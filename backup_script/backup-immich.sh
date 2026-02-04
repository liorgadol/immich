#!/bin/bash

# Absolute paths are required for cron
ENV_FILE="/home/gadol/projects/immich/.env"
BACKUP_DIR="/mnt/data/immich/backup"
BACKUP_FILE="$BACKUP_DIR/immich_db_backup.sql.gz"
LOG_FILE="$BACKUP_DIR/backup.log"

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

# Backup library folder with rsync
log "Starting library rsync backup..."
if rsync -avh --delete --inplace /mnt/data/immich/library/ /mnt/data/immich/backup/library/; then
    log "Library backup completed: /mnt/data/immich/backup/library/"
else
    log "ERROR: Library backup failed"
    exit 1
fi