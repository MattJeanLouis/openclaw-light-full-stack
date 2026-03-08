#!/usr/bin/env bash
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

QUIET=false
for arg in "$@"; do
    case "$arg" in
        --quiet|-q) QUIET=true ;;
    esac
done

info()    { $QUIET || echo -e "${BLUE}ℹ  $*${NC}"; }
success() { $QUIET || echo -e "${GREEN}✔  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
error()   { echo -e "${RED}✖  $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Source .env for POSTGRES_USER and other vars
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$PROJECT_DIR/.env"
    set +a
fi

TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
BACKUP_DIR="$PROJECT_DIR/backups/$TIMESTAMP"

mkdir -p "$BACKUP_DIR"

info "Starting backup to $BACKUP_DIR"

# ── Database dump ─────────────────────────────────────────────────────
info "Dumping PostgreSQL database..."
docker compose exec -T postgres pg_dumpall -U "${POSTGRES_USER:-openclaw}" 2>/dev/null | gzip > "$BACKUP_DIR/database.sql.gz"
success "Database dump saved"

# ── Config files ──────────────────────────────────────────────────────
info "Backing up configuration files..."
cp -f "$PROJECT_DIR/.env" "$BACKUP_DIR/.env" 2>/dev/null || warn ".env not found"
cp -f "$PROJECT_DIR/config/openclaw.json" "$BACKUP_DIR/openclaw.json" 2>/dev/null || warn "openclaw.json not found"
cp -f "$PROJECT_DIR/config/litellm.yaml" "$BACKUP_DIR/litellm.yaml" 2>/dev/null || warn "litellm.yaml not found"
success "Configuration files backed up"

# ── OpenClaw data (agents, identity) ─────────────────────────────────
info "Backing up OpenClaw data..."
mkdir -p "$BACKUP_DIR/openclaw-data"
docker compose cp openclaw:/home/node/.openclaw/agents "$BACKUP_DIR/openclaw-data/agents" 2>/dev/null || warn "No agents data to backup"
docker compose cp openclaw:/home/node/.openclaw/identity "$BACKUP_DIR/openclaw-data/identity" 2>/dev/null || warn "No identity data to backup"
success "OpenClaw data backed up"

# ── Clean old backups (keep last 7) ──────────────────────────────────
BACKUP_COUNT=$(find "$PROJECT_DIR/backups" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [ "$BACKUP_COUNT" -gt 7 ]; then
    REMOVE_COUNT=$((BACKUP_COUNT - 7))
    info "Cleaning old backups (removing $REMOVE_COUNT oldest)..."
    find "$PROJECT_DIR/backups" -mindepth 1 -maxdepth 1 -type d | sort | head -n "$REMOVE_COUNT" | while read -r dir; do
        rm -rf "$dir"
    done
    success "Old backups cleaned"
fi

# ── Google Drive sync via rclone ──────────────────────────────────────
if [ -f "$PROJECT_DIR/config/rclone.conf" ]; then
    info "Syncing backup to Google Drive via rclone..."
    docker compose run --rm -v "$PROJECT_DIR/backups:/backups:ro" backup \
        sync /backups "gdrive:openclaw-backups" \
        --config /config/rclone/rclone.conf 2>/dev/null \
        && success "Backup synced to Google Drive" \
        || warn "Google Drive sync failed — backup is still saved locally"
fi

# ── Summary ───────────────────────────────────────────────────────────
BACKUP_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "unknown")
success "Backup complete: $BACKUP_DIR ($BACKUP_SIZE)"
