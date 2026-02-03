#!/bin/bash

#############################################################
# Immich Backup Configuration - Example
#
# Copy this file to backup-config.sh and adjust the values
# according to your setup.
#############################################################

# ====================
# REQUIRED SETTINGS
# ====================

# Immich installation directory (where docker-compose.yml is located)
IMMICH_DIR="/Users/gadol/dev/immich"

# Backup type: "local" or "smb"
BACKUP_TYPE="local"

# For local backups: full path to backup destination
# For SMB backups: this is ignored (use SMB_MOUNT_POINT instead)
BACKUP_DESTINATION="/path/to/backup/destination"

# ====================
# SMB SETTINGS (only needed if BACKUP_TYPE="smb")
# ====================

# SMB share path (format: //server/share)
# Example: //192.168.1.100/backups or //nas.local/immich-backups
SMB_SHARE="//server/share"

# Local mount point for SMB share
SMB_MOUNT_POINT="/mnt/immich-backup"

# SMB credentials
SMB_USERNAME="your_username"
SMB_PASSWORD="your_password"  # Optional: leave empty for guest access or use credentials file
SMB_DOMAIN=""                  # Optional: Windows domain (if applicable)

# Additional mount options (optional)
# Example: "vers=3.0,uid=1000,gid=1000"
SMB_MOUNT_OPTIONS=""

# Automatically unmount SMB share after backup (true/false)
AUTO_UNMOUNT_SMB="true"

# ====================
# DOCKER SETTINGS
# ====================

# Docker Compose file location (defaults to $IMMICH_DIR/docker-compose.yml)
DOCKER_COMPOSE_FILE="${IMMICH_DIR}/docker-compose.yml"

# PostgreSQL container name (default: immich_postgres)
DB_CONTAINER="immich_postgres"

# ====================
# BACKUP SETTINGS
# ====================

# Number of days to keep old backups (0 = keep all)
BACKUP_RETENTION_DAYS=7

# ====================
# RSYNC SETTINGS
# ====================

# Enable compression during transfer (true/false)
# Useful for network transfers, may slow down local backups
RSYNC_COMPRESS="true"

# Patterns to exclude from backup (space-separated)
# Example: "*.tmp cache/* *.log"
RSYNC_EXCLUDE=""

# ====================
# NOTES
# ====================

# For SMB backups on Ubuntu, ensure cifs-utils is installed:
#   sudo apt-get install cifs-utils
#
# For better security, consider using a credentials file instead of
# storing password in this config:
#   1. Create a file: /etc/immich-backup-credentials
#   2. Add: username=your_username
#           password=your_password
#           domain=your_domain (optional)
#   3. Set permissions: sudo chmod 600 /etc/immich-backup-credentials
#   4. Use in SMB_MOUNT_OPTIONS: "credentials=/etc/immich-backup-credentials"
#   5. Leave SMB_USERNAME and SMB_PASSWORD empty in this config
