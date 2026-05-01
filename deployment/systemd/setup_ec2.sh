#!/usr/bin/env bash
###############################################################################
# AutoShield AI — EC2 Setup Script for Ubuntu 26.04 LTS "Resolute Raccoon"
#
# Provisions a fresh Ubuntu 26.04 EC2 instance with everything needed:
#   - System updates + essential packages
#   - Docker + Docker Compose (via official Docker repo)
#   - Python 3.13 (system default — no PPA needed)
#   - Node.js 20 (NodeSource)
#   - Repository clone
#   - .env scaffolding with auto-generated JWT secret
#   - UFW firewall (22/80/443)
#   - NGINX reverse proxy with WebSocket + 25MB upload + 5min LLM timeouts
#   - Systemd service for boot persistence
#
# Usage on a fresh Ubuntu 26.04 EC2 instance:
#   sudo chmod +x setup_ec2.sh
#   sudo bash setup_ec2.sh
#
# Recommended EC2: t3.medium or larger (4 GB RAM, 30 GB EBS)
###############################################################################

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1" >&2; exit 1; }

# ─── Configuration ───────────────────────────────────────────────────────────
APP_USER="ubuntu"
APP_HOME="/home/${APP_USER}"
APP_DIR="${APP_HOME}/autoshield-ai"
REPO_URL="${REPO_URL:-https://github.com/prashant9501/autoshield-ai.git}"
BRANCH="${BRANCH:-main}"

FRONTEND_PORT=3000
BACKEND_PORT=8000

# ─── 0. Pre-flight ───────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "  AutoShield AI — Ubuntu 26.04 LTS (Resolute Raccoon) Setup"
echo "================================================================"
echo ""

if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash setup_ec2.sh"
fi

# Verify Ubuntu 26.04
if ! command -v lsb_release &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq lsb-release
fi

UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)

log "Detected: Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

if [[ "${UBUNTU_VERSION}" != "26.04" ]]; then
    warn "This script is optimized for Ubuntu 26.04. You're on ${UBUNTU_VERSION}."
    warn "Continuing — but use the version-aware script if you hit issues."
fi

# Clean any junk from prior failed runs
rm -f /etc/apt/sources.list.d/deadsnakes*.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/*deadsnakes*.sources 2>/dev/null || true

if ! id "${APP_USER}" &>/dev/null; then
    error "User '${APP_USER}' missing — script expects default Ubuntu EC2 user"
fi

if ! curl -sSf --max-time 10 https://github.com >/dev/null 2>&1; then
    error "No internet — check security group allows outbound 443"
fi

success "Pre-flight passed"

# ─── 1. System update ────────────────────────────────────────────────────────
log "Step 1/10 — System update..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https build-essential \
    htop ufw jq vim nano openssl pkg-config
success "System packages updated"

# ─── 2. Python 3.13 (system default — already present) ───────────────────────
log "Step 2/10 — Verifying Python 3.13 (Ubuntu 26.04 default)..."

apt-get install -y -qq python3 python3-pip python3-venv python3-dev python3-full

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
log "System Python: ${PYTHON_VERSION}"

PY_MAJOR=$(echo "${PYTHON_VERSION}" | cut -d. -f1)
PY_MINOR=$(echo "${PYTHON_VERSION}" | cut -d. -f2)
if [[ "${PY_MAJOR}" -lt 3 ]] || { [[ "${PY_MAJOR}" -eq 3 ]] && [[ "${PY_MINOR}" -lt 12 ]]; }; then
    error "Python ${PYTHON_VERSION} too old. Need 3.12+ for LangGraph."
fi
success "Python: ${PYTHON_VERSION}"

# ─── 3. Docker + Docker Compose (official repo) ──────────────────────────────
log "Step 3/10 — Installing Docker + Compose..."

if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Try the actual codename first; fall back to noble (24.04) if Docker
    # hasn't published packages for resolute yet (sometimes lags by a few weeks)
    DOCKER_CODENAME="${UBUNTU_CODENAME}"
    if ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${UBUNTU_CODENAME}/Release" >/dev/null 2>&1; then
        warn "Docker repo for '${UBUNTU_CODENAME}' not yet published — falling back to 'noble' (24.04 packages)"
        DOCKER_CODENAME="noble"
    fi

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${DOCKER_CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    usermod -aG docker "${APP_USER}"
    success "Docker installed: $(docker --version)"
else
    success "Docker already installed: $(docker --version)"
fi

success "Docker Compose: $(docker compose version)"

# ─── 4. Node.js 20 (NodeSource) ──────────────────────────────────────────────
log "Step 4/10 — Installing Node.js 20..."

if ! command -v node &>/dev/null || [[ "$(node --version)" != v20* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi
success "Node.js: $(node --version)"
success "npm: $(npm --version)"

# ─── 5. Clone repository ─────────────────────────────────────────────────────
log "Step 5/10 — Setting up repository..."

if [[ -d "${APP_DIR}/.git" ]]; then
    warn "Repo exists — pulling latest"
    cd "${APP_DIR}"
    sudo -u "${APP_USER}" git fetch origin
    sudo -u "${APP_USER}" git checkout "${BRANCH}" 2>/dev/null || \
        sudo -u "${APP_USER}" git checkout -b "${BRANCH}" "origin/${BRANCH}"
    sudo -u "${APP_USER}" git pull origin "${BRANCH}"
elif [[ -d "${APP_DIR}" ]]; then
    warn "Directory exists but not a git repo. Backing up..."
    mv "${APP_DIR}" "${APP_DIR}.bak.$(date +%s)"
    sudo -u "${APP_USER}" git clone -b "${BRANCH}" "${REPO_URL}" "${APP_DIR}"
else
    sudo -u "${APP_USER}" git clone -b "${BRANCH}" "${REPO_URL}" "${APP_DIR}"
fi

chown -R "${APP_USER}:${APP_USER}" "${APP_DIR}"
success "Repository ready at ${APP_DIR}"

# ─── 6. Configure .env ───────────────────────────────────────────────────────
log "Step 6/10 — Configuring .env..."

ENV_FILE="${APP_DIR}/backend/.env"
ENV_EXAMPLE="${APP_DIR}/backend/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
    warn ".env exists — leaving alone (delete to regenerate)"
else
    [[ -f "${ENV_EXAMPLE}" ]] || error ".env.example missing at ${ENV_EXAMPLE}"
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"

    JWT_SECRET=$(openssl rand -hex 32)
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" "${ENV_FILE}"

    # IMDSv2 (token-required metadata) — Ubuntu 26.04 EC2 AMIs default to IMDSv2
    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
    PUBLIC_IP=""
    if [[ -n "${TOKEN}" ]]; then
        PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
            --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    else
        # Fallback to IMDSv1
        PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi

    if [[ -n "${PUBLIC_IP}" ]]; then
        sed -i "s|CORS_ORIGINS=.*|CORS_ORIGINS=http://localhost:3000,http://${PUBLIC_IP}|g" "${ENV_FILE}"
        success "Detected public IP: ${PUBLIC_IP}"
    else
        warn "Could not auto-detect public IP — edit CORS_ORIGINS manually"
    fi

    chown "${APP_USER}:${APP_USER}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    success ".env created at ${ENV_FILE}"
    warn "⚠️  YOU MUST ADD YOUR OPENAI_API_KEY: sudo nano ${ENV_FILE}"
fi

# ─── 7. UFW firewall ─────────────────────────────────────────────────────────
log "Step 7/10 — Firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment 'SSH'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable >/dev/null 2>&1
success "UFW enabled (22, 80, 443)"

# ─── 8. NGINX reverse proxy ──────────────────────────────────────────────────
log "Step 8/10 — NGINX reverse proxy..."
apt-get install -y -qq nginx
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/autoshield <<NGINX_EOF
upstream autoshield_frontend { server 127.0.0.1:${FRONTEND_PORT}; }
upstream autoshield_backend  { server 127.0.0.1:${BACKEND_PORT}; }

# Allow large damage image uploads for claims
client_max_body_size 25M;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    gzip_min_length 256;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # Backend API
    location /api/ {
        proxy_pass http://autoshield_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # WebSocket (chat streaming)
    location /ws/ {
        proxy_pass http://autoshield_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location /docs        { proxy_pass http://autoshield_backend; proxy_set_header Host \$host; }
    location /openapi.json { proxy_pass http://autoshield_backend; proxy_set_header Host \$host; }
    location /health      { proxy_pass http://autoshield_backend; access_log off; }
    location /metrics     { proxy_pass http://autoshield_backend; }

    # Frontend (Next.js) — catch-all
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
    error "NGINX config test failed"
fi

# ─── 9. Systemd service ──────────────────────────────────────────────────────
log "Step 9/10 — Installing systemd service..."

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

ExecStartPre=/usr/bin/docker compose pull --ignore-pull-failures
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart

StandardOutput=journal
StandardError=journal
SyslogIdentifier=autoshield

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable autoshield.service
success "autoshield.service installed and enabled"

# ─── 10. Pre-pull Docker images ──────────────────────────────────────────────
log "Step 10/10 — Pre-pulling Docker images (this may take a few minutes)..."

cd "${APP_DIR}/deployment/docker"
sudo -u "${APP_USER}" docker compose pull --ignore-pull-failures 2>&1 | grep -E "Pulling|Pulled|Status" || true
success "Docker images ready"

# ─── Final ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo -e "${GREEN}✅ AutoShield AI is ready to launch!${NC}"
echo "================================================================"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo -e "${BLUE}1.${NC} Add your OpenAI API key:"
echo "      sudo nano ${ENV_FILE}"
echo "      # Set OPENAI_API_KEY=sk-proj-..."
echo "      # (Optional) Set LANGSMITH_API_KEY=lsv2_pt_..."
echo ""
echo -e "${BLUE}2.${NC} Start the application:"
echo "      sudo systemctl start autoshield"
echo ""
echo -e "${BLUE}3.${NC} Wait ~60 seconds, then check status:"
echo "      sudo systemctl status autoshield"
echo "      cd ${APP_DIR}/deployment/docker && docker compose ps"
echo ""
echo -e "${BLUE}4.${NC} (After Phase 1 code is in place) Initialize the database:"
echo "      cd ${APP_DIR}/deployment/docker"
echo "      docker compose exec backend alembic upgrade head"
echo "      docker compose exec backend python -m app.database.seed"
echo "      docker compose exec backend python scripts/ingest_kb.py"
echo ""
echo -e "${BLUE}5.${NC} Access the application:"

# Re-fetch public IP using IMDSv2
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
if [[ -n "${TOKEN}" ]]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
        --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
else
    PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
fi

echo "      Frontend:    http://${PUBLIC_IP}/"
echo "      API Docs:    http://${PUBLIC_IP}/docs"
echo "      Health:      http://${PUBLIC_IP}/health"
echo ""
echo -e "${YELLOW}USEFUL COMMANDS:${NC}"
echo "      Service status:    sudo systemctl status autoshield"
echo "      Live logs:         sudo journalctl -u autoshield -f"
echo "      Container logs:    cd ${APP_DIR}/deployment/docker && docker compose logs -f"
echo "      Backend only:      cd ${APP_DIR}/deployment/docker && docker compose logs -f backend"
echo "      Restart:           sudo systemctl restart autoshield"
echo "      Stop:              sudo systemctl stop autoshield"
echo "      Update from git:   cd ${APP_DIR} && git pull && sudo systemctl restart autoshield"
echo ""
echo -e "${YELLOW}OPTIONAL — ENABLE HTTPS (Let's Encrypt):${NC}"
echo "      sudo apt-get install -y certbot python3-certbot-nginx"
echo "      sudo certbot --nginx -d your-domain.com"
echo ""
echo -e "${YELLOW}TROUBLESHOOTING:${NC}"
echo "      • Docker permission denied → log out and back in"
echo "      • Port already in use      → sudo lsof -i :8000"
echo "      • Out of disk             → docker system prune -af"
echo "      • Backend won't start     → check OPENAI_API_KEY in ${ENV_FILE}"
echo ""
echo "================================================================"
success "Setup finished. Edit .env, then: sudo systemctl start autoshield"
echo "================================================================"
