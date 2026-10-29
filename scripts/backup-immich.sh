#!/bin/bash

# Fail a pipeline if any command in it fails (e.g. pg_dump | gzip)
set -o pipefail

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
SUMMARY_FILE="$SCRIPT_DIR/backup-summary.log"
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

# Send a Telegram message (no-op if TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set)
send_telegram() {
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        return 0
    fi
    if ! curl -fsS -m 15 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=$1" > /dev/null; then
        log "WARNING: Failed to send Telegram notification"
    fi
}

# Summary state, filled in as each step runs and written by on_exit
STEP="starting"
SUMMARY_DB="not run"
SUMMARY_CONFIG="not run"
SUMMARY_LIBRARY="not run"
SUMMARY_CONTAINERS=""
RSYNC_OUT=$(mktemp)

# Pull one value out of rsync --stats output ("?" if this rsync doesn't print it)
rsync_stat() {
    local value
    value=$(awk -F': ' -v key="$1" '$1 == key { print $2; exit }' "$RSYNC_OUT")
    value="${value%% (*}"  # drop breakdowns like "(reg: 10, dir: 2)"
    value="${value% bytes}"
    echo "${value:-?}"
}

# Overwrite the summary file with the result of this run
write_summary() {
    local status="$1" duration="$2" disk used_pct
    disk=$(df -h "$BACKUP_DIR" | awk 'NR==2 { print $4 " free (" $5 " used)" }')
    used_pct=$(df -P "$BACKUP_DIR" | awk 'NR==2 { sub("%", "", $5); print $5 }')
    [ "${used_pct:-0}" -ge 90 ] && disk="$disk  WARNING: backup volume almost full"
    {
        echo "==== Immich backup - $(date -d "@$START_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$START_TIME" '+%Y-%m-%d %H:%M:%S') ($(hostname)) ===="
        echo "Status:      $status"
        echo "Duration:    $duration"
        echo "Database:    $SUMMARY_DB"
        echo "DB backups kept:"
        for f in $(ls -t "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null); do
            echo "             $(basename "$f")  $(du -h "$f" | cut -f1)"
        done
        echo "Config:      $SUMMARY_CONFIG"
        echo "Library:     $SUMMARY_LIBRARY"
        echo "Disk:        $disk"
        echo "Containers:  $SUMMARY_CONTAINERS"
        echo "Full log:    $LOG_FILE"
    } > "$SUMMARY_FILE"
}

# Record start time
START_TIME=$(date +%s)
log "Starting backup..."


IMMICH_CONTAINERS=(immich_server immich_machine_learning)
NGINX_CONTAINER=immich_nginx_proxy
# Trap: restart containers (on success and failure), notify on failure, write the summary
on_exit() {
    local rc=$?
    # Immich containers first, then nginx-proxy
    for c in "${IMMICH_CONTAINERS[@]}" "$NGINX_CONTAINER"; do
        log "Starting $c..."
        if docker start "$c"; then
            log "$c restarted successfully"
            SUMMARY_CONTAINERS="$SUMMARY_CONTAINERS $c OK,"
        else
            log "ERROR: Failed to restart $c!"
            SUMMARY_CONTAINERS="$SUMMARY_CONTAINERS $c FAILED,"
            if [ "$rc" -eq 0 ]; then
                rc=1
                STEP="restarting containers"
            fi
        fi
    done
    SUMMARY_CONTAINERS="${SUMMARY_CONTAINERS# }"
    SUMMARY_CONTAINERS="${SUMMARY_CONTAINERS%,}"

    # Calculate and log total time
    local duration=$(( $(date +%s) - START_TIME ))
    duration="$((duration / 60))m $((duration % 60))s"
    log "Total backup time: $duration"

    if [ "$rc" -ne 0 ]; then
        send_telegram "Immich backup FAILED on $(hostname) (exit code $rc)

$(tail -n 15 "$LOG_FILE")"
        write_summary "FAILED at: $STEP (exit code $rc)" "$duration"
    else
        write_summary "SUCCESS" "$duration"
    fi
    rm -f "$RSYNC_OUT"
    exit "$rc"
}
trap on_exit EXIT

# Stop containers for consistent backup
STEP="stopping containers"
for c in "${IMMICH_CONTAINERS[@]}"; do
    log "Stopping $c..."
    if docker stop "$c"; then
        log "$c stopped successfully"
    else
        log "WARNING: Failed to stop $c, continuing anyway"
    fi
done
# Stop nginx-proxy last
log "Stopping $NGINX_CONTAINER..."
if docker stop "$NGINX_CONTAINER"; then
    log "$NGINX_CONTAINER stopped successfully"
else
    log "WARNING: Failed to stop $NGINX_CONTAINER, continuing anyway"
fi

STEP="database backup"
log "Starting database backup..."
if docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
    pg_dump -U "$DB_USERNAME" -d "$DB_NAME" --clean --if-exists | gzip > "$BACKUP_FILE"; then
    DB_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    log "Backup completed: $BACKUP_FILE ($DB_SIZE)"

    # Make sure the dump can actually be decompressed
    if gzip -t "$BACKUP_FILE"; then
        log "Integrity check passed (gzip -t)"
        SUMMARY_DB="$(basename "$BACKUP_FILE")  ($DB_SIZE)  integrity: OK"
    else
        log "ERROR: Integrity check failed for $BACKUP_FILE"
        SUMMARY_DB="$(basename "$BACKUP_FILE")  ($DB_SIZE)  integrity: FAILED"
        exit 1
    fi

    # Keep only the last 4 backups
    log "Cleaning up old DB backups (keeping last $MAX_BACKUPS)..."
    ls -t "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | tail -n +$((MAX_BACKUPS + 1)) | xargs -r rm -f
    REMAINING=$(ls -1 "$BACKUP_DIR"/immich_db_backup_*.sql.gz 2>/dev/null | wc -l)
    log "Current DB backup count: $REMAINING"
else
    log "ERROR: Backup failed"
    SUMMARY_DB="FAILED"
    exit 1
fi

# Backup configuration files (keeps only latest copy)
STEP="configuration files"
log "Backing up configuration files..."
if cp "$ENV_FILE" "$BACKUP_DIR/env_backup"; then
    log "Backed up .env file"
    SUMMARY_CONFIG=".env OK"
else
    SUMMARY_CONFIG=".env FAILED"
fi
if cp "$IMMICH_DIR/docker-compose.yml" "$BACKUP_DIR/docker-compose_backup.yml"; then
    log "Backed up docker-compose.yml"
    SUMMARY_CONFIG="$SUMMARY_CONFIG, docker-compose.yml OK"
else
    SUMMARY_CONFIG="$SUMMARY_CONFIG, docker-compose.yml FAILED"
fi

# Backup library folder with rsync
STEP="library rsync"
log "Starting library rsync backup..."
LIBRARY_SOURCE="${UPLOAD_LOCATION%/}/"  # Remove trailing slash and add it back for rsync
LIBRARY_BACKUP="${BACKUP_DIR}/library/"
if rsync -avh --delete --inplace --stats "$LIBRARY_SOURCE" "$LIBRARY_BACKUP" | tee "$RSYNC_OUT"; then
    log "Library backup completed: $LIBRARY_BACKUP"
    SUMMARY_LIBRARY="files sent $(rsync_stat 'Number of regular files transferred') ($(rsync_stat 'Total transferred file size')), deleted $(rsync_stat 'Number of deleted files'), total $(rsync_stat 'Number of files') / $(rsync_stat 'Total file size')"
else
    log "ERROR: Library backup failed"
    SUMMARY_LIBRARY="FAILED"
    exit 1
fi

# Containers restart, total time and the summary are handled by on_exit
STEP="done"
