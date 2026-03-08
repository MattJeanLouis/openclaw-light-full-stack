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
ROLLBACK_FILE="$(mktemp)"

cd "$PROJECT_DIR"

echo ""
echo -e "${BOLD}OpenClaw Update${NC}"
echo ""

# ── Step 1: Pre-update backup ────────────────────────────────────────
info "Creating pre-update backup..."
bash "$SCRIPT_DIR/backup.sh" --quiet
success "Pre-update backup complete"

# ── Step 2: Record current image digests ─────────────────────────────
info "Recording current image digests for rollback..."

for service in postgres litellm openclaw; do
    digest=$(docker compose images "$service" --format '{{.Repository}}:{{.Tag}}@{{.Digest}}' 2>/dev/null | head -1 || echo "unknown")
    echo "${service}=${digest}" >> "$ROLLBACK_FILE"
done

success "Rollback info saved to $ROLLBACK_FILE"

# ── Step 3: Pull new images ──────────────────────────────────────────
info "Pulling latest images..."
docker compose pull

# ── Step 4: Progressive restart ──────────────────────────────────────
info "Restarting services progressively..."

info "Restarting postgres..."
docker compose up -d postgres
sleep 5

info "Restarting litellm..."
docker compose up -d litellm
sleep 5

info "Restarting openclaw..."
docker compose up -d openclaw
sleep 10

# Restart any active profile services
ACTIVE_SERVICES=$(docker compose ps --format '{{.Service}}' 2>/dev/null || true)
for svc in caddy cloudflared diun backup; do
    if echo "$ACTIVE_SERVICES" | grep -q "^${svc}$"; then
        info "Restarting profile service: $svc..."
        docker compose up -d "$svc"
    fi
done

# ── Step 5: Wait for healthchecks ─────────────────────────────────────
info "Waiting for services to become healthy..."
TIMEOUT=60
INTERVAL=5
ELAPSED=0
ALL_HEALTHY=false

while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))

    UNHEALTHY=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -cE '(unhealthy|starting)' || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        ALL_HEALTHY=true
        break
    fi

    info "Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

echo ""

# ── Step 6: Result ────────────────────────────────────────────────────
if $ALL_HEALTHY; then
    success "Update complete — all services are healthy!"
    rm -f "$ROLLBACK_FILE"
    echo ""
    docker compose ps
else
    error "Some services are unhealthy after update."
    echo ""
    docker compose ps
    echo ""
    warn "Current service status:"
    docker compose ps --format '{{.Name}}\t{{.Status}}'
    echo ""

    read -rp "Roll back to previous images? [y/N] " do_rollback
    if [[ "$do_rollback" =~ ^[Yy]$ ]]; then
        info "Rolling back to previous images..."

        while IFS='=' read -r service digest; do
            if [ "$digest" != "unknown" ] && [ -n "$digest" ]; then
                info "Pulling previous image for $service: $digest"
                docker pull "$digest" 2>/dev/null || warn "Could not pull previous image for $service"
            fi
        done < "$ROLLBACK_FILE"

        docker compose up -d
        success "Rollback complete. Check status with: make status"
    else
        warn "Skipping rollback. Fix issues manually and run: make restart"
    fi

    rm -f "$ROLLBACK_FILE"
fi
