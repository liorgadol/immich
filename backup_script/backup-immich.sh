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


CONTAINERS_TO_MANAGE=(immich_server immich_machine_learning)
# Trap to ensure both containers restart even if script fails
trap 'log "Restarting Immich containers..."; for c in "${CONTAINERS_TO_MANAGE[@]}"; do docker start "$c"; done' EXIT

# Stop containers for consistent backup
for c in "${CONTAINERS_TO_MANAGE[@]}"; do
    log "Stopping $c..."
    if docker stop "$c"; then
        log "$c stopped successfully"
    else
        log "WARNING: Failed to stop $c, continuing anyway"
    fi
done

log "Starting database backup..."
if docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
    pg_dump -U "$DB_USERNAME" -d "$DB_NAME" --clean --if-exists | gzip > "$BACKUP_FILE"; then
    log "Backup completed: $BACKUP_FILE ($(du -h "$BACKUP_FILE" | cut -f1))"
    
    # Keep only the last 4 backups
    log "Cleaning up old DB backups (keeping last $MAX_BACKUPS)..."
    ls -t "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    REMAINING=$(ls -1 "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | wc -l)
    log "Current DB backup count: $REMAINING"
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


# Restart containers
for c in "${CONTAINERS_TO_MANAGE[@]}"; do
    log "Starting $c..."
    if docker start "$c"; then
        log "$c restarted successfully"
    else
        log "ERROR: Failed to restart $c!"
        exit 1
    fi
done

# Disable trap since we've manually restarted
trap - EXIT

# Calculate and log total time
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
log "Total backup time: ${MINUTES}m ${SECONDS}s"