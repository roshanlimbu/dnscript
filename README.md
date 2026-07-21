# DeployNest — Server Bootstrap Installer

> One-command setup for a fresh Ubuntu VM. Installs everything needed to run DeployNest and deploy Laravel applications.

## ⚡ Quick Install

The script can be run interactively to prompt you for domain setup, or you can pass the flags directly.

### Interactive Mode (Recommended)
If you run the script normally, it will prompt you for your frontend and API domains and configure them automatically:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/roshanlimbu/dnscript/master/install.sh)
```
*(Note: We use `bash <(...)` instead of piping so the interactive prompts work properly!)*

### Non-Interactive (One-liner)
To pass the domains directly and skip the prompts:

```bash
curl -fsSL https://raw.githubusercontent.com/roshanlimbu/dnscript/master/install.sh | sudo bash -s -- \
  --domain deploynest.yourdomain.com \
  --api-domain api.deploynest.yourdomain.com \
  --ssl-email your@email.com
```

---

## What Gets Installed

| Tool | Purpose |
|------|---------|
| **Docker + Compose** | Container runtime for all services |
| **Bun** | JS runtime for backend & frontend |
| **Rust + Cargo** | Builds the DeployNest worker |
| **PHP 8.2 + extensions** | Laravel app deployment support |
| **Composer** | PHP dependency manager |
| **Nginx Proxy Manager** | GUI reverse proxy + SSL (optional) |

### Repos Cloned Automatically

| Repo | Destination |
|------|-------------|
| `roshanlimbu/deploynest` | `/opt/deploynest/deploynest` |
| `roshanlimbu/DN_front` | `/opt/deploynest/DN_front` |
| `roshanlimbu/Deploynestworker` | `/opt/deploynest/Deploynestworker` |

---

## Requirements

- **OS**: Ubuntu 22.04 or 24.04 (Debian also supported)
- **RAM**: 2 GB minimum, 4 GB recommended
- **CPU**: 1 vCPU minimum, 2 recommended
- **Storage**: 20 GB+
- **Access**: Root or sudo privileges

---

## Options

```
Usage: sudo bash install.sh [options]

Options:
  --domain DOMAIN       Frontend domain (e.g. deploynest.com)
  --api-domain DOMAIN   Backend API domain (e.g. api.deploynest.com)
  --ssl-email EMAIL     Email for Let's Encrypt SSL notifications
  --with-npm            Deploy Nginx Proxy Manager via Docker (port 81)
  --with-caddy          Start the worker Caddy service after install
  --with-migrations     Run Drizzle DB migrations after install
  --install-dir PATH    Where to clone repos (default: /opt/deploynest)
  --backend-repo URL    Override backend repo URL
  --frontend-repo URL   Override frontend repo URL
  --worker-repo URL     Override worker repo URL
  -h, --help            Show help
```

### Examples

```bash
# Minimal install (no Caddy, no migrations, no NPM)
sudo bash install.sh

# Install + start Nginx Proxy Manager
sudo bash install.sh --with-npm

# Install everything at once
sudo bash install.sh --with-npm --with-caddy --with-migrations

# Custom install directory
sudo bash install.sh --install-dir /home/ubuntu/apps
```

You can also pass options as environment variables:

```bash
WITH_NPM=1 WITH_CADDY=1 sudo bash install.sh
```

---

## After Installation

### 1. Edit your `.env` files

```bash
nano /opt/deploynest/deploynest/.env
nano /opt/deploynest/Deploynestworker/.env
```

### 2. Open Nginx Proxy Manager (if `--with-npm` was used)

```
http://YOUR_SERVER_IP:81

Default credentials:
  Email:    admin@example.com
  Password: changeme
```

> ⚠️ Change the default credentials immediately after first login.

### 3. Add your domain in NPM

1. **Proxy Hosts → Add Proxy Host**
2. Domain: `yourdomain.com`
3. Forward to your app container
4. SSL tab → Request Let's Encrypt certificate ✅

---

## Dev Commands

```bash
# Backend
cd /opt/deploynest/deploynest && bun run dev

# Frontend
cd /opt/deploynest/deploynestfrontend && bun run dev

# Worker
cd /opt/deploynest/Deploynestworker && cargo run
```

---

## Update / Redeploy

Re-running the script on an existing install is safe — it will `git pull` instead of re-cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/roshanlimbu/dnscript/master/install.sh \
  | sudo bash -s -- --with-migrations
```

Or manually:

```bash
cd /opt/deploynest/deploynest && git pull && bun install && bun run db:migrate
cd /opt/deploynest/deploynestfrontend && git pull && bun install
cd /opt/deploynest/Deploynestworker && git pull && cargo build --release
```

---

## Google Cloud Firewall

If running on Google Cloud, open the required ports:

```bash
gcloud compute firewall-rules create allow-http   --allow tcp:80
gcloud compute firewall-rules create allow-https  --allow tcp:443
gcloud compute firewall-rules create allow-npm    --allow tcp:81 --source-ranges=YOUR_HOME_IP/32
```

> Port 81 (NPM admin) should be restricted to your IP only.

---

## Troubleshooting

**Docker group not active after install?**
```bash
newgrp docker
# or log out and back in
```

**Bun not found after install?**
```bash
export PATH="$HOME/.bun/bin:$PATH"
# Add to ~/.bashrc for persistence
```

**Cargo not found after install?**
```bash
source "$HOME/.cargo/env"
# Add to ~/.bashrc for persistence
```

**Check service status:**
```bash
sudo systemctl status docker
sudo systemctl status php8.2-fpm
docker ps   # running containers
```

---

## License

MIT

