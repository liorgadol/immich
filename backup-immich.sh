#!/bin/bash

#############################################################
# Immich Backup Script
# 
# This script backs up both the PostgreSQL database and
# all Immich files to a local or SMB destination.
#
# Usage:
#   ./backup-immich.sh [config_file]
#
# If no config file is specified, it will use backup-config.sh
#############################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default config file
CONFIG_FILE="${1:-${SCRIPT_DIR}/backup-config.sh}"

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

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    log_info "Please create a config file. See backup-config.example.sh for reference."
    exit 1
fi

# Source the config file
log_info "Loading configuration from: $CONFIG_FILE"
source "$CONFIG_FILE"

# Validate required configuration
if [[ -z "${IMMICH_DIR:-}" ]]; then
    log_error "IMMICH_DIR not set in config file"
    exit 1
fi

if [[ -z "${BACKUP_DESTINATION:-}" ]]; then
    log_error "BACKUP_DESTINATION not set in config file"
    exit 1
fi

if [[ -z "${BACKUP_TYPE:-}" ]]; then
    log_error "BACKUP_TYPE not set in config file (should be 'local' or 'smb')"
    exit 1
fi

# Set default values if not specified
DOCKER_COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-${IMMICH_DIR}/docker-compose.yml}"
DB_CONTAINER="${DB_CONTAINER:-immich_postgres}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="immich_backup_${TIMESTAMP}"

# Check if docker-compose file exists
if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
    log_error "docker-compose.yml not found at: $DOCKER_COMPOSE_FILE"
    exit 1
fi

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

# Function to mount SMB share if needed
mount_smb_share() {
    if [[ "$BACKUP_TYPE" == "smb" ]]; then
        log_info "Checking SMB mount..."
        
        if [[ -z "${SMB_SHARE:-}" ]] || [[ -z "${SMB_MOUNT_POINT:-}" ]]; then
            log_error "SMB_SHARE and SMB_MOUNT_POINT must be set for SMB backup"
            exit 1
        fi
        
        # Create mount point if it doesn't exist
        sudo mkdir -p "$SMB_MOUNT_POINT"
        
        # Check if already mounted
        if mountpoint -q "$SMB_MOUNT_POINT"; then
            log_info "SMB share already mounted at $SMB_MOUNT_POINT"
        else
            log_info "Mounting SMB share..."
            
            # Build mount options
            MOUNT_OPTS="username=${SMB_USERNAME:-guest}"
            if [[ -n "${SMB_PASSWORD:-}" ]]; then
                MOUNT_OPTS="${MOUNT_OPTS},password=${SMB_PASSWORD}"
            else
                MOUNT_OPTS="${MOUNT_OPTS},guest"
            fi
            
            if [[ -n "${SMB_DOMAIN:-}" ]]; then
                MOUNT_OPTS="${MOUNT_OPTS},domain=${SMB_DOMAIN}"
            fi
            
            # Add additional options if specified
            if [[ -n "${SMB_MOUNT_OPTIONS:-}" ]]; then
                MOUNT_OPTS="${MOUNT_OPTS},${SMB_MOUNT_OPTIONS}"
            fi
            
            # Mount the share
            if sudo mount -t cifs "$SMB_SHARE" "$SMB_MOUNT_POINT" -o "$MOUNT_OPTS"; then
                log_info "SMB share mounted successfully"
            else
                log_error "Failed to mount SMB share"
                exit 1
            fi
        fi
        
        BACKUP_BASE_DIR="$SMB_MOUNT_POINT"
    else
        BACKUP_BASE_DIR="$BACKUP_DESTINATION"
    fi
}

# Function to unmount SMB share if needed
unmount_smb_share() {
    if [[ "$BACKUP_TYPE" == "smb" ]] && [[ "${AUTO_UNMOUNT_SMB:-true}" == "true" ]]; then
        if mountpoint -q "$SMB_MOUNT_POINT"; then
            log_info "Unmounting SMB share..."
            sudo umount "$SMB_MOUNT_POINT" || log_warn "Failed to unmount SMB share"
        fi
    fi
}

# Function to get database credentials from .env file
get_db_credentials() {
    ENV_FILE="${IMMICH_DIR}/.env"
    
    if [[ -f "$ENV_FILE" ]]; then
        DB_USERNAME=$(grep "^DB_USERNAME=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        DB_PASSWORD=$(grep "^DB_PASSWORD=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        DB_NAME=$(grep "^DB_DATABASE_NAME=" "$ENV_FILE" | cut -d '=' -f2 | tr -d '"' | tr -d "'")
        
        # Set defaults if not found
        DB_USERNAME="${DB_USERNAME:-postgres}"
        DB_PASSWORD="${DB_PASSWORD:-postgres}"
        DB_NAME="${DB_NAME:-immich}"
    else
        log_warn ".env file not found, using defaults"
        DB_USERNAME="postgres"
        DB_PASSWORD="postgres"
        DB_NAME="immich"
    fi
}

# Function to backup PostgreSQL database
backup_database() {
    log_info "Starting database backup..."
    
    local db_backup_file="${BACKUP_DIR}/database_${TIMESTAMP}.sql.gz"
    
    # Get database credentials
    get_db_credentials
    
    # Check if database container is running
    if ! docker ps | grep -q "$DB_CONTAINER"; then
        log_error "Database container '$DB_CONTAINER' is not running"
        return 1
    fi
    
    # Perform database backup using pg_dump
    if docker exec -e PGPASSWORD="$DB_PASSWORD" "$DB_CONTAINER" \
        pg_dump -U "$DB_USERNAME" -d "$DB_NAME" --clean --if-exists | gzip > "$db_backup_file"; then
        log_info "Database backup completed: $db_backup_file"
        log_info "Database backup size: $(du -h "$db_backup_file" | cut -f1)"
        return 0
    else
        log_error "Database backup failed"
        return 1
    fi
}

# Function to backup files using rsync
backup_files() {
    log_info "Starting file backup..."
    
    local files_backup_dir="${BACKUP_DIR}/files"
    mkdir -p "$files_backup_dir"
    
    # Define directories to backup
    local dirs_to_backup=(
        "library"
        "postgres"
    )
    
    # Add docker-compose.yml and .env to backup
    log_info "Backing up configuration files..."
    mkdir -p "${files_backup_dir}/config"
    cp "$DOCKER_COMPOSE_FILE" "${files_backup_dir}/config/" || log_warn "Failed to copy docker-compose.yml"
    
    if [[ -f "${IMMICH_DIR}/.env" ]]; then
        cp "${IMMICH_DIR}/.env" "${files_backup_dir}/config/" || log_warn "Failed to copy .env"
    fi
    
    # Rsync options
    RSYNC_OPTS="-aAXv --delete"
    
    if [[ "${RSYNC_COMPRESS:-true}" == "true" ]]; then
        RSYNC_OPTS="${RSYNC_OPTS} --compress"
    fi
    
    if [[ -n "${RSYNC_EXCLUDE:-}" ]]; then
        for pattern in $RSYNC_EXCLUDE; do
            RSYNC_OPTS="${RSYNC_OPTS} --exclude=${pattern}"
        done
    fi
    
    # Backup each directory
    for dir in "${dirs_to_backup[@]}"; do
        local source_dir="${IMMICH_DIR}/${dir}"
        
        if [[ -d "$source_dir" ]]; then
            log_info "Backing up: $dir"
            
            if rsync $RSYNC_OPTS "$source_dir/" "${files_backup_dir}/${dir}/"; then
                log_info "Successfully backed up: $dir"
            else
                log_error "Failed to backup: $dir"
                return 1
            fi
        else
            log_warn "Directory not found, skipping: $source_dir"
        fi
    done
    
    log_info "File backup completed"
    log_info "Total backup size: $(du -sh "$files_backup_dir" | cut -f1)"
    return 0
}

# Function to create backup info file
create_backup_info() {
    local info_file="${BACKUP_DIR}/backup_info.txt"
    
    cat > "$info_file" << EOF
Immich Backup Information
=========================
Backup Date: $(date)
Backup Name: $BACKUP_NAME
Immich Directory: $IMMICH_DIR
Docker Compose File: $DOCKER_COMPOSE_FILE

Database Container: $DB_CONTAINER
Database Name: $DB_NAME
Database User: $DB_USERNAME

Backup Contents:
- PostgreSQL database dump (compressed)
- Immich library files
- PostgreSQL data directory
- Configuration files (docker-compose.yml, .env)

Backup completed successfully.
EOF
    
    log_info "Backup info saved to: $info_file"
}

# Function to cleanup old backups
cleanup_old_backups() {
    if [[ "$BACKUP_RETENTION_DAYS" -gt 0 ]]; then
        log_info "Cleaning up backups older than $BACKUP_RETENTION_DAYS days..."
        
        find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "immich_backup_*" -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true
        
        log_info "Cleanup completed"
    fi
}

# Main backup function
main() {
    log_info "=========================================="
    log_info "Starting Immich Backup: $BACKUP_NAME"
    log_info "=========================================="
    log_info "Immich Directory: $IMMICH_DIR"
    log_info "Backup Type: $BACKUP_TYPE"
    
    # Mount SMB share if needed
    mount_smb_share
    
    # Create backup directory
    BACKUP_DIR="${BACKUP_BASE_DIR}/${BACKUP_NAME}"
    mkdir -p "$BACKUP_DIR"
    log_info "Backup Directory: $BACKUP_DIR"
    
    # Trap to ensure cleanup on exit
    trap unmount_smb_share EXIT
    
    # Perform backups
    local backup_failed=0
    
    if ! backup_database; then
        backup_failed=1
    fi
    
    if ! backup_files; then
        backup_failed=1
    fi
    
    if [[ $backup_failed -eq 0 ]]; then
        create_backup_info
        cleanup_old_backups
        
        log_info "=========================================="
        log_info "Backup completed successfully!"
        log_info "Backup location: $BACKUP_DIR"
        log_info "=========================================="
    else
        log_error "=========================================="
        log_error "Backup completed with errors!"
        log_error "Check the logs above for details"
        log_error "=========================================="
        exit 1
    fi
}

# Run main function
main
