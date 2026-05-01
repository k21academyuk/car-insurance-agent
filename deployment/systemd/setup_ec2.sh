#!/usr/bin/env bash
###############################################################################
# AutoShield AI — Automated EC2 Setup Script
#
# Provisions a fresh Ubuntu 24.04 LTS EC2 instance with everything needed to
# run the AutoShield AI multi-agent platform:
#   - System updates + essential packages
#   - Docker + Docker Compose
#   - Python 3.12 + Node.js 20 (host-side, for scripts)
#   - Repository setup at /home/ubuntu/autoshield-ai
#   - .env file scaffolding
#   - NGINX reverse proxy
#   - Systemd service for auto-start on boot
#   - UFW firewall rules
#   - Optional: Let's Encrypt SSL via Certbot
#
# Usage (on a fresh EC2 instance):
#   sudo chmod +x deployment/systemd/setup_ec2.sh
#   sudo bash deployment/systemd/setup_ec2.sh
#
# Recommended EC2: t3.medium or larger (2 vCPU, 4GB RAM minimum)
# OS: Ubuntu 24.04 LTS
# Storage: 30 GB EBS minimum (Docker images + ChromaDB + Postgres data)
###############################################################################

set -euo pipefail

# ─── Colors for readable output ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# ─── Configuration ───────────────────────────────────────────────────────────
APP_USER="ubuntu"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/autoshield-ai"
REPO_URL="${REPO_URL:-https://github.com/prashant9501/autoshield-ai.git}"
BRANCH="${BRANCH:-main}"

# Service ports (exposed on host via NGINX)
FRONTEND_PORT=3000
BACKEND_PORT=8000
GRAFANA_PORT=3001
PROMETHEUS_PORT=9090

# ─── 0. Pre-flight checks ────────────────────────────────────────────────────
log "AutoShield AI — EC2 Setup Script"
echo "================================================"

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root: sudo bash setup_ec2.sh"
fi

if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
    warn "This script is tested on Ubuntu 24.04. You're on something else — proceeding anyway."
fi

if ! id "${APP_USER}" &>/dev/null; then
    error "User '${APP_USER}' does not exist. This script expects the default Ubuntu EC2 user."
fi

# Check internet
if ! curl -sSf https://github.com >/dev/null 2>&1; then
    error "No internet connectivity. Check your security group / NACL allows outbound 443."
fi

success "Pre-flight checks passed"

# ─── 1. System update ────────────────────────────────────────────────────────
log "Step 1/10 — Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl \
    wget \
    git \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    build-essential \
    htop \
    ufw \
    jq \
    vim \
    nano

success "System packages updated"

# ─── 2. Install Docker + Docker Compose ──────────────────────────────────────
log "Step 2/10 — Installing Docker + Docker Compose..."

if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    # Add ubuntu user to docker group (so non-root can run docker)
    usermod -aG docker "${APP_USER}"

    success "Docker installed: $(docker --version)"
    success "Docker Compose: $(docker compose version)"
else
    success "Docker already installed: $(docker --version)"
fi

# ─── 3. Install Python 3.12 + Node.js 20 (host tools) ────────────────────────
log "Step 3/10 — Installing Python 3.12 and Node.js 20 (host tools)..."

# Python 3.12 (Ubuntu 24.04 ships with it by default)
if ! command -v python3.12 &>/dev/null; then
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update -qq
    apt-get install -y -qq python3.12 python3.12-venv python3.12-dev python3-pip
fi
success "Python: $(python3.12 --version)"

# Node.js 20 (NodeSource)
if ! command -v node &>/dev/null || [[ "$(node --version)" != v20* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi
success "Node.js: $(node --version)"

# ─── 4. Clone repository ─────────────────────────────────────────────────────
log "Step 4/10 — Cloning repository..."

if [[ -d "${APP_DIR}/.git" ]]; then
    warn "Repo already exists at ${APP_DIR}, pulling latest..."
    cd "${APP_DIR}"
    sudo -u "${APP_USER}" git fetch origin
    sudo -u "${APP_USER}" git checkout "${BRANCH}"
    sudo -u "${APP_USER}" git pull origin "${BRANCH}"
else
    sudo -u "${APP_USER}" git clone -b "${BRANCH}" "${REPO_URL}" "${APP_DIR}"
fi

chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
success "Repository ready at ${APP_DIR}"

# ─── 5. Configure .env file ──────────────────────────────────────────────────
log "Step 5/10 — Configuring .env file..."

ENV_FILE="${APP_DIR}/backend/.env"
ENV_EXAMPLE="${APP_DIR}/backend/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
    warn ".env already exists — leaving it alone (delete it manually to regenerate)"
else
    if [[ ! -f "${ENV_EXAMPLE}" ]]; then
        error ".env.example not found at ${ENV_EXAMPLE} — repo may be incomplete"
    fi

    cp "${ENV_EXAMPLE}" "${ENV_FILE}"

    # Generate a strong JWT secret automatically
    JWT_SECRET=$(openssl rand -hex 32)
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" "${ENV_FILE}"

    # Update CORS origins to include the public IP
    PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 || echo "")
    if [[ -n "${PUBLIC_IP}" ]]; then
        sed -i "s|CORS_ORIGINS=.*|CORS_ORIGINS=http://localhost:3000,http://${PUBLIC_IP}|g" "${ENV_FILE}"
        success "Detected public IP: ${PUBLIC_IP}"
    fi

    chown "${APP_USER}:${APP_USER}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    success ".env file created at ${ENV_FILE}"
    warn "⚠️  YOU MUST EDIT IT TO ADD YOUR OPENAI_API_KEY:"
    warn "    sudo nano ${ENV_FILE}"
fi

# ─── 6. Configure UFW firewall ───────────────────────────────────────────────
log "Step 6/10 — Configuring UFW firewall..."

ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp     comment 'SSH'
ufw allow 80/tcp     comment 'HTTP'
ufw allow 443/tcp    comment 'HTTPS'
ufw --force enable >/dev/null 2>&1
success "UFW firewall enabled (22, 80, 443 open)"

# ─── 7. Configure NGINX reverse proxy ────────────────────────────────────────
log "Step 7/10 — Installing & configuring NGINX..."
apt-get install -y -qq nginx

# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Write AutoShield site config
cat > /etc/nginx/sites-available/autoshield <<NGINX_EOF
# AutoShield AI — NGINX reverse proxy
# Routes traffic from port 80 to the appropriate Docker service.

upstream autoshield_frontend {
    server 127.0.0.1:${FRONTEND_PORT};
}

upstream autoshield_backend {
    server 127.0.0.1:${BACKEND_PORT};
}

# Increase max upload size for damage images (claims) and policy docs
client_max_body_size 25M;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Gzip compression
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_min_length 256;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # ─── Backend API ──────────────────────────────────────
    location /api/ {
        proxy_pass http://autoshield_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;     # Long timeouts for LLM calls
        proxy_send_timeout 300s;
    }

    # ─── WebSocket (chat streaming) ───────────────────────
    location /ws/ {
        proxy_pass http://autoshield_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;   # Keep-alive for chat
    }

    # ─── FastAPI docs (Swagger) ───────────────────────────
    location /docs {
        proxy_pass http://autoshield_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
    location /openapi.json {
        proxy_pass http://autoshield_backend;
        proxy_set_header Host \$host;
    }

    # ─── Health check ─────────────────────────────────────
    location /health {
        proxy_pass http://autoshield_backend;
        access_log off;
    }

    # ─── Prometheus metrics (admin only — IP-restrict in prod) ───
    location /metrics {
        proxy_pass http://autoshield_backend;
        # Uncomment to lock down to your office IP:
        # allow 1.2.3.4;
        # deny all;
    }

    # ─── Frontend (Next.js) — catch-all ───────────────────
    location / {
        proxy_pass http://autoshield_frontend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/autoshield /etc/nginx/sites-enabled/autoshield

if nginx -t 2>/dev/null; then
    systemctl restart nginx
    systemctl enable nginx
    success "NGINX configured and running"
else
    error "NGINX config test failed — check /etc/nginx/sites-available/autoshield"
fi

# ─── 8. Install systemd service for auto-start ───────────────────────────────
log "Step 8/10 — Installing systemd service..."

cat > /etc/systemd/system/autoshield.service <<SYSTEMD_EOF
[Unit]
Description=AutoShield AI — Multi-Agent Car Insurance Platform
Documentation=https://github.com/prashant9501/autoshield-ai
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_DIR}/deployment/docker
TimeoutStartSec=600
TimeoutStopSec=120
Restart=on-failure
RestartSec=10

# Pull latest images then bring stack up
ExecStartPre=/usr/bin/docker compose pull --ignore-pull-failures
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=autoshield

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable autoshield.service
success "Systemd service installed: autoshield.service"

# ─── 9. Pre-pull Docker images (saves time on first start) ───────────────────
log "Step 9/10 — Pre-pulling Docker images (this may take a few minutes)..."

cd "${APP_DIR}/deployment/docker"
sudo -u "${APP_USER}" docker compose pull --ignore-pull-failures 2>&1 | grep -E "Pulling|Pulled|Status" || true

success "Docker images ready"

# ─── 10. Final instructions ──────────────────────────────────────────────────
log "Step 10/10 — Setup complete!"
echo ""
echo "================================================================"
echo -e "${GREEN}✅ AutoShield AI is ready to launch!${NC}"
echo "================================================================"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo -e "${BLUE}1.${NC} Add your OpenAI API key:"
echo "      sudo nano ${ENV_FILE}"
echo "      # Set: OPENAI_API_KEY=sk-proj-..."
echo "      # (Optional) Set: LANGSMITH_API_KEY=lsv2_pt_..."
echo ""
echo -e "${BLUE}2.${NC} Start the application:"
echo "      sudo systemctl start autoshield"
echo ""
echo -e "${BLUE}3.${NC} Wait ~60 seconds for all services to come up, then check status:"
echo "      sudo systemctl status autoshield"
echo "      cd ${APP_DIR}/deployment/docker && docker compose ps"
echo ""
echo -e "${BLUE}4.${NC} Initialize the database (first time only):"
echo "      cd ${APP_DIR}/deployment/docker"
echo "      docker compose exec backend alembic upgrade head"
echo "      docker compose exec backend python -m app.database.seed"
echo "      docker compose exec backend python scripts/ingest_kb.py"
echo "      docker compose exec backend python -m app.ml_models.train_risk"
echo "      docker compose exec backend python -m app.ml_models.train_fraud"
echo ""
echo -e "${BLUE}5.${NC} Access the application:"

PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 || echo "YOUR-EC2-IP")
echo "      Frontend:    http://${PUBLIC_IP}/"
echo "      API Docs:    http://${PUBLIC_IP}/docs"
echo "      Health:      http://${PUBLIC_IP}/health"
echo ""
echo -e "${YELLOW}USEFUL COMMANDS:${NC}"
echo "      Check service:       sudo systemctl status autoshield"
echo "      View logs (live):    sudo journalctl -u autoshield -f"
echo "      Container logs:      cd ${APP_DIR}/deployment/docker && docker compose logs -f"
echo "      Backend logs only:   cd ${APP_DIR}/deployment/docker && docker compose logs -f backend"
echo "      Restart:             sudo systemctl restart autoshield"
echo "      Stop:                sudo systemctl stop autoshield"
echo "      Update from git:     cd ${APP_DIR} && git pull && sudo systemctl restart autoshield"
echo ""
echo -e "${YELLOW}OPTIONAL — ENABLE HTTPS (Let's Encrypt):${NC}"
echo "      sudo apt-get install -y certbot python3-certbot-nginx"
echo "      sudo certbot --nginx -d your-domain.com"
echo ""
echo -e "${YELLOW}TROUBLESHOOTING:${NC}"
echo "      • Docker permission denied  → log out and back in (group change)"
echo "      • Port already in use       → sudo lsof -i :8000  (find conflicting process)"
echo "      • Out of disk               → docker system prune -af"
echo "      • Backend won't start       → check OPENAI_API_KEY in ${ENV_FILE}"
echo ""
echo "================================================================"
success "Setup script finished. Edit .env and run: sudo systemctl start autoshield"
echo "================================================================"
