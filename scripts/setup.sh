#!/usr/bin/env bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}ℹ  $*${NC}"; }
success() { echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
error()   { echo -e "${RED}✖  $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE="$PROJECT_DIR/.env.example"

cd "$PROJECT_DIR"

# ── Banner ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║       OpenClaw Self-Host Setup Wizard    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Step 1: Prerequisites ────────────────────────────────────────────
info "Checking prerequisites..."

if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
    exit 1
fi
success "Docker found: $(docker --version)"

if ! docker compose version &>/dev/null; then
    error "Docker Compose (v2) is not available. Install it from https://docs.docker.com/compose/install/"
    exit 1
fi
success "Docker Compose found: $(docker compose version --short)"

if ! docker info &>/dev/null 2>&1; then
    error "Docker daemon is not running. Start Docker and try again."
    exit 1
fi
success "Docker daemon is running"

# ── Step 2: Architecture ─────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64)
        info "Detected ARM64 architecture"
        ;;
    x86_64|amd64)
        info "Detected x86_64 architecture"
        ;;
    *)
        warn "Unknown architecture: $ARCH — images may not be available"
        ;;
esac

# ── Step 3: Environment file ─────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
    warn ".env already exists"
    read -rp "Overwrite with fresh config? [y/N] " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        info "Keeping existing .env"
    else
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        success "Copied .env.example to .env"
    fi
else
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    success "Created .env from .env.example"
fi

# ── Step 4: Generate secrets ─────────────────────────────────────────
info "Generating secure secrets..."

generate_secret() {
    openssl rand -hex 32
}

# Replace "change-me" placeholders with generated secrets
GATEWAY_TOKEN="$(generate_secret)"
POSTGRES_PASSWORD="$(generate_secret)"
LITELLM_KEY="sk-$(generate_secret)"

sed -i.bak "s|OPENCLAW_GATEWAY_TOKEN=change-me|OPENCLAW_GATEWAY_TOKEN=${GATEWAY_TOKEN}|" "$ENV_FILE"
sed -i.bak "s|POSTGRES_PASSWORD=change-me|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" "$ENV_FILE"
sed -i.bak "s|LITELLM_MASTER_KEY=sk-change-me|LITELLM_MASTER_KEY=${LITELLM_KEY}|" "$ENV_FILE"

# Clean up .bak files from sed
rm -f "$ENV_FILE.bak"

success "Generated gateway token, database password, and LiteLLM master key"

# ── Step 5: AI Provider keys ─────────────────────────────────────────
echo ""
info "AI Provider Configuration"
echo "  OpenClaw uses LiteLLM as a proxy — you need at least one provider key."
echo ""

read -rp "Enter your OpenAI API key (or press Enter to skip): " OPENAI_KEY
if [ -n "$OPENAI_KEY" ]; then
    sed -i.bak "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=${OPENAI_KEY}|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
    success "OpenAI API key saved"
else
    warn "Skipped — you can add provider keys to .env later"
fi

# ── Step 6: Channels ─────────────────────────────────────────────────
echo ""
info "Messaging Channels"
echo "  OpenClaw supports WhatsApp, Discord, Telegram, Slack, and more."
echo "  Channels are configured after setup via the CLI:"
echo ""
echo -e "    ${BOLD}make cli${NC}  — then run channel setup commands"
echo -e "    ${BOLD}make channels-status${NC}  — check connection status"
echo ""
read -rp "Press Enter to continue..." _

# ── Step 7: Profiles ─────────────────────────────────────────────────
echo ""
info "Optional Profiles"
PROFILES=""

read -rp "Enable Cloudflare Tunnel for remote access? [y/N] " enable_tunnel
if [[ "$enable_tunnel" =~ ^[Yy]$ ]]; then
    read -rp "Enter your Cloudflare Tunnel token: " tunnel_token
    if [ -n "$tunnel_token" ]; then
        sed -i.bak "s|^# CLOUDFLARE_TUNNEL_TOKEN=.*|CLOUDFLARE_TUNNEL_TOKEN=${tunnel_token}|" "$ENV_FILE"
        rm -f "$ENV_FILE.bak"
        PROFILES="tunnel"
        success "Cloudflare Tunnel configured"
    else
        warn "No token provided — skipping tunnel"
    fi
fi

read -rp "Enable Diun image update notifications? [y/N] " enable_diun
if [[ "$enable_diun" =~ ^[Yy]$ ]]; then
    if [ -n "$PROFILES" ]; then
        PROFILES="${PROFILES},notify"
    else
        PROFILES="notify"
    fi
    success "Diun notifications enabled"
fi

if [ -n "$PROFILES" ]; then
    sed -i.bak "s|^COMPOSE_PROFILES=.*|COMPOSE_PROFILES=${PROFILES}|" "$ENV_FILE"
    rm -f "$ENV_FILE.bak"
fi

# ── Step 8: Pull images and start ────────────────────────────────────
echo ""
info "Pulling container images (this may take a few minutes)..."
docker compose pull

info "Starting services..."
docker compose up -d

# ── Step 9: Wait for healthchecks ─────────────────────────────────────
info "Waiting for services to become healthy..."
TIMEOUT=60
INTERVAL=5
ELAPSED=0
ALL_HEALTHY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))

    # Check if all core services are healthy
    UNHEALTHY=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -cE '(unhealthy|starting)' || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        ALL_HEALTHY=true
        break
    fi

    info "Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

echo ""
if $ALL_HEALTHY; then
    success "All services are healthy!"
else
    warn "Some services may still be starting. Check with: make status"
fi

# ── Step 10: Summary ─────────────────────────────────────────────────
# Read back values from .env
source "$ENV_FILE"

HOST_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "localhost")
PORT="${OPENCLAW_PORT:-18789}"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║           Setup Complete!                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Gateway URL:${NC}   http://${HOST_IP}:${PORT}"
echo -e "  ${BOLD}Gateway Token:${NC} ${OPENCLAW_GATEWAY_TOKEN}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo "    make status          — Check service health"
echo "    make logs            — Follow all logs"
echo "    make logs-openclaw   — Follow OpenClaw logs"
echo "    make cli             — Open OpenClaw CLI"
echo "    make channels-status — Check channel connections"
echo "    make backup          — Backup database + configs"
echo "    make update          — Update to latest images"
echo ""
echo -e "  ${BOLD}Next steps:${NC}"
echo "    1. Connect a messaging channel via: make cli"
echo "    2. Add more AI provider keys to .env"
echo "    3. Set up backups: make setup-backup"
echo ""
