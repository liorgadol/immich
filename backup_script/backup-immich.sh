#!/bin/bash

# Absolute paths are required for cron
ENV_FILE="/Users/liorg/homedev/immich/.env"
BACKUP_DIR="/mnt/data/immich"
BACKUP_FILE="$BACKUP_DIR/immich_backup.sql.gz"
LOG_FILE="$BACKUP_DIR/backup.log"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Clear the log file at the start
> "$LOG_FILE"

# Log function (appends during this run)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Load environment variables
source "$ENV_FILE"

log "Starting backup..."

if docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
    pg_dump -U "$DB_USERNAME" -d "$DB_NAME" --clean --if-exists | gzip > "$BACKUP_FILE"; then
    log "Backup completed: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
else
    log "ERROR: Backup failed"
    exit 1
fi