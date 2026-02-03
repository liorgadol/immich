#!/bin/bash

#############################################################
# Immich Backup Configuration - SMB Share (Ubuntu)
#############################################################

# Immich installation directory
IMMICH_DIR="/Users/gadol/dev/immich"

# Backup type
BACKUP_TYPE="smb"

# This is not used for SMB backups but required
BACKUP_DESTINATION=""

# SMB share configuration
# Format: //server_ip_or_hostname/share_name
# Examples:
#   //192.168.1.100/immich-backups
#   //nas.local/backups
SMB_SHARE="//192.168.1.100/backups"

# Local mount point (will be created if it doesn't exist)
SMB_MOUNT_POINT="/mnt/immich-backup"

# SMB credentials
SMB_USERNAME="backup_user"
SMB_PASSWORD="your_password"
SMB_DOMAIN=""  # Leave empty if not using Windows domain

# Additional mount options for better compatibility
# vers=3.0 - Use SMB version 3.0 (good compatibility)
# uid/gid - Set file ownership (use your user's uid/gid)
SMB_MOUNT_OPTIONS="vers=3.0,uid=1000,gid=1000"

# Automatically unmount after backup
AUTO_UNMOUNT_SMB="true"

# Docker settings
DOCKER_COMPOSE_FILE="${IMMICH_DIR}/docker-compose.yml"
DB_CONTAINER="immich_postgres"

# Backup retention in days
BACKUP_RETENTION_DAYS=14

# Rsync settings
RSYNC_COMPRESS="true"   # Enable compression for network transfer
RSYNC_EXCLUDE=""

# ====================
# SETUP INSTRUCTIONS FOR UBUNTU
# ====================
#
# 1. Install required packages:
#    sudo apt-get update
#    sudo apt-get install cifs-utils rsync
#
# 2. (Optional but recommended) Use a credentials file for better security:
#    a. Create credentials file:
#       sudo nano /etc/immich-backup-credentials
#    
#    b. Add these lines:
#       username=backup_user
#       password=your_password
#       domain=YOUR_DOMAIN (if applicable)
#    
#    c. Secure the file:
#       sudo chmod 600 /etc/immich-backup-credentials
#    
#    d. Update SMB_MOUNT_OPTIONS above:
#       SMB_MOUNT_OPTIONS="credentials=/etc/immich-backup-credentials,vers=3.0,uid=1000,gid=1000"
#    
#    e. Clear the password in this file:
#       SMB_USERNAME=""
#       SMB_PASSWORD=""
#
# 3. Verify your user can use sudo without password for mount/umount:
#    Or add this to /etc/sudoers (use 'sudo visudo'):
#       your_username ALL=(ALL) NOPASSWD: /bin/mount, /bin/umount, /bin/mkdir
#
# 4. Test the mount manually first:
#    sudo mkdir -p /mnt/immich-backup
#    sudo mount -t cifs //server/share /mnt/immich-backup -o username=user,password=pass
#    ls /mnt/immich-backup
#    sudo umount /mnt/immich-backup
