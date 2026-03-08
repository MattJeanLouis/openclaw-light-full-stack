#!/usr/bin/env sh
# Diun notification script
# Called when a Docker image update is detected.
# Writes to /data/updates.json so OpenClaw or scripts can read it.

UPDATES_FILE="/data/updates.json"

# Append update info as JSON line
printf '{"image":"%s","tag":"%s","digest":"%s","date":"%s"}\n' \
    "${DIUN_ENTRY_IMAGE:-unknown}" \
    "${DIUN_ENTRY_TAG:-latest}" \
    "${DIUN_ENTRY_DIGEST:-}" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$UPDATES_FILE"
