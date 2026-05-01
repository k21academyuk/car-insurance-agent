#!/usr/bin/env bash
###############################################################################
# Car Insurance Agent — EC2 Setup Script for Ubuntu 26.04 LTS
#
# Provisions a fresh Ubuntu 26.04 EC2 instance with:
#   - System updates + essential packages
#   - Python 3.13 (system default)
#   - Docker + Docker Compose
#   - Node.js 20
#   - .env scaffolding (auto-generated JWT secret + public IP)
#   - UFW firewall (22 / 80 / 443)
#   - NGINX reverse proxy
#   - Systemd service for boot persistence
#
# PREREQUISITE: Clone the repo BEFORE running this script.
#
#   cd ~
#   git clone https://github.com/k21academyuk/car-insurance-agent.git
#   cd car-insurance-agent
#   sudo chmod +x deployment/systemd/setup_ec2.sh
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

FRONTEND_PORT=3000
BACKEND_PORT=8000

# ─── 0. Pre-flight ───────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo "       Car Insurance Agent — EC2 Setup (Ubuntu 26.04)"
echo "================================================================"
echo ""

if [[ $EUID -ne 0 ]]; then
    error "Run as root: sudo bash setup_ec2.sh"
fi

# Verify the repo has been cloned (matches the pattern you like)
log "Checking application directory: ${APP_DIR}"
if [[ ! -d "${APP_DIR}" ]]; then
    echo ""
    error "Application directory not found at ${APP_DIR}.
       Please clone the repository first:
           cd ~
           git clone https://github.com/k21academyuk/car-insurance-agent.git
           cd car-insurance-agent
           sudo bash deployment/systemd/setup_ec2.sh"
fi
success "Application directory found"

# Clean up junk from any prior failed runs
rm -f /etc/apt/sources.list.d/deadsnakes*.list 2>/dev/null || true
rm -f /etc/apt/sources.list.d/*deadsnakes*.sources 2>/dev/null || true
rm -rf "${APP_HOME}/autoshield-ai" 2>/dev/null || true

if ! command -v lsb_release &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq lsb-release
fi

UBUNTU_VERSION=$(lsb_release -rs)
UBUNTU_CODENAME=$(lsb_release -cs)
log "Detected: Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

if [[ "${UBUNTU_VERSION}" != "26.04" ]]; then
    warn "Script targets Ubuntu 26.04. You're on ${UBUNTU_VERSION} — proceeding anyway."
fi

if ! curl -sSf --max-time 10 https://github.com >/dev/null 2>&1; then
    error "No internet — check security group allows outbound 443"
fi

success "Pre-flight passed"

# ─── 1. System update ────────────────────────────────────────────────────────
log "Step 1/9 — System update..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    curl wget git unzip ca-certificates gnupg lsb-release \
    software-properties-common apt-transport-https build-essential \
    htop ufw jq vim nano openssl pkg-config
success "System packages updated"

# ─── 2. Python 3.13 (system default) ─────────────────────────────────────────
log "Step 2/9 — Verifying Python..."
apt-get install -y -qq python3 python3-pip python3-venv python3-dev python3-full

PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
PY_MAJOR=$(echo "${PYTHON_VERSION}" | cut -d. -f1)
PY_MINOR=$(echo "${PYTHON_VERSION}" | cut -d. -f2)
if [[ "${PY_MAJOR}" -lt 3 ]] || { [[ "${PY_MAJOR}" -eq 3 ]] && [[ "${PY_MINOR}" -lt 12 ]]; }; then
    error "Python ${PYTHON_VERSION} is too old. Need 3.12+"
fi
success "Python: ${PYTHON_VERSION}"

# ─── 3. Docker + Docker Compose ──────────────────────────────────────────────
log "Step 3/9 — Installing Docker + Compose..."

if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    DOCKER_CODENAME="${UBUNTU_CODENAME}"
    if ! curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${UBUNTU_CODENAME}/Release" >/dev/null 2>&1; then
        warn "Docker repo for '${UBUNTU_CODENAME}' not yet published — using 'noble' (24.04) packages"
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

# ─── 4. Node.js 20 ───────────────────────────────────────────────────────────
log "Step 4/9 — Installing Node.js 20..."
if ! command -v node &>/dev/null || [[ "$(node --version)" != v20* ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y -qq nodejs
fi
success "Node.js: $(node --version)"
success "npm: $(npm --version)"

# ─── 5. Configure .env ───────────────────────────────────────────────────────
log "Step 5/9 — Configuring .env..."

ENV_FILE="${APP_DIR}/backend/.env"
ENV_EXAMPLE="${APP_DIR}/backend/.env.example"

if [[ -f "${ENV_FILE}" ]]; then
    warn ".env exists — leaving alone (delete to regenerate)"
elif [[ ! -f "${ENV_EXAMPLE}" ]]; then
    warn ".env.example missing at ${ENV_EXAMPLE} — skipping (create manually later)"
else
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"

    JWT_SECRET=$(openssl rand -hex 32)
    sed -i "s|JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" "${ENV_FILE}" 2>/dev/null || true

    # Detect public IP (IMDSv2 with v1 fallback)
    TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
    if [[ -n "${TOKEN}" ]]; then
        PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
            --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    else
        PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    fi

    if [[ -n "${PUBLIC_IP}" ]]; then
        sed -i "s|CORS_ORIGINS=.*|CORS_ORIGINS=http://localhost:3000,http://${PUBLIC_IP}|g" "${ENV_FILE}" 2>/dev/null || true
        success "Detected public IP: ${PUBLIC_IP}"
    fi

    chown "${APP_USER}:${APP_USER}" "${ENV_FILE}"
    chmod 600 "${ENV_FILE}"
    success ".env created at ${ENV_FILE}"
    warn "⚠️  EDIT IT TO ADD YOUR OPENAI_API_KEY: sudo nano ${ENV_FILE}"
fi

# ─── 6. UFW firewall ─────────────────────────────────────────────────────────
log "Step 6/9 — Firewall..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp  comment 'SSH'
ufw allow 80/tcp  comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force enable >/dev/null 2>&1
success "UFW enabled (22, 80, 443)"

# ─── 7. NGINX reverse proxy ──────────────────────────────────────────────────
log "Step 7/9 — NGINX reverse proxy..."
apt-get install -y -qq nginx
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/car-insurance-agent <<NGINX_EOF
upstream ci_frontend { server 127.0.0.1:${FRONTEND_PORT}; }
upstream ci_backend  { server 127.0.0.1:${BACKEND_PORT}; }

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

    location /api/ {
        proxy_pass http://ci_backend;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /ws/ {
        proxy_pass http://ci_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 86400s;
    }

    location /docs        { proxy_pass http://ci_backend; proxy_set_header Host \$host; }
    location /openapi.json { proxy_pass http://ci_backend; proxy_set_header Host \$host; }
    location /health      { proxy_pass http://ci_backend; access_log off; }
    location /metrics     { proxy_pass http://ci_backend; }

    location / {
        proxy_pass http://ci_frontend;
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

ln -sf /etc/nginx/sites-available/car-insurance-agent /etc/nginx/sites-enabled/car-insurance-agent

if nginx -t 2>/dev/null; then
    systemctl restart nginx
    systemctl enable nginx
    success "NGINX configured and running"
else
    error "NGINX config test failed"
fi

# ─── 8. Systemd service ──────────────────────────────────────────────────────
log "Step 8/9 — Installing systemd service..."

# Auto-detect docker-compose location inside the repo
COMPOSE_DIR=""
for candidate in \
    "${APP_DIR}/deployment/docker" \
    "${APP_DIR}/deployment" \
    "${APP_DIR}/docker" \
    "${APP_DIR}"; do
    if [[ -f "${candidate}/docker-compose.yml" ]] || [[ -f "${candidate}/compose.yml" ]]; then
        COMPOSE_DIR="${candidate}"
        break
    fi
done

if [[ -z "${COMPOSE_DIR}" ]]; then
    warn "No docker-compose.yml found yet — service will fail to start until it exists"
    COMPOSE_DIR="${APP_DIR}/deployment/docker"
fi
log "Compose directory: ${COMPOSE_DIR}"

cat > /etc/systemd/system/car-insurance-agent.service <<SYSTEMD_EOF
[Unit]
Description=Car Insurance Agent — Multi-Agent AI Platform
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${COMPOSE_DIR}
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
SyslogIdentifier=car-insurance-agent

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

systemctl daemon-reload
systemctl enable car-insurance-agent.service
success "car-insurance-agent.service installed and enabled"

# ─── 9. Pre-pull Docker images ───────────────────────────────────────────────
log "Step 9/9 — Pre-pulling Docker images..."
if [[ -f "${COMPOSE_DIR}/docker-compose.yml" ]] || [[ -f "${COMPOSE_DIR}/compose.yml" ]]; then
    cd "${COMPOSE_DIR}"
    sudo -u "${APP_USER}" docker compose pull --ignore-pull-failures 2>&1 | grep -E "Pulling|Pulled|Status" || true
    success "Docker images ready"
else
    warn "Skipping image pre-pull (no compose file yet)"
fi

# ─── Final summary ───────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo -e "${GREEN}✅ Setup complete!${NC}"
echo "================================================================"
echo ""
echo -e "${YELLOW}NEXT STEPS:${NC}"
echo ""
echo -e "${BLUE}1.${NC} Add your OpenAI API key:"
echo "      sudo nano ${ENV_FILE}"
echo "      # Set OPENAI_API_KEY=sk-proj-..."
echo ""
echo -e "${BLUE}2.${NC} Start the service:"
echo "      sudo systemctl start car-insurance-agent"
echo ""
echo -e "${BLUE}3.${NC} Check status (wait ~60s):"
echo "      sudo systemctl status car-insurance-agent"
echo "      cd ${COMPOSE_DIR} && docker compose ps"
echo ""

TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 2>/dev/null || echo "")
if [[ -n "${TOKEN}" ]]; then
    PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: ${TOKEN}" \
        --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
else
    PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "YOUR-EC2-IP")
fi

echo -e "${BLUE}4.${NC} Open in browser:"
echo "      Frontend:    http://${PUBLIC_IP}/"
echo "      API Docs:    http://${PUBLIC_IP}/docs"
echo "      Health:      http://${PUBLIC_IP}/health"
echo ""
echo -e "${YELLOW}USEFUL COMMANDS:${NC}"
echo "      Status:    sudo systemctl status car-insurance-agent"
echo "      Logs:      sudo journalctl -u car-insurance-agent -f"
echo "      Restart:   sudo systemctl restart car-insurance-agent"
echo "      Stop:      sudo systemctl stop car-insurance-agent"
echo "      Update:    cd ${APP_DIR} && git pull && sudo systemctl restart car-insurance-agent"
echo ""
echo "================================================================"
success "Done! Edit .env, then: sudo systemctl start car-insurance-agent"
echo "================================================================"
