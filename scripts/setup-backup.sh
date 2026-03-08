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
RCLONE_CONF="$PROJECT_DIR/config/rclone.conf"

cd "$PROJECT_DIR"

echo ""
echo -e "${BOLD}Google Drive Backup Setup${NC}"
echo ""
info "This will configure rclone for Google Drive backups."
info "You'll be guided through an interactive configuration process."
echo ""

# ── Run rclone config interactively ───────────────────────────────────
info "Starting rclone configuration..."
docker run --rm -it \
    -v "$PROJECT_DIR/config:/config/rclone" \
    rclone/rclone:latest \
    config --config /config/rclone/rclone.conf

echo ""

# ── Verify configuration ─────────────────────────────────────────────
if [ -f "$RCLONE_CONF" ]; then
    info "Testing Google Drive connection..."
    if docker run --rm \
        -v "$PROJECT_DIR/config:/config/rclone:ro" \
        rclone/rclone:latest \
        lsd "gdrive:" --config /config/rclone/rclone.conf 2>/dev/null; then
        echo ""
        success "Google Drive connection successful!"
        echo ""
        info "Enable the backup profile in your .env:"
        echo "  Add 'backup' to COMPOSE_PROFILES (comma-separated)"
        echo ""
        info "Backups will sync to Google Drive automatically when you run:"
        echo "  make backup"
    else
        echo ""
        warn "Could not list Google Drive contents."
        warn "The rclone config was saved, but the connection test failed."
        warn "Check your remote name matches 'gdrive' or edit scripts/backup.sh"
    fi
else
    error "No rclone.conf was created. Run this command again to retry."
fi
