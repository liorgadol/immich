#!/bin/bash

# Stop on first failed command
set -e

# Run from the Immich directory (parent of scripts/, where docker-compose.yml lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$(dirname "$SCRIPT_DIR")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Pull first so Immich stays up during the download,
# and a failed pull leaves the old containers running
log "Pulling latest images..."
docker compose pull

log "Stopping containers..."
docker compose down

log "Waiting 10 seconds..."
sleep 10

log "Starting containers..."
docker compose up -d

log "Update complete"
