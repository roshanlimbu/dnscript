#!/usr/bin/env bash

# =================================================================
#  DeployNest — Full Server Bootstrap & Install Script
#  Runs on a fresh Ubuntu 22.04 / 24.04 server
#
#  What this does:
#   1. Installs system deps: git, curl, unzip, build-essential
#   2. Installs Docker + Docker Compose plugin
#   3. Installs Bun (JS runtime)
#   4. Installs Rust + Cargo
#   5. Installs PHP 8.2 + extensions (for Laravel deployments)
#   6. Clones all 3 public repos
#   7. Installs project dependencies (bun install, cargo build)
#   8. Sets up .env files
#   9. Optionally runs DB migrations
#  10. Optionally starts Caddy via Docker Compose
# =================================================================

set -euo pipefail
export COMPOSER_ALLOW_SUPERUSER=1

# ── Colors ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "\n${CYAN}==>${NC} ${BOLD}$1${NC}"; }
success() { echo -e "  ${GREEN}✔${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}⚠${NC}  $1"; }
error()   { echo -e "  ${RED}✘${NC}  $1"; exit 1; }
step()    { echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; \
            echo -e "${BOLD}${CYAN}  $1${NC}"; \
            echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# ── Banner ────────────────────────────────────────────────────────
clear
echo ""
echo -e "${BOLD}${CYAN}"
echo "  ██████╗ ███████╗██████╗ ██╗      ██████╗ ██╗   ██╗███╗   ██╗███████╗███████╗████████╗"
echo "  ██╔══██╗██╔════╝██╔══██╗██║     ██╔═══██╗╚██╗ ██╔╝████╗  ██║██╔════╝██╔════╝╚══██╔══╝"
echo "  ██║  ██║█████╗  ██████╔╝██║     ██║   ██║ ╚████╔╝ ██╔██╗ ██║█████╗  ███████╗   ██║   "
echo "  ██║  ██║██╔══╝  ██╔═══╝ ██║     ██║   ██║  ╚██╔╝  ██║╚██╗██║██╔══╝  ╚════██║   ██║   "
echo "  ██████╔╝███████╗██║     ███████╗╚██████╔╝   ██║   ██║ ╚████║███████╗███████║   ██║   "
echo "  ╚═════╝ ╚══════╝╚═╝     ╚══════╝ ╚═════╝    ╚═╝   ╚═╝  ╚═══╝╚══════╝╚══════╝   ╚═╝   "
echo -e "${NC}"
echo -e "  ${BOLD}Full Server Bootstrap & Installer${NC}"
echo -e "  ${DIM}Docker · Bun · Rust · PHP · Nginx Proxy Manager · All Repos${NC}"
echo ""

# ── Root check ────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Please run as root:  sudo bash install.sh"
fi

# ── OS check ──────────────────────────────────────────────────────
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_VERSION="${VERSION_ID:-}"
else
    error "Cannot detect OS. This script supports Ubuntu 22.04/24.04."
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    warn "This script is optimized for Ubuntu/Debian. Detected: ${OS_ID}. Proceeding anyway..."
fi

# =================================================================
#  CONFIGURATION
# =================================================================
step "Configuration"

# Repo URLs — update these to your actual GitHub org/username
BACKEND_REPO="${BACKEND_REPO:-https://github.com/roshanlimbu/deploynest.git}"
FRONTEND_REPO="${FRONTEND_REPO:-https://github.com/roshanlimbu/DN_front.git}"
WORKER_REPO="${WORKER_REPO:-https://github.com/roshanlimbu/Deploynestworker.git}"

# Where to clone everything
INSTALL_DIR="${INSTALL_DIR:-/opt/deploynest}"

# Directories
BACKEND_DIR="$INSTALL_DIR/deploynest"
FRONTEND_DIR="$INSTALL_DIR/DN_front"
WORKER_DIR="$INSTALL_DIR/Deploynestworker"

# Flags (can be set via env vars too)
WITH_CADDY="${WITH_CADDY:-0}"
WITH_MIGRATIONS="${WITH_MIGRATIONS:-0}"
WITH_NPM="${WITH_NPM:-0}"    # Nginx Proxy Manager

# Domain config (set interactively below or via env vars)
FRONTEND_DOMAIN="${FRONTEND_DOMAIN:-}"
API_DOMAIN="${API_DOMAIN:-}"
SSL_EMAIL="${SSL_EMAIL:-}"

echo -e "  ${BOLD}Install directory:${NC}  ${CYAN}${INSTALL_DIR}${NC}"
echo -e "  ${BOLD}Backend repo:${NC}       ${CYAN}${BACKEND_REPO}${NC}"
echo -e "  ${BOLD}Frontend repo:${NC}      ${CYAN}${FRONTEND_REPO}${NC}"
echo -e "  ${BOLD}Worker repo:${NC}        ${CYAN}${WORKER_REPO}${NC}"
echo ""

# Parse CLI flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --with-caddy)       WITH_CADDY=1;      shift ;;
        --with-migrations)  WITH_MIGRATIONS=1; shift ;;
        --with-npm)         WITH_NPM=1;        shift ;;
        --install-dir)      INSTALL_DIR="$2";  shift 2 ;;
        --backend-repo)     BACKEND_REPO="$2"; shift 2 ;;
        --frontend-repo)    FRONTEND_REPO="$2";shift 2 ;;
        --worker-repo)      WORKER_REPO="$2";  shift 2 ;;
        --domain)           FRONTEND_DOMAIN="$2"; shift 2 ;;
        --api-domain)       API_DOMAIN="$2";      shift 2 ;;
        --ssl-email)        SSL_EMAIL="$2";        shift 2 ;;
        -y|--yes)           AUTO_YES=1;        shift ;;
        -h|--help)
            cat <<'EOF'
Usage: sudo bash install.sh [options]

Options:
  --with-caddy          Start the worker Caddy service after install
  --with-migrations     Run Drizzle DB migrations after install
  --with-npm            Deploy Nginx Proxy Manager via Docker
  --domain DOMAIN       Frontend domain  (e.g. deploynest.com)
  --api-domain DOMAIN   Backend API domain (e.g. api.deploynest.com)
  --ssl-email EMAIL     Email for Let's Encrypt SSL certificate
  --install-dir PATH    Where to clone repos (default: /opt/deploynest)
  --backend-repo URL    Override backend repo URL
  --frontend-repo URL   Override frontend repo URL
  --worker-repo URL     Override worker repo URL
  -y, --yes             Skip confirmation prompt (auto-yes)
  -h, --help            Show this help

Environment variable overrides:
  BACKEND_REPO, FRONTEND_REPO, WORKER_REPO, INSTALL_DIR
  FRONTEND_DOMAIN, API_DOMAIN, SSL_EMAIL
  WITH_CADDY=1, WITH_MIGRATIONS=1, WITH_NPM=1
EOF
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo -e "  ${DIM}Options: caddy=${WITH_CADDY}  migrations=${WITH_MIGRATIONS}  npm=${WITH_NPM}${NC}"
echo ""

# ── Domain prompts (interactive only — skipped if piped or --yes) ──
if [[ "${AUTO_YES:-0}" -ne 1 ]] && [[ -t 0 ]]; then
    echo -e "  ${BOLD}${CYAN}Domain Setup${NC}  ${DIM}(press Enter to skip and use IP:port instead)${NC}"
    echo ""
    read -rp "  Frontend domain  (e.g. deploynest.com or app.deploynest.com): " _DOMAIN_INPUT
    if [[ -n "$_DOMAIN_INPUT" ]]; then
        FRONTEND_DOMAIN="$_DOMAIN_INPUT"
        read -rp "  API subdomain    (e.g. api.deploynest.com) [leave blank to skip]: " _API_INPUT
        API_DOMAIN="${_API_INPUT:-}"
        read -rp "  Email for SSL certificate (Let's Encrypt): " _EMAIL_INPUT
        SSL_EMAIL="${_EMAIL_INPUT:-}"
    fi
    echo ""
fi

# ── Show domain plan ──────────────────────────────────────────────
if [[ -n "$FRONTEND_DOMAIN" ]]; then
    echo -e "  ${BOLD}Domain plan:${NC}"
    echo -e "    Frontend  :  ${CYAN}https://${FRONTEND_DOMAIN}${NC}  → port ${FRONTEND_PORT:-8080}"
    [[ -n "$API_DOMAIN" ]] && \
    echo -e "    API       :  ${CYAN}https://${API_DOMAIN}${NC}  → port ${BACKEND_PORT:-4000}"
    [[ -n "$SSL_EMAIL" ]] && \
    echo -e "    SSL email :  ${CYAN}${SSL_EMAIL}${NC}"
else
    warn "No domain provided — app will be reachable at IP:port only."
fi
echo ""

# Auto-confirm if: --yes flag passed, or stdin is not a terminal (e.g. curl | bash)
if [[ "${AUTO_YES:-0}" -eq 1 ]] || [[ ! -t 0 ]]; then
    warn "Non-interactive mode detected — auto-confirming."
else
    read -rp "  Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM="${CONFIRM:-Y}"
    [[ "$CONFIRM" =~ ^[Yy]$ ]] || { warn "Aborted."; exit 0; }
fi

# =================================================================
#  STEP 1 — System Update & Core Packages
# =================================================================
step "1 · System Update & Core Packages"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
    git \
    curl \
    wget \
    unzip \
    zip \
    build-essential \
    pkg-config \
    ca-certificates \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https \
    openssl \
    libssl-dev

success "Core packages installed."

# =================================================================
#  STEP 2 — Docker + Docker Compose
# =================================================================
step "2 · Docker & Docker Compose"

if command -v docker &>/dev/null; then
    success "Docker already installed: $(docker --version)"
else
    info "Installing Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker
    success "Docker installed: $(docker --version)"
fi

if docker compose version &>/dev/null; then
    success "Docker Compose: $(docker compose version)"
else
    error "Docker Compose plugin not found. Check Docker installation."
fi

# Add current non-root user to docker group (if script run via sudo)
REAL_USER="${SUDO_USER:-$USER}"
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
    usermod -aG docker "$REAL_USER" && \
        success "Added '${REAL_USER}' to docker group (re-login to take effect)."
fi

# =================================================================
#  STEP 3 — Bun (JS Runtime)
# =================================================================
step "3 · Bun"

if command -v bun &>/dev/null; then
    success "Bun already installed: $(bun --version)"
else
    info "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash

    # Make bun available system-wide
    BUN_BIN="$HOME/.bun/bin"
    if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
        BUN_BIN="/home/${REAL_USER}/.bun/bin"
    fi

    if [[ -f "${BUN_BIN}/bun" ]]; then
        ln -sf "${BUN_BIN}/bun" /usr/local/bin/bun
        success "Bun installed: $(bun --version)"
    else
        # Fallback: try the root path
        ln -sf "/root/.bun/bin/bun" /usr/local/bin/bun 2>/dev/null || \
            warn "Bun symlink failed. You may need to add ~/.bun/bin to PATH manually."
    fi
fi

# =================================================================
#  STEP 4 — Rust + Cargo
# =================================================================
step "4 · Rust & Cargo"

if command -v cargo &>/dev/null; then
    success "Cargo already installed: $(cargo --version)"
else
    info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path

    # Make cargo available system-wide
    CARGO_BIN="$HOME/.cargo/bin"
    if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
        CARGO_BIN="/home/${REAL_USER}/.cargo/bin"
    fi

    export PATH="${CARGO_BIN}:$PATH"

    if [[ -f "${CARGO_BIN}/cargo" ]]; then
        ln -sf "${CARGO_BIN}/cargo"  /usr/local/bin/cargo
        ln -sf "${CARGO_BIN}/rustc"  /usr/local/bin/rustc
        ln -sf "${CARGO_BIN}/rustup" /usr/local/bin/rustup
        success "Rust installed: $(cargo --version)"
    else
        warn "Cargo not found at ${CARGO_BIN}. Trying /root/.cargo/bin..."
        export PATH="/root/.cargo/bin:$PATH"
        ln -sf "/root/.cargo/bin/cargo"  /usr/local/bin/cargo  2>/dev/null || true
        ln -sf "/root/.cargo/bin/rustc"  /usr/local/bin/rustc  2>/dev/null || true
    fi
fi

# =================================================================
#  STEP 5 — PHP 8.3 + Extensions (for Laravel deployment support)
# =================================================================
# Set PHP version here — change to 8.4 if needed
PHP_VERSION="${PHP_VERSION:-8.3}"
step "5 · PHP ${PHP_VERSION} + Extensions"

if command -v php &>/dev/null; then
    success "PHP already installed: $(php --version | head -1)"
else
    info "Adding Ondrej PHP PPA..."
    add-apt-repository -y ppa:ondrej/php
    apt-get update -qq

    info "Installing PHP ${PHP_VERSION} + Laravel extensions..."
    apt-get install -y -qq \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-tokenizer" \
        "php${PHP_VERSION}-fileinfo"
    # Note: sodium and pcntl are compiled into PHP 8.3+ by default — no separate package needed

    systemctl enable "php${PHP_VERSION}-fpm"
    systemctl start  "php${PHP_VERSION}-fpm"
    success "PHP installed: $(php --version | head -1)"
fi

# =================================================================
#  STEP 6 — Composer (PHP dependency manager)
# =================================================================
step "6 · Composer"

if command -v composer &>/dev/null; then
    success "Composer already installed: $(composer --version --no-ansi | head -1)"
else
    info "Installing Composer..."
    php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');"
    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
    rm /tmp/composer-setup.php
    success "Composer installed: $(composer --version --no-ansi | head -1)"
fi

# =================================================================
#  STEP 7 — Nginx Proxy Manager (optional)
# =================================================================
if [[ "$WITH_NPM" -eq 1 ]]; then
    step "7 · Nginx Proxy Manager"

    NPM_DIR="/opt/nginx-proxy-manager"
    mkdir -p "$NPM_DIR"

    cat > "$NPM_DIR/docker-compose.yml" <<'NPMEOF'
version: '3.8'
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
    networks:
      - proxy

networks:
  proxy:
    name: proxy
    driver: bridge
NPMEOF

    docker compose -f "$NPM_DIR/docker-compose.yml" up -d
    success "Nginx Proxy Manager started."
    warn "Admin panel: http://YOUR_SERVER_IP:81"
    warn "Default login → Email: admin@example.com  Password: changeme"
else
    info "Skipping Nginx Proxy Manager. Re-run with --with-npm to enable."
fi

# =================================================================
#  STEP 8 — Create shared Docker network (for all apps + NPM)
# =================================================================
step "8 · Docker Network"

if docker network ls | grep -q "^.*proxy"; then
    success "Docker 'proxy' network already exists."
else
    docker network create proxy
    success "Created shared Docker network: proxy"
fi

# =================================================================
#  STEP 9 — Clone Repos
# =================================================================
step "9 · Cloning Repositories"

mkdir -p "$INSTALL_DIR"

clone_or_pull() {
    local repo="$1"
    local dest="$2"
    local name
    name=$(basename "$dest")

    if [[ -d "$dest/.git" ]]; then
        info "Updating existing repo: ${name}"
        git -C "$dest" pull --ff-only
        success "${name} updated."
    else
        info "Cloning: ${repo}"
        git clone --depth=1 "$repo" "$dest"
        success "${name} cloned."
    fi
}

clone_or_pull "$BACKEND_REPO"  "$BACKEND_DIR"
clone_or_pull "$FRONTEND_REPO" "$FRONTEND_DIR"
clone_or_pull "$WORKER_REPO"   "$WORKER_DIR"

# =================================================================
#  STEP 10 — Database & Environment Setup
# =================================================================
step "10 · Database & Environment Setup"

info "Installing PostgreSQL Server..."
apt-get install -y -qq postgresql postgresql-contrib
systemctl enable postgresql
systemctl start postgresql
sleep 3

info "Configuring PostgreSQL deploynest database..."
# Generate random password
DB_PASS=$(openssl rand -hex 16)
DB_USER="deploynest"
DB_NAME="deploynest"

sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};" || true
sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASS}';" || sudo -u postgres psql -c "ALTER USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASS}';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};"
sudo -u postgres psql -d ${DB_NAME} -c "ALTER SCHEMA public OWNER TO ${DB_USER};"

success "Database '${DB_NAME}' created with user '${DB_USER}'."

DATABASE_URL="postgres://${DB_USER}:${DB_PASS}@127.0.0.1:5432/${DB_NAME}"
JWT_SECRET=$(openssl rand -hex 32)

# ── Backend .env ───────────────────────────────────────────────
if [[ -f "$BACKEND_DIR/.env.example" && ! -f "$BACKEND_DIR/.env" ]]; then
    cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|g" "$BACKEND_DIR/.env"
    sed -i "s|^DB_HOST=.*|DB_HOST=127.0.0.1|g" "$BACKEND_DIR/.env"
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=${DB_NAME}|g" "$BACKEND_DIR/.env"
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=${DB_USER}|g" "$BACKEND_DIR/.env"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=${DB_PASS}|g" "$BACKEND_DIR/.env"
    sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|g" "$BACKEND_DIR/.env"
    success "Created and configured backend .env"
elif [[ ! -f "$BACKEND_DIR/.env" ]]; then
    cat > "$BACKEND_DIR/.env" <<EOF
DATABASE_URL=${DATABASE_URL}
JWT_SECRET=${JWT_SECRET}
PORT=${BACKEND_PORT:-4000}
NODE_ENV=production
EOF
    success "Generated default backend .env"
else
    warn "Keeping existing backend .env but forcefully updating DATABASE_URL"
    if grep -q "^DATABASE_URL=" "$BACKEND_DIR/.env"; then
        sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|g" "$BACKEND_DIR/.env"
    else
        echo "DATABASE_URL=${DATABASE_URL}" >> "$BACKEND_DIR/.env"
    fi
fi

# ── Worker .env ────────────────────────────────────────────────
WORKER_BASE_DOMAIN="${FRONTEND_DOMAIN:-localhost}"
WORKER_SCHEME="http"
[[ -n "$FRONTEND_DOMAIN" ]] && WORKER_SCHEME="https"

if [[ ! -f "$WORKER_DIR/.env" ]]; then
    cat > "$WORKER_DIR/.env" <<EOF
DATABASE_URL=${DATABASE_URL}
WORKSPACE_DIR=/tmp/deploynest
POLL_INTERVAL_SECONDS=5
CONTAINER_PORT=3000
PORT_START=4001
PORT_END=9000
CADDY_ADMIN_URL=http://127.0.0.1:2019
CADDY_SERVER=srv0
CADDY_UPSTREAM_HOST=host.docker.internal
BASE_DOMAIN=${WORKER_BASE_DOMAIN}
PUBLIC_SCHEME=${WORKER_SCHEME}
EOF
    success "Generated default worker .env"
else
    warn "Keeping existing worker .env but forcefully updating DATABASE_URL and BASE_DOMAIN"
    if grep -q "^DATABASE_URL=" "$WORKER_DIR/.env"; then
        sed -i "s|^DATABASE_URL=.*|DATABASE_URL=${DATABASE_URL}|g" "$WORKER_DIR/.env"
    else
        echo "DATABASE_URL=${DATABASE_URL}" >> "$WORKER_DIR/.env"
    fi
    if grep -q "^BASE_DOMAIN=" "$WORKER_DIR/.env"; then
        sed -i "s|^BASE_DOMAIN=.*|BASE_DOMAIN=${WORKER_BASE_DOMAIN}|g" "$WORKER_DIR/.env"
    else
        echo "BASE_DOMAIN=${WORKER_BASE_DOMAIN}" >> "$WORKER_DIR/.env"
    fi
    if grep -q "^PUBLIC_SCHEME=" "$WORKER_DIR/.env"; then
        sed -i "s|^PUBLIC_SCHEME=.*|PUBLIC_SCHEME=${WORKER_SCHEME}|g" "$WORKER_DIR/.env"
    else
        echo "PUBLIC_SCHEME=${WORKER_SCHEME}" >> "$WORKER_DIR/.env"
    fi
fi

# ── Frontend .env ──────────────────────────────────────────────
if [[ -f "$FRONTEND_DIR/.env.example" && ! -f "$FRONTEND_DIR/.env" ]]; then
    cp "$FRONTEND_DIR/.env.example" "$FRONTEND_DIR/.env"
    # Auto-inject backend URL if known
    API_URL="http://127.0.0.1:${BACKEND_PORT:-4000}"
    [[ -n "$API_DOMAIN" ]] && API_URL="https://${API_DOMAIN}"
    sed -i "s|^NEXT_PUBLIC_API_URL=.*|NEXT_PUBLIC_API_URL=${API_URL}|g" "$FRONTEND_DIR/.env"
    success "Created frontend .env"
else
    warn "Keeping existing frontend .env (or no .env.example found)"
fi

# =================================================================
#  STEP 11 — Install Dependencies
# =================================================================
step "11 · Installing Project Dependencies"

info "Installing backend dependencies (bun install)..."
(cd "$BACKEND_DIR" && bun install)
success "Backend deps installed."

info "Installing frontend dependencies (bun install)..."
(cd "$FRONTEND_DIR" && bun install)
success "Frontend deps installed."

info "Building worker (cargo build --release)..."
(cd "$WORKER_DIR" && cargo build --release)
success "Worker built."

# =================================================================
#  STEP 12 — Database Migrations (optional)
# =================================================================
if [[ "$WITH_MIGRATIONS" -eq 1 ]]; then
    step "12 · Database Migrations"
    info "Running Drizzle migrations..."
    (cd "$BACKEND_DIR" && bun run db:migrate)
    success "Migrations complete."
else
    warn "Skipping migrations. Run with --with-migrations when PostgreSQL is ready."
fi

# =================================================================
#  STEP 13 — Start Caddy (optional)
# =================================================================
if [[ "$WITH_CADDY" -eq 1 ]]; then
    step "13 · Starting Caddy"
    (cd "$WORKER_DIR" && docker compose up -d caddy)
    success "Caddy started via Docker Compose."
else
    warn "Skipping Caddy. Run with --with-caddy to start it."
fi

# =================================================================
#  STEP 14 — Systemd Services (Backend + Frontend)
# =================================================================
step "14 · Setting Up Services (Backend + Frontend)"

BUN_BIN=$(command -v bun || echo "/usr/local/bin/bun")
BACKEND_PORT="${BACKEND_PORT:-4000}"
FRONTEND_PORT="${FRONTEND_PORT:-8080}"

# ── Backend service ────────────────────────────────────────────
info "Creating systemd service: deploynest-backend (port ${BACKEND_PORT})..."
cat > /etc/systemd/system/deploynest-backend.service <<SVCEOF
[Unit]
Description=DeployNest Backend (Bun)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${BACKEND_DIR}
ExecStart=${BUN_BIN} run dev
Restart=always
RestartSec=5
Environment=PORT=${BACKEND_PORT}
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=deploynest-backend

[Install]
WantedBy=multi-user.target
SVCEOF

success "Backend service created."

# ── Frontend service ───────────────────────────────────────────
info "Building frontend for production..."
(cd "$FRONTEND_DIR" && bun run build) && success "Frontend built." || warn "Frontend build failed — check package.json scripts."

info "Creating systemd service: deploynest-frontend (port ${FRONTEND_PORT})..."
cat > /etc/systemd/system/deploynest-frontend.service <<SVCEOF
[Unit]
Description=DeployNest Frontend (Next.js)
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${FRONTEND_DIR}
ExecStart=${BUN_BIN} run start
Restart=always
RestartSec=5
Environment=PORT=${FRONTEND_PORT}
Environment=NODE_ENV=production
StandardOutput=journal
StandardError=journal
SyslogIdentifier=deploynest-frontend

[Install]
WantedBy=multi-user.target
SVCEOF

success "Frontend service created."

# ── Worker service ─────────────────────────────────────────────
WORKER_BIN="${WORKER_DIR}/target/release/deploynestworker"
info "Creating systemd service: deploynest-worker..."
cat > /etc/systemd/system/deploynest-worker.service <<SVCEOF
[Unit]
Description=DeployNest Worker (Rust)
After=network.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=${WORKER_DIR}
ExecStart=${WORKER_BIN}
Restart=always
RestartSec=5
EnvironmentFile=${WORKER_DIR}/.env
StandardOutput=journal
StandardError=journal
SyslogIdentifier=deploynest-worker

[Install]
WantedBy=multi-user.target
SVCEOF
success "Worker service created."

# ── Enable + start all ─────────────────────────────────────────
systemctl daemon-reload

systemctl enable deploynest-backend
systemctl restart deploynest-backend
success "Backend started  → http://localhost:${BACKEND_PORT}"

systemctl enable deploynest-frontend
systemctl restart deploynest-frontend
success "Frontend started → http://localhost:${FRONTEND_PORT}"

systemctl enable deploynest-worker
systemctl restart deploynest-worker
success "Worker started   (picks up deployment jobs)"

# =================================================================
#  STEP 15 — Nginx Vhost + SSL (if domain provided)
# =================================================================
if [[ -n "$FRONTEND_DOMAIN" ]]; then
    step "15 · Nginx + SSL for ${FRONTEND_DOMAIN}"

    # Install Nginx + Certbot
    info "Installing Nginx and Certbot..."
    apt-get install -y -qq nginx certbot python3-certbot-nginx
    systemctl enable nginx
    systemctl start  nginx
    success "Nginx installed."

    # ── Frontend vhost ────────────────────────────────────────────
    info "Creating Nginx vhost: ${FRONTEND_DOMAIN} → port ${FRONTEND_PORT}..."
    cat > "/etc/nginx/sites-available/${FRONTEND_DOMAIN}" <<NGINXEOF
server {
    listen 80;
    server_name ${FRONTEND_DOMAIN};

    client_max_body_size 64M;
    charset utf-8;

    # Gzip
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml text/javascript;

    # Security headers
    add_header X-Frame-Options        "SAMEORIGIN"  always;
    add_header X-Content-Type-Options "nosniff"     always;
    add_header Referrer-Policy        "strict-origin-when-cross-origin" always;

    location / {
        proxy_pass         http://127.0.0.1:${FRONTEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 60s;
    }



    access_log /var/log/nginx/${FRONTEND_DOMAIN}-access.log;
    error_log  /var/log/nginx/${FRONTEND_DOMAIN}-error.log;
}
NGINXEOF

    ln -sf "/etc/nginx/sites-available/${FRONTEND_DOMAIN}" \
           "/etc/nginx/sites-enabled/${FRONTEND_DOMAIN}"
    success "Frontend vhost created: ${FRONTEND_DOMAIN}"

    # ── API subdomain vhost ───────────────────────────────────────
    if [[ -n "$API_DOMAIN" ]]; then
        info "Creating Nginx vhost: ${API_DOMAIN} → port ${BACKEND_PORT}..."
        cat > "/etc/nginx/sites-available/${API_DOMAIN}" <<NGINXEOF
server {
    listen 80;
    server_name ${API_DOMAIN};

    client_max_body_size 64M;
    charset utf-8;

    # CORS headers
    add_header Access-Control-Allow-Origin  "${FRONTEND_DOMAIN}" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Authorization, Content-Type, Accept" always;

    location / {
        if (\$request_method = 'OPTIONS') {
            return 204;
        }
        proxy_pass         http://127.0.0.1:${BACKEND_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 120s;
    }

    access_log /var/log/nginx/${API_DOMAIN}-access.log;
    error_log  /var/log/nginx/${API_DOMAIN}-error.log;
}
NGINXEOF

        ln -sf "/etc/nginx/sites-available/${API_DOMAIN}" \
               "/etc/nginx/sites-enabled/${API_DOMAIN}"
        success "API vhost created: ${API_DOMAIN}"
    fi

    # Remove default nginx site if present
    rm -f /etc/nginx/sites-enabled/default

    nginx -t && systemctl reload nginx
    success "Nginx reloaded."

    # ── SSL via Certbot ───────────────────────────────────────────
    if [[ -n "$SSL_EMAIL" ]]; then
        info "Requesting Let's Encrypt SSL certificate..."

        CERTBOT_DOMAINS="-d ${FRONTEND_DOMAIN}"
        [[ -n "$API_DOMAIN" ]] && CERTBOT_DOMAINS="${CERTBOT_DOMAINS} -d ${API_DOMAIN}"

        certbot --nginx \
            --non-interactive \
            --agree-tos \
            --redirect \
            --email "${SSL_EMAIL}" \
            ${CERTBOT_DOMAINS} && \
            success "SSL certificate installed! Auto-renew enabled." || \
            warn "Certbot failed — DNS may not be propagated yet. Run manually: certbot --nginx -d ${FRONTEND_DOMAIN}"

        # Enable auto-renew timer
        systemctl enable certbot.timer 2>/dev/null || \
            (crontab -l 2>/dev/null; echo "0 12 * * * certbot renew --quiet") | crontab -
    else
        warn "No SSL email provided — skipping HTTPS. Add SSL later with:"
        warn "  certbot --nginx -d ${FRONTEND_DOMAIN}"
    fi

else
    info "No domain configured. Skipping Nginx vhost setup."
    warn "If using Nginx Proxy Manager, add proxy hosts:"
    warn "  yourdomain.com      → localhost:${FRONTEND_PORT}"
    warn "  api.yourdomain.com  → localhost:${BACKEND_PORT}"
fi

# =================================================================
#  DONE — Summary
# =================================================================
echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  ✅  DeployNest Installation Complete!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Install Directory:${NC}   ${INSTALL_DIR}"
echo -e "  ${BOLD}Docker:${NC}             $(docker --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}Bun:${NC}                $(bun --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}Cargo:${NC}              $(cargo --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}PHP:${NC}                $(php --version 2>/dev/null | head -1 || echo 'installed')"
echo ""
echo -e "  ${BOLD}${GREEN}Services Running:${NC}"
if [[ -n "$FRONTEND_DOMAIN" ]]; then
    echo -e "  ${DIM}Frontend:${NC}  ${CYAN}https://${FRONTEND_DOMAIN}${NC}"
    [[ -n "$API_DOMAIN" ]] && \
    echo -e "  ${DIM}API:${NC}       ${CYAN}https://${API_DOMAIN}${NC}"
else
    echo -e "  ${DIM}Frontend:${NC}  http://YOUR_IP:${FRONTEND_PORT}   (systemd: deploynest-frontend)"
    echo -e "  ${DIM}Backend:${NC}   http://YOUR_IP:${BACKEND_PORT}    (systemd: deploynest-backend)"
fi
echo ""
echo -e "  ${YELLOW}${BOLD}Next steps:${NC}"
echo -e "  ${DIM}1.${NC}  Edit backend .env  →  ${CYAN}nano ${BACKEND_DIR}/.env${NC}"
echo -e "  ${DIM}2.${NC}  Edit worker .env   →  ${CYAN}nano ${WORKER_DIR}/.env${NC}"
if [[ "${WITH_NPM:-0}" -eq 1 ]]; then
    echo -e "  ${DIM}3.${NC}  Open NPM admin     →  ${CYAN}http://YOUR_IP:81${NC}  (admin@example.com / changeme)"
fi
echo -e ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "  ${DIM}Status:${NC}   sudo systemctl status deploynest-backend deploynest-frontend"
echo -e "  ${DIM}Logs:${NC}     sudo journalctl -u deploynest-backend -f"
echo -e "           sudo journalctl -u deploynest-frontend -f"
echo -e "  ${DIM}Restart:${NC}  sudo systemctl restart deploynest-backend"
echo -e "           sudo systemctl restart deploynest-frontend"
echo -e "           sudo systemctl restart deploynest-worker"
echo -e ""
echo -e "  ${BOLD}Re-run options:${NC}"
echo -e "  ${DIM}With migrations:${NC}  sudo bash install.sh --with-migrations"
echo -e "  ${DIM}With Caddy:${NC}       sudo bash install.sh --with-caddy"
echo -e "  ${DIM}With NPM:${NC}         sudo bash install.sh --with-npm"
echo ""
echo -e "  ${DIM}Note: Log out and back in for Docker group to take effect.${NC}"
echo ""



echo ""
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${GREEN}  ✅  DeployNest Installation Complete!${NC}"
echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  ${BOLD}Install Directory:${NC}   ${INSTALL_DIR}"
echo -e "  ${BOLD}Docker:${NC}             $(docker --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}Bun:${NC}                $(bun --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}Cargo:${NC}              $(cargo --version 2>/dev/null || echo 'installed')"
echo -e "  ${BOLD}PHP:${NC}                $(php --version 2>/dev/null | head -1 || echo 'installed')"
echo ""
  echo -e "  ${BOLD}${GREEN}Services Running:${NC}"
  echo -e "  ${DIM}Backend:${NC}   http://localhost:${BACKEND_PORT:-4000}   (systemd: deploynest-backend)"
  echo -e "  ${DIM}Frontend:${NC}  http://localhost:${FRONTEND_PORT:-8080}  (systemd: deploynest-frontend)"
  echo -e "  ${DIM}Worker:${NC}    Rust worker polling DB every 5s            (systemd: deploynest-worker)"
  echo ""
echo -e "  ${YELLOW}${BOLD}Next steps:${NC}"
echo -e "  ${DIM}1.${NC}  Edit backend .env  →  ${CYAN}nano ${BACKEND_DIR}/.env${NC}"
echo -e "  ${DIM}2.${NC}  Edit worker .env   →  ${CYAN}nano ${WORKER_DIR}/.env${NC}"
if [[ "${WITH_NPM:-0}" -eq 1 ]]; then
    echo -e "  ${DIM}3.${NC}  Open NPM admin     →  ${CYAN}http://YOUR_IP:81${NC}  (admin@example.com / changeme)"
    echo -e "  ${DIM}4.${NC}  In NPM add hosts:"
    echo -e "          yourdomain.com      → localhost:${FRONTEND_PORT:-8080}"
    echo -e "          api.yourdomain.com  → localhost:${BACKEND_PORT:-4000}"
fi
echo -e ""
echo -e "  ${BOLD}Service management:${NC}"
echo -e "  ${DIM}Status:${NC}   sudo systemctl status deploynest-backend deploynest-frontend"
echo -e "  ${DIM}Logs:${NC}     sudo journalctl -u deploynest-backend -f"
echo -e "           sudo journalctl -u deploynest-frontend -f"
echo -e "  ${DIM}Restart:${NC}  sudo systemctl restart deploynest-backend"
echo -e "           sudo systemctl restart deploynest-frontend"
echo -e ""
echo -e "  ${BOLD}Re-run options:${NC}"
echo -e "  ${DIM}With migrations:${NC}  sudo bash install.sh --with-migrations"
echo -e "  ${DIM}With Caddy:${NC}       sudo bash install.sh --with-caddy"
echo -e "  ${DIM}With NPM:${NC}         sudo bash install.sh --with-npm"
echo ""
echo -e "  ${DIM}Note: Log out and back in for Docker group to take effect.${NC}"
echo ""
