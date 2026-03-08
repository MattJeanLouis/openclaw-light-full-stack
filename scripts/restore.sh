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
BACKUPS_DIR="$PROJECT_DIR/backups"

cd "$PROJECT_DIR"

echo ""
echo -e "${BOLD}OpenClaw Restore${NC}"
echo ""

# ── List available backups ────────────────────────────────────────────
if [ ! -d "$BACKUPS_DIR" ] || [ -z "$(ls -A "$BACKUPS_DIR" 2>/dev/null)" ]; then
    error "No backups found in $BACKUPS_DIR"
    exit 1
fi

info "Available backups:"
echo ""

INDEX=0
BACKUP_DIRS=()
while IFS= read -r dir; do
    INDEX=$((INDEX + 1))
    DIRNAME="$(basename "$dir")"
    SIZE="$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "?")"
    HAS_DB=""
    [ -f "$dir/database.sql.gz" ] && HAS_DB=" [DB]"
    echo -e "  ${BOLD}${INDEX})${NC} ${DIRNAME}  (${SIZE})${HAS_DB}"
    BACKUP_DIRS+=("$dir")
done < <(find "$BACKUPS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

if [ ${#BACKUP_DIRS[@]} -eq 0 ]; then
    error "No backup directories found"
    exit 1
fi

echo ""
read -rp "Select backup to restore [1-${#BACKUP_DIRS[@]}]: " SELECTION

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#BACKUP_DIRS[@]} ]; then
    error "Invalid selection"
    exit 1
fi

SELECTED_DIR="${BACKUP_DIRS[$((SELECTION - 1))]}"
SELECTED_NAME="$(basename "$SELECTED_DIR")"

echo ""
warn "This will restore from backup: $SELECTED_NAME"
warn "Current data will be OVERWRITTEN."
read -rp "Are you sure you want to continue? [y/N] " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    info "Restore cancelled"
    exit 0
fi

# ── Stop services ─────────────────────────────────────────────────────
info "Stopping services..."
docker compose down

# ── Restore config files ─────────────────────────────────────────────
info "Restoring configuration files..."
[ -f "$SELECTED_DIR/.env" ] && cp -f "$SELECTED_DIR/.env" "$PROJECT_DIR/.env" && success "Restored .env"
[ -f "$SELECTED_DIR/openclaw.json" ] && cp -f "$SELECTED_DIR/openclaw.json" "$PROJECT_DIR/config/openclaw.json" && success "Restored openclaw.json"
[ -f "$SELECTED_DIR/litellm.yaml" ] && cp -f "$SELECTED_DIR/litellm.yaml" "$PROJECT_DIR/config/litellm.yaml" && success "Restored litellm.yaml"

# ── Start postgres only ──────────────────────────────────────────────
if [ -f "$SELECTED_DIR/database.sql.gz" ]; then
    info "Starting PostgreSQL for database restore..."
    docker compose up -d postgres

    # Wait for postgres to be ready
    info "Waiting for PostgreSQL to be ready..."
    TIMEOUT=30
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER:-openclaw}" &>/dev/null; then
            break
        fi
        sleep 2
        ELAPSED=$((ELAPSED + 2))
    done

    info "Restoring database dump..."
    gunzip -c "$SELECTED_DIR/database.sql.gz" | docker compose exec -T postgres psql -U "${POSTGRES_USER:-openclaw}" -d "${POSTGRES_DB:-litellm}" &>/dev/null
    success "Database restored"
else
    warn "No database dump found in backup — skipping database restore"
fi

# ── Start all services ───────────────────────────────────────────────
info "Starting all services..."
docker compose up -d

# ── Wait for healthchecks ─────────────────────────────────────────────
info "Waiting for services to become healthy..."
TIMEOUT=60
INTERVAL=5
ELAPSED=0

while [ $ELAPSED -lt $TIMEOUT ]; do
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))

    UNHEALTHY=$(docker compose ps --format '{{.Name}} {{.Status}}' 2>/dev/null | grep -cE '(unhealthy|starting)' || true)
    if [ "$UNHEALTHY" -eq 0 ]; then
        break
    fi

    info "Waiting... (${ELAPSED}s / ${TIMEOUT}s)"
done

echo ""
success "Restore complete from backup: $SELECTED_NAME"
echo ""
docker compose ps
