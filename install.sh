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
        -h|--help)
            cat <<'EOF'
Usage: sudo bash install.sh [options]

Options:
  --with-caddy          Start the worker Caddy service after install
  --with-migrations     Run Drizzle DB migrations after install
  --with-npm            Deploy Nginx Proxy Manager via Docker
  --install-dir PATH    Where to clone repos (default: /opt/deploynest)
  --backend-repo URL    Override backend repo URL
  --frontend-repo URL   Override frontend repo URL
  --worker-repo URL     Override worker repo URL
  -h, --help            Show this help

Environment variable overrides:
  BACKEND_REPO, FRONTEND_REPO, WORKER_REPO, INSTALL_DIR
  WITH_CADDY=1, WITH_MIGRATIONS=1, WITH_NPM=1
EOF
            exit 0 ;;
        -y|--yes)           AUTO_YES=1;        shift ;;
        -h|--help)
            cat <<'EOF'
Usage: sudo bash install.sh [options]

Options:
  --with-caddy          Start the worker Caddy service after install
  --with-migrations     Run Drizzle DB migrations after install
  --with-npm            Deploy Nginx Proxy Manager via Docker
  --install-dir PATH    Where to clone repos (default: /opt/deploynest)
  --backend-repo URL    Override backend repo URL
  --frontend-repo URL   Override frontend repo URL
  --worker-repo URL     Override worker repo URL
  -y, --yes             Skip confirmation prompt (auto-yes)
  -h, --help            Show this help

Environment variable overrides:
  BACKEND_REPO, FRONTEND_REPO, WORKER_REPO, INSTALL_DIR
  WITH_CADDY=1, WITH_MIGRATIONS=1, WITH_NPM=1
EOF
            exit 0 ;;
        *)
            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo -e "  ${DIM}Options: caddy=${WITH_CADDY}  migrations=${WITH_MIGRATIONS}  npm=${WITH_NPM}${NC}"
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
#  STEP 10 — Environment Files
# =================================================================
step "10 · Environment Files"

copy_if_missing() {
    local src="$1" dst="$2"
    if [[ -f "$dst" ]]; then
        warn "Keeping existing: ${dst#$INSTALL_DIR/}"
    elif [[ -f "$src" ]]; then
        cp "$src" "$dst"
        success "Created: ${dst#$INSTALL_DIR/}"
    else
        warn "No .env.example found at ${src#$INSTALL_DIR/} — skipping."
    fi
}

# Backend .env
if [[ ! -f "$BACKEND_DIR/.env" ]]; then
    if [[ -f "$BACKEND_DIR/.env.example" ]]; then
        cp "$BACKEND_DIR/.env.example" "$BACKEND_DIR/.env"
    else
        cat > "$BACKEND_DIR/.env" <<'EOF'
DATABASE_URL=postgresql://localhost:5432/deploynest
JWT_SECRET=change-me-before-production
PORT=3000
NODE_ENV=production
EOF
    fi
    success "Created deploynest/.env — edit DATABASE_URL and JWT_SECRET!"
else
    warn "Keeping existing deploynest/.env"
fi

# Worker .env
copy_if_missing "$WORKER_DIR/.env.example" "$WORKER_DIR/.env"

# Frontend .env
copy_if_missing "$FRONTEND_DIR/.env.example" "$FRONTEND_DIR/.env"

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
echo -e "  ${YELLOW}${BOLD}Next steps:${NC}"
echo -e "  ${DIM}1.${NC}  Edit backend .env  →  ${CYAN}nano ${BACKEND_DIR}/.env${NC}"
echo -e "  ${DIM}2.${NC}  Edit worker .env   →  ${CYAN}nano ${WORKER_DIR}/.env${NC}"
if [[ "$WITH_NPM" -eq 1 ]]; then
    echo -e "  ${DIM}3.${NC}  Open NPM admin     →  ${CYAN}http://YOUR_IP:81${NC}  (admin@example.com / changeme)"
fi
echo -e ""
echo -e "  ${BOLD}Dev commands:${NC}"
echo -e "  ${DIM}Backend:${NC}   cd ${BACKEND_DIR}  && bun run dev"
echo -e "  ${DIM}Frontend:${NC}  cd ${FRONTEND_DIR} && bun run dev"
echo -e "  ${DIM}Worker:${NC}    cd ${WORKER_DIR}   && cargo run"
echo -e ""
echo -e "  ${BOLD}Re-run options:${NC}"
echo -e "  ${DIM}With migrations:${NC}  sudo bash install.sh --with-migrations"
echo -e "  ${DIM}With Caddy:${NC}       sudo bash install.sh --with-caddy"
echo -e "  ${DIM}With NPM:${NC}         sudo bash install.sh --with-npm"
echo ""
echo -e "  ${DIM}Note: Log out and back in for Docker group to take effect.${NC}"
echo ""

