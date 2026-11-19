#!/usr/bin/env bash
# Google Compute Engine startup script for eScriptorium.
# Runs as root on every boot; each step is idempotent.
# Secrets are generated on the server itself and never leave it
# (they live in /opt/escriptorium/variables.env, readable by root only).
set -euo pipefail

APP_DIR=/opt/escriptorium
UPSTREAM=https://gitlab.com/scripta/escriptorium.git
UPSTREAM_REF=3447622065812dcd995da5663404420b4214f44f   # same snapshot as this repo
MD=http://metadata.google.internal/computeMetadata/v1

log() { echo "[escriptorium-setup] $*"; }

# 1. Docker
if ! command -v docker >/dev/null 2>&1; then
  log "installing docker"
  curl -fsSL https://get.docker.com | sh
fi

# 2. Code (pinned to the snapshot this repo was imported from)
if [ ! -d "$APP_DIR/.git" ]; then
  log "cloning eScriptorium"
  git clone --filter=blob:none "$UPSTREAM" "$APP_DIR"
  git -C "$APP_DIR" checkout -q "$UPSTREAM_REF"
fi
cd "$APP_DIR"

# 3. Config with generated secrets (only on first boot)
IP=$(curl -fsS -H 'Metadata-Flavor: Google' "$MD/instance/network-interfaces/0/access-configs/0/external-ip")
if [ ! -f variables.env ]; then
  log "writing variables.env"
  rnd() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c "$1"; }
  sed \
    -e "s|^DOMAIN=.*|DOMAIN=$IP|" \
    -e "s|^SECRET_KEY=.*|SECRET_KEY=$(rnd 50)|" \
    -e "s|^CSRF_TRUSTED_ORIGINS=.*|CSRF_TRUSTED_ORIGINS=http://$IP|" \
    -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(rnd 32)|" \
    -e "s|^DJANGO_SU_EMAIL=.*|DJANGO_SU_EMAIL=admin@example.com|" \
    -e "s|^DJANGO_SU_PASSWORD=.*|DJANGO_SU_PASSWORD=$(rnd 20)|" \
    -e "s|^FLOWER_BASIC_AUTH=.*|FLOWER_BASIC_AUTH=flower:$(rnd 20)|" \
    variables.env_example > variables.env
  chmod 600 variables.env
fi

# 4. Serve on port 80 as well as the default 8080
cat > docker-compose.override.yml <<'EOF'
services:
  nginx:
    ports:
      - 80:80
EOF

# 5. Start (prebuilt images from eScriptorium's registry)
log "starting containers"
docker compose pull -q
docker compose up -d
log "done"
