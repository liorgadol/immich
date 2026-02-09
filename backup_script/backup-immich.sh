#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMMICH_DIR="${IMMICH_DIR:-$(dirname "$SCRIPT_DIR")}"

# Load environment variables from .env file
ENV_FILE="${ENV_FILE:-$IMMICH_DIR/.env}"
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "ERROR: .env file not found at $ENV_FILE"
    exit 1
fi

# Backup configuration (can be overridden in .env)
BACKUP_DIR="${BACKUP_DIR:-/mnt/data/immich/backup}"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/immich_db_backup_${TIMESTAMP}.sql.gz"
LOG_FILE="$BACKUP_DIR/backup.log"
MAX_BACKUPS="${MAX_BACKUPS:-4}"
DB_CONTAINER="${DB_CONTAINER:-immich_postgres}"
DB_NAME="${DB_DATABASE_NAME:-immich}"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Clear the log file at the start
> "$LOG_FILE"

# Log function (appends during this run)
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Record start time
START_TIME=$(date +%s)
log "Starting backup..."

# Trap to ensure immich_server restarts even if script fails
trap 'log "Restarting immich_server..."; docker start immich_server' EXIT

# Stop immich_server for consistent backup
log "Stopping immich_server..."
if docker stop immich_server; then
    log "immich_server stopped successfully"
else
    log "WARNING: Failed to stop immich_server, continuing anyway"
fi

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

# Backup configuration files (keeps only latest copy)
log "Backing up configuration files..."
cp "$ENV_FILE" "$BACKUP_DIR/env_backup" && log "Backed up .env file"
cp "$IMMICH_DIR/docker-compose.yml" "$BACKUP_DIR/docker-compose_backup.yml" && log "Backed up docker-compose.yml"

# Backup library folder with rsync
log "Starting library rsync backup..."
LIBRARY_SOURCE="${UPLOAD_LOCATION%/}/"  # Remove trailing slash and add it back for rsync
LIBRARY_BACKUP="${BACKUP_DIR}/library/"
if rsync -avh --delete --inplace "$LIBRARY_SOURCE" "$LIBRARY_BACKUP"; then
    log "Library backup completed: $LIBRARY_BACKUP"
else
    log "ERROR: Library backup failed"
    exit 1
fi

# Restart immich_server
log "Starting immich_server..."
if docker start immich_server; then
    log "immich_server restarted successfully"
else
    log "ERROR: Failed to restart immich_server!"
    exit 1
fi

# Disable trap since we've manually restarted
trap - EXIT

# Calculate and log total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log "Total backup time: ${MINUTES}m ${SECONDS}s"