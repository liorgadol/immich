#!/bin/bash

#############################################################
# Immich Restore Script
# 
# This script restores an Immich backup (database and files)
#
# Usage:
#   ./restore-immich.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS
#############################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if backup path is provided
if [[ $# -lt 1 ]]; then
    log_error "Usage: $0 /path/to/backup/immich_backup_YYYYMMDD_HHMMSS [immich_dir]"
    exit 1
fi

BACKUP_DIR="$1"
IMMICH_DIR="${2:-/Users/gadol/dev/immich}"

# Check if backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

# Check if backup info file exists
if [[ ! -f "${BACKUP_DIR}/backup_info.txt" ]]; then
    log_warn "backup_info.txt not found. This might not be a valid backup."
fi

log_info "=========================================="
log_info "Immich Restore"
log_info "=========================================="
log_info "Backup Directory: $BACKUP_DIR"
log_info "Restore to: $IMMICH_DIR"
log_info ""

# Warning prompt
log_warn "WARNING: This will OVERWRITE existing Immich data!"
log_warn "Make sure Immich containers are stopped before proceeding."
echo -e "${YELLOW}Type 'yes' to continue:${NC}"
read -r confirmation

if [[ "$confirmation" != "yes" ]]; then
    log_info "Restore cancelled."
    exit 0
fi

# Container names
DB_CONTAINER="immich_postgres"

# Function to get database credentials
get_db_credentials() {
    ENV_FILE="${IMMICH_DIR}/.env"
    
    if [[ -f "$ENV_FILE" ]]; then
        DB_USERNAME=$(grep "^DB_USERNAME=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        DB_PASSWORD=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        DB_NAME=$(grep "^DB_DATABASE_NAME=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        
        DB_USERNAME="${DB_USERNAME:-postgres}"
        DB_PASSWORD="${DB_PASSWORD:-postgres}"
        DB_NAME="${DB_NAME:-immich}"
    else
        log_error ".env file not found at: $ENV_FILE"
        exit 1
    fi
}

# Function to stop Immich containers
stop_containers() {
    log_info "Stopping Immich containers..."
    cd "$IMMICH_DIR"
    
    if docker compose ps -q | grep -q .; then
        docker compose down
        log_info "Containers stopped"
    else
        log_info "Containers already stopped"
    fi
}

# Function to restore database
restore_database() {
    log_info "Restoring database..."
    
    # Find the database backup file
    local db_backup_file=$(find "$BACKUP_DIR" -name "database_*.sql.gz" | head -n 1)
    
    if [[ -z "$db_backup_file" ]]; then
        log_error "Database backup file not found in: $BACKUP_DIR"
        return 1
    fi
    
    log_info "Found database backup: $(basename "$db_backup_file")"
    
    # Start only the database container
    log_info "Starting database container..."
    cd "$IMMICH_DIR"
    docker compose up -d database
    
    # Wait for database to be ready
    log_info "Waiting for database to be ready..."
    sleep 10
    
    for i in {1..30}; do
        if docker exec "$DB_CONTAINER" pg_isready -U "$DB_USERNAME" > /dev/null 2>&1; then
            log_info "Database is ready"
            break
        fi
        if [[ $i -eq 30 ]]; then
            log_error "Database did not become ready in time"
            return 1
        fi
        sleep 2
    done
    
    # Drop and recreate database
    log_info "Dropping and recreating database..."
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USERNAME" -c "DROP DATABASE IF EXISTS $DB_NAME;" postgres
    docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USERNAME" -c "CREATE DATABASE $DB_NAME;" postgres
    
    # Restore database from backup
    log_info "Restoring database from backup..."
    gunzip -c "$db_backup_file" | docker exec -i -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        psql -U "$DB_USERNAME" -d "$DB_NAME"
    
    log_info "Database restore completed"
    
    # Stop database container
    docker compose stop database
}

# Function to restore files
restore_files() {
    log_info "Restoring files..."
    
    local files_backup_dir="${BACKUP_DIR}/files"
    
    if [[ ! -d "$files_backup_dir" ]]; then
        log_error "Files backup directory not found: $files_backup_dir"
        return 1
    fi
    
    # Restore configuration files
    if [[ -d "${files_backup_dir}/config" ]]; then
        log_info "Restoring configuration files..."
        
        if [[ -f "${files_backup_dir}/config/docker-compose.yml" ]]; then
            cp "${files_backup_dir}/config/docker-compose.yml" "$IMMICH_DIR/" && \
                log_info "Restored docker-compose.yml"
        fi
        
        if [[ -f "${files_backup_dir}/config/.env" ]]; then
            # Backup current .env before overwriting
            if [[ -f "${IMMICH_DIR}/.env" ]]; then
                cp "${IMMICH_DIR}/.env" "${IMMICH_DIR}/.env.backup-$(date +%Y%m%d_%H%M%S)"
                log_info "Current .env backed up"
            fi
            cp "${files_backup_dir}/config/.env" "$IMMICH_DIR/" && \
                log_info "Restored .env"
        fi
    fi
    
    # Restore data directories
    local dirs_to_restore=("library" "postgres")
    
    for dir in "${dirs_to_restore[@]}"; do
        if [[ -d "${files_backup_dir}/${dir}" ]]; then
            log_info "Restoring: $dir"
            
            # Create target directory if it doesn't exist
            mkdir -p "${IMMICH_DIR}/${dir}"
            
            # Use rsync to restore
            if rsync -aAXv --delete "${files_backup_dir}/${dir}/" "${IMMICH_DIR}/${dir}/"; then
                log_info "Successfully restored: $dir"
            else
                log_error "Failed to restore: $dir"
                return 1
            fi
        else
            log_warn "Directory not found in backup, skipping: $dir"
        fi
    done
    
    log_info "File restore completed"
}

# Function to start Immich
start_immich() {
    log_info "Starting Immich containers..."
    cd "$IMMICH_DIR"
    docker compose up -d
    log_info "Immich started"
}

# Main restore function
main() {
    # Get database credentials
    get_db_credentials
    
    # Stop containers
    stop_containers
    
    # Perform restore
    local restore_failed=0
    
    if ! restore_database; then
        restore_failed=1
    fi
    
    if ! restore_files; then
        restore_failed=1
    fi
    
    if [[ $restore_failed -eq 0 ]]; then
        log_info "=========================================="
        log_info "Restore completed successfully!"
        log_info "=========================================="
        
        # Ask if user wants to start Immich
        echo -e "${YELLOW}Start Immich now? (yes/no):${NC}"
        read -r start_now
        
        if [[ "$start_now" == "yes" ]]; then
            start_immich
            log_info "Immich is starting. Check status with: docker compose ps"
        else
            log_info "You can start Immich later with: docker compose up -d"
        fi
    else
        log_error "=========================================="
        log_error "Restore completed with errors!"
        log_error "Check the logs above for details"
        log_error "=========================================="
        exit 1
    fi
}

# Run main function
main
