# Immich Backup & Restore Scripts

Complete backup and restore solution for Immich installations with support for local storage and SMB network shares.

## Features

- **PostgreSQL Database Backup**: Uses `pg_dump` for clean, compressed database backups
- **File System Backup**: Uses `rsync` for efficient, incremental file backups
- **Flexible Destinations**: Supports both local storage and SMB/CIFS network shares
- **Automatic Cleanup**: Configurable retention policy for old backups
- **Safe Restore**: Interactive restore process with confirmation prompts
- **Comprehensive Logging**: Color-coded output for easy monitoring

## Prerequisites

### For All Systems
- Docker and Docker Compose
- rsync
- bash

### For SMB Backups on Ubuntu
```bash
sudo apt-get update
sudo apt-get install cifs-utils rsync
```

## Quick Start

### 1. Setup Configuration

Choose the appropriate config file for your backup destination:

#### For Local Storage:
```bash
cp backup-config-local.sh backup-config.sh
nano backup-config.sh
```

Edit these settings:
```bash
IMMICH_DIR="/Users/gadol/dev/immich"          # Your Immich installation path
BACKUP_DESTINATION="/path/to/backups/immich"  # Where to store backups
BACKUP_RETENTION_DAYS=7                        # How many days to keep old backups
```

#### For SMB Share (Ubuntu):
```bash
cp backup-config-smb.sh backup-config.sh
nano backup-config.sh
```

Edit these settings:
```bash
IMMICH_DIR="/Users/gadol/dev/immich"
SMB_SHARE="//192.168.1.100/backups"           # Your SMB share
SMB_MOUNT_POINT="/mnt/immich-backup"          # Local mount point
SMB_USERNAME="your_username"
SMB_PASSWORD="your_password"
```

### 2. Make Scripts Executable

```bash
chmod +x backup-immich.sh restore-immich.sh
```

### 3. Run Your First Backup

```bash
./backup-immich.sh
```

Or with a specific config file:
```bash
./backup-immich.sh backup-config-local.sh
```

## Detailed Configuration

### Configuration Files

- `backup-config.example.sh` - Template with all options explained
- `backup-config-local.sh` - Pre-configured for local storage
- `backup-config-smb.sh` - Pre-configured for SMB shares with Ubuntu setup instructions

### Key Configuration Options

```bash
# Required Settings
IMMICH_DIR="/Users/gadol/dev/immich"          # Immich installation directory
BACKUP_TYPE="local"                            # "local" or "smb"
BACKUP_DESTINATION="/path/to/backups"         # For local backups

# SMB Settings (when BACKUP_TYPE="smb")
SMB_SHARE="//server/share"                    # SMB share path
SMB_MOUNT_POINT="/mnt/immich-backup"          # Local mount point
SMB_USERNAME="user"                            # SMB username
SMB_PASSWORD="pass"                            # SMB password (see security note below)
SMB_DOMAIN=""                                  # Windows domain (optional)
AUTO_UNMOUNT_SMB="true"                        # Auto-unmount after backup

# Docker Settings
DB_CONTAINER="immich_postgres"                # Database container name

# Backup Settings
BACKUP_RETENTION_DAYS=7                        # Days to keep old backups (0=keep all)

# Rsync Settings
RSYNC_COMPRESS="true"                          # Compress during transfer
RSYNC_EXCLUDE=""                               # Patterns to exclude
```

## Security Best Practices for SMB

Instead of storing passwords in the config file, use a credentials file:

### 1. Create a credentials file:
```bash
sudo nano /etc/immich-backup-credentials
```

### 2. Add your credentials:
```
username=your_username
password=your_password
domain=YOUR_DOMAIN
```

### 3. Secure the file:
```bash
sudo chmod 600 /etc/immich-backup-credentials
sudo chown root:root /etc/immich-backup-credentials
```

### 4. Update your config:
```bash
SMB_USERNAME=""
SMB_PASSWORD=""
SMB_MOUNT_OPTIONS="credentials=/etc/immich-backup-credentials,vers=3.0,uid=1000,gid=1000"
```

## What Gets Backed Up

The backup script creates a timestamped directory containing:

```
immich_backup_YYYYMMDD_HHMMSS/
├── backup_info.txt              # Backup metadata
├── database_YYYYMMDD_HHMMSS.sql.gz  # Compressed database dump
└── files/
    ├── config/
    │   ├── docker-compose.yml   # Docker configuration
    │   └── .env                 # Environment variables
    ├── library/                 # Immich media files
    └── postgres/                # PostgreSQL data directory
```

## Restoring from Backup

### ⚠️ Warning
Restoring will **OVERWRITE** your current Immich installation. Make sure you have a current backup before proceeding.

### Restore Process

```bash
./restore-immich.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS
```

Or specify a different Immich directory:
```bash
./restore-immich.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS /path/to/immich
```

The restore script will:
1. Stop all Immich containers
2. Drop and recreate the database
3. Restore the database from the backup
4. Restore all files (library, postgres data, configs)
5. Ask if you want to start Immich

## Automation with Cron

### Daily Backups at 2 AM

```bash
crontab -e
```

Add this line:
```cron
0 2 * * * /Users/gadol/dev/immich/backup-immich.sh >> /var/log/immich-backup.log 2>&1
```

### Weekly Backups (Sunday at 3 AM)

```cron
0 3 * * 0 /Users/gadol/dev/immich/backup-immich.sh >> /var/log/immich-backup.log 2>&1
```

### For SMB backups, ensure sudo works without password

Add to `/etc/sudoers` (use `sudo visudo`):
```
your_username ALL=(ALL) NOPASSWD: /bin/mount, /bin/umount, /bin/mkdir
```

## Monitoring Backups

### Check Backup Log
```bash
tail -f /var/log/immich-backup.log
```

### List All Backups
```bash
ls -lh /path/to/backups/
```

### Check Backup Size
```bash
du -sh /path/to/backups/immich_backup_*
```

## Troubleshooting

### Database Connection Issues
- Ensure the database container is running: `docker ps | grep postgres`
- Check database credentials in `.env` file
- Verify container name matches `DB_CONTAINER` in config

### SMB Mount Issues
- Test manual mount: `sudo mount -t cifs //server/share /mnt/test -o username=user,password=pass`
- Check SMB version compatibility: Try different `vers=` options (1.0, 2.0, 2.1, 3.0)
- Verify network connectivity: `ping server_ip`
- Check firewall rules on SMB server

### Permission Issues
- For local backups: Ensure write permissions to backup destination
- For SMB: Check uid/gid in mount options match your user
- Use `id` command to find your uid/gid

### Rsync Errors
- Check source directories exist: `ls -la /Users/gadol/dev/immich/`
- Verify sufficient disk space: `df -h`
- Review rsync exclude patterns if files are missing

## Testing Your Backup

It's important to regularly test that your backups can be restored:

### 1. Test in a Different Location
```bash
# Create a test directory
mkdir -p /tmp/immich-test
cp docker-compose.yml /tmp/immich-test/
cp .env /tmp/immich-test/

# Restore to test location
./restore-immich.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS /tmp/immich-test
```

### 2. Verify Backup Contents
```bash
# Check database backup
gunzip -c /path/to/backup/immich_backup_*/database_*.sql.gz | head -n 50

# Check files
ls -lh /path/to/backup/immich_backup_*/files/
```

## Upgrading Immich

Before upgrading Immich:
1. Run a backup
2. Verify backup completed successfully
3. Test backup if possible
4. Proceed with upgrade
5. Keep backup for at least one retention period after successful upgrade

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review script logs for detailed error messages
3. Verify configuration settings
4. Test individual components (docker, rsync, mount) separately

## File Descriptions

- `backup-immich.sh` - Main backup script
- `restore-immich.sh` - Restore script
- `backup-config.example.sh` - Configuration template with all options
- `backup-config-local.sh` - Quick start config for local storage
- `backup-config-smb.sh` - Quick start config for SMB shares
- `README-BACKUP.md` - This documentation file

## License

Use these scripts at your own risk. Always test backups before relying on them in production.
