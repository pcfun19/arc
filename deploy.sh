#!/usr/bin/env bash
set -euo pipefail

# deploy.sh - deploy ARC on Ubuntu 24.04
# Usage: sudo ./deploy.sh <git_repo_url> [branch] [deploy_dir]
# Example: sudo ./deploy.sh https://github.com/pcfun19/walletsv_api.git main /opt/arc

GIT_URL=${1:-}
BRANCH=${2:-main}
DEST=${3:-/opt/arc}

if [ -z "$GIT_URL" ]; then
  echo "Usage: sudo $0 <git_repo_url> [branch] [deploy_dir]"
  exit 1
fi

echo "Deploying ARC from $GIT_URL (branch $BRANCH) to $DEST"

apt update
apt install -y git curl wget unzip ca-certificates build-essential golang-go nginx ufw

# Install nats-server to /usr/local/bin if not present
if ! command -v nats-server >/dev/null 2>&1; then
  echo "Installing nats-server..."
  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"
  TARBALL=$(curl -sL https://api.github.com/repos/nats-io/nats-server/releases/latest | grep browser_download_url | grep linux-amd64 | cut -d '"' -f 4)
  if [ -z "$TARBALL" ]; then
    echo "Failed to locate nats-server download URL; please install manually." >&2
    exit 1
  fi
  wget -q "$TARBALL" -O nats.tgz
  tar xzf nats.tgz
  BIN_DIR=$(find . -maxdepth 2 -type f -name nats-server -print -quit)
  sudo cp "$BIN_DIR" /usr/local/bin/nats-server
  sudo chmod +x /usr/local/bin/nats-server
  cd - >/dev/null
  rm -rf "$TMPDIR"
fi

# Create deploy user if not exists
DEPLOY_USER=${SUDO_USER:-$(whoami)}
echo "Using deploy user: $DEPLOY_USER"

# Clone or update repo
if [ -d "$DEST/.git" ]; then
  echo "Updating existing repo in $DEST"
  git -C "$DEST" fetch --all
  git -C "$DEST" checkout "$BRANCH"
  git -C "$DEST" pull --ff-only origin "$BRANCH"
else
  echo "Cloning repo to $DEST"
  mkdir -p "$DEST"
  git clone --branch "$BRANCH" "$GIT_URL" "$DEST"
  chown -R "$DEPLOY_USER":"$DEPLOY_USER" "$DEST"
fi

# Ensure .env exists in repo root. If there is .env.example, copy it as template.
if [ ! -f "$DEST/.env" ]; then
  if [ -f "$DEST/.env.example" ]; then
    echo "Creating .env from .env.example (please edit values)"
    cp "$DEST/.env.example" "$DEST/.env"
    chown "$DEPLOY_USER":"$DEPLOY_USER" "$DEST/.env"
  else
    echo "No .env found in repo. Please create $DEST/.env with required env vars and rerun." >&2
    exit 1
  fi
fi

# Build ARC binary
echo "Building ARC..."
cd "$DEST"
sudo -u "$DEPLOY_USER" -H bash -c 'go build -o arc ./cmd/arc'

# Create systemd service for nats
echo "Creating systemd unit for nats..."
sudo useradd --system --no-create-home --shell /usr/sbin/nologin nats || true
sudo tee /etc/systemd/system/nats.service > /dev/null <<'NATS'
[Unit]
Description=NATS Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nats-server -p 4222 -js
Restart=on-failure
User=nats

[Install]
WantedBy=multi-user.target
NATS

sudo systemctl daemon-reload
sudo systemctl enable --now nats.service

# Create systemd unit for arc
echo "Creating systemd unit for arc..."
sudo tee /etc/systemd/system/arc.service > /dev/null <<EOF
[Unit]
Description=ARC Service
After=network.target nats.service

[Service]
Type=simple
WorkingDirectory=$DEST
EnvironmentFile=$DEST/.env
ExecStart=$DEST/arc -config=$DEST/config -api=true -metamorph=true -blocktx=true -callbacker=true
Restart=on-failure
User=$DEPLOY_USER
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now arc.service

# Configure nginx to proxy IP:80 to ARC API on localhost:9090
echo "Configuring nginx to proxy 0.0.0.0:80 -> 127.0.0.1:9090"
NGINX_CONF=/etc/nginx/sites-available/arc
sudo tee "$NGINX_CONF" > /dev/null <<'NGCONF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # send all traffic to ARC API listening on localhost:9090
    location / {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGCONF

sudo ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/arc
sudo rm -f /etc/nginx/sites-enabled/default || true
sudo nginx -t
sudo systemctl restart nginx

# Open firewall
if command -v ufw >/dev/null 2>&1; then
  sudo ufw allow OpenSSH
  sudo ufw allow 80/tcp
  sudo ufw --force enable
fi

echo "Deployment complete. Check services with:"
echo "  sudo systemctl status nats arc nginx"
echo "Logs: sudo journalctl -u arc -f" 
echo "Visit http://<server-ip>/ to reach ARC API (proxied to localhost:9090)"

exit 0
