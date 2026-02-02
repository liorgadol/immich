#!/bin/bash

#############################################################
# Immich Backup Configuration - Local Storage
#############################################################

# Immich installation directory
IMMICH_DIR="/Users/gadol/dev/immich"

# Backup type
BACKUP_TYPE="local"

# Local backup destination (adjust to your preferred location)
BACKUP_DESTINATION="/path/to/local/backups/immich"

# Docker Compose file location
DOCKER_COMPOSE_FILE="${IMMICH_DIR}/docker-compose.yml"

# PostgreSQL container name
DB_CONTAINER="immich_postgres"

# Backup retention in days (0 = keep all)
BACKUP_RETENTION_DAYS=7

# Rsync settings
RSYNC_COMPRESS="false"  # No need for compression on local storage
RSYNC_EXCLUDE=""        # Add patterns to exclude if needed
