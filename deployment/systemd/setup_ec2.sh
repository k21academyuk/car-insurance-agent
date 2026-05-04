#!/usr/bin/env bash
###############################################################################
# Car Insurance Agent — EC2 Setup (Ubuntu 26.04)
#
# Provisions a fresh Ubuntu 26.04 EC2 instance with:
#   - System updates + Docker + Docker Compose
#   - Python 3.13 (system default)
#   - .env scaffolding (auto-generated, public IP detection)
#   - UFW firewall (22/80/443)
#   - NGINX reverse proxy
#   - Systemd service for boot persistence
#
# PREREQUISITE: Clone the repo BEFORE running this script:
#   cd ~
#   git clone https://github.com/k21academyuk/car-insurance-agent.git
#   cd car-insurance-agent
#   sudo bash deployment/systemd/setup_ec2.sh
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
APP_DIR="${APP_HOME}/car-insurance-agent"
APP_PORT=8000

# ─── 0. Pre-flight ───────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "       Car Insurance Agent — EC2 Setup (Ubuntu 26.04)"
echo "================================================================"
echo ""

if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash setup_ec2.sh"
fi

log "Checking application directory: ${APP_DIR}"
if [[ ! -d "${APP_DIR}" ]]; then
    error "Application directory not found at ${APP_DIR}.
       Please clone the repository first:
           cd ~
           git clone https://github.com/k21academyuk/car-insurance-agent.git
           cd car-insurance-agent
           sudo bash deployment/systemd/setup_ec2.sh"
fi
success "Application directory found"

if ! command -v lsb_release &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq lsb-release
fi
UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)
log "Detected: Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

if ! curl -sSf --max-time 10 https://github.com >/dev/null 2>&1; then
    error "No internet — check security group allows outbound 443"
fi
success "Pre-flight passed"

# ─── 1. System update ────────────────────────────────────────────────────────
log "Step 1/8 — System update..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip ca-certificates gnupg \
    software-properties-common apt-transport-https \
    ufw nano openssl
success "System packages updated"

# ─── 2. Docker + Compose ─────────────────────────────────────────────────────
log "Step 2/8 — Installing Docker + Compose..."
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    DOCKER_CODENAME="${UBUNTU_CODENAME}"
    if ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${UBUNTU_CODENAME}/Release" >/dev/null 2>&1; then
        warn "Docker repo for '${UBUNTU_CODENAME}' not yet published — using 'noble' (24.04)"
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
fi
success "Docker: $(docker --version)"
success "Compose: $(docker compose version)"

# ─── 3. Configure .env ───────────────────────────────────────────────────────
log "Step 3/8 — Configuring .env..."
ENV_FILE="${APP_DIR}/backend/.env"
ENV_EXAMPLE="${APP_DIR}/backend/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
    warn ".env exists — leaving alone"
elif [[ ! -f "${ENV_EXAMPLE}" ]]; then
    warn ".env.example missing"
else
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"

    # Detect public IP (IMDSv2)
    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
    if [[ -n "${TOKEN}" ]]; then
        PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
            --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    else
        PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi

    if [[ -n "${PUBLIC_IP}" ]]; then
        sed -i "s|CORS_ORIGINS=.*|CORS_ORIGINS=http://localhost:8000,http://${PUBLIC_IP}|g" "${ENV_FILE}" 2>/dev/null || true
        success "Public IP: ${PUBLIC_IP}"
    fi

    chown "${APP_USER}:${APP_USER}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    success ".env created at ${ENV_FILE}"
    warn "⚠️  EDIT IT TO ADD YOUR OPENAI_API_KEY: sudo nano ${ENV_FILE}"
fi

# ─── 4. UFW firewall ─────────────────────────────────────────────────────────
log "Step 4/8 — Firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment 'SSH'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable >/dev/null 2>&1
success "UFW: 22/80/443 open"

# ─── 5. NGINX ────────────────────────────────────────────────────────────────
log "Step 5/8 — NGINX reverse proxy..."
apt-get install -y -qq nginx
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/car-insurance-agent <<NGINX_EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 25M;
    gzip on;
    gzip_types text/plain text/css application/json application/javascript;
    gzip_min_length 256;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/car-insurance-agent /etc/nginx/sites-enabled/

if nginx -t 2>/dev/null; then
    systemctl restart nginx
    systemctl enable nginx
    success "NGINX configured"
else
    error "NGINX config test failed"
fi

# ─── 6. Build the Docker image ───────────────────────────────────────────────
log "Step 6/8 — Building Docker image (this takes 3–5 minutes)..."
cd "${APP_DIR}/deployment/docker"
sudo -u "${APP_USER}" docker compose build 2>&1 | tail -20
success "Docker image built"

# ─── 7. Systemd service ──────────────────────────────────────────────────────
log "Step 7/8 — Installing systemd service..."

cat > /etc/systemd/system/car-insurance-agent.service <<SYSTEMD_EOF
[Unit]
Description=Car Insurance Agent — Multi-Agent AI
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

ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart

StandardOutput=journal
StandardError=journal
SyslogIdentifier=car-insurance-agent

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable car-insurance-agent.service
success "Service enabled"

# ─── 8. Done ─────────────────────────────────────────────────────────────────
log "Step 8/8 — Setup complete!"
echo ""
echo "================================================================"
echo -e "${GREEN}✅ Car Insurance Agent ready to launch!${NC}"
echo "================================================================"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo -e "${BLUE}1.${NC} Add your OpenAI API key:"
echo "      sudo nano ${ENV_FILE}"
echo ""
echo -e "${BLUE}2.${NC} Start the service:"
echo "      sudo systemctl start car-insurance-agent"
echo ""
echo -e "${BLUE}3.${NC} Wait ~30 seconds, then ingest the knowledge base:"
echo "      cd ${APP_DIR}/deployment/docker"
echo "      docker compose exec app python scripts/ingest_kb.py"
echo ""

# Re-fetch public IP
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
if [[ -n "${TOKEN}" ]]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
        --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
else
    PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
fi

echo -e "${BLUE}4.${NC} Open in browser:"
echo "      Chat UI:    http://${PUBLIC_IP}/"
echo "      API docs:   http://${PUBLIC_IP}/docs"
echo "      Health:     http://${PUBLIC_IP}/health"
echo ""
echo -e "${YELLOW}USEFUL COMMANDS:${NC}"
echo "      Status:    sudo systemctl status car-insurance-agent"
echo "      Logs:      sudo journalctl -u car-insurance-agent -f"
echo "      App logs:  cd ${APP_DIR}/deployment/docker && docker compose logs -f"
echo "      Restart:   sudo systemctl restart car-insurance-agent"
echo "      Update:    cd ${APP_DIR} && git pull && cd deployment/docker && \\"
echo "                 docker compose build && sudo systemctl restart car-insurance-agent"
echo ""
echo "================================================================"
