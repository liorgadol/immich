#!/bin/bash

# Absolute paths are required for cron
ENV_FILE="/home/gadol/projects/immich/.env"
BACKUP_DIR="/mnt/data/immich/backup"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/immich_db_backup_${TIMESTAMP}.sql.gz"
LOG_FILE="$BACKUP_DIR/backup.log"
MAX_BACKUPS=4

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
    
    # Keep only the last 4 backups
    log "Cleaning up old backups (keeping last $MAX_BACKUPS)..."
    ls -t "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    REMAINING=$(ls -1 "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | wc -l)
    log "Current backup count: $REMAINING"
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