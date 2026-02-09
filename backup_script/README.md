# Immich Backup Script

Complete backup solution for your Immich installation, including database, configuration files, and all media files.

## 📋 Overview

The `backup-immich.sh` script provides automated backups of your entire Immich installation:

- **PostgreSQL Database**: Compressed SQL dumps with automatic rotation
- **Media Library**: Complete backup of all photos and videos using rsync
- **Configuration Files**: `.env` and `docker-compose.yml` backups
- **Detailed Logging**: All operations logged to `backup.log`
- **Cron Compatible**: Absolute paths for scheduled backups

## 🚀 Quick Start

### Manual Backup

```bash
cd backup_script
./backup-immich.sh
```

The script will:
1. **Stop the immich_server container** (for data consistency)
2. Set up a safety trap to ensure server restart even if script fails
3. Backup the PostgreSQL database (compressed)
4. Clean up old database backups (keeps last 4)
5. Backup configuration files (.env and docker-compose.yml)
6. Sync the library folder with rsync
7. **Restart the immich_server container**
8. Log all operations with timestamps

### Automated Backups (Cron)

To schedule daily backups at 2 AM:

```bash
crontab -e
```

Add this line (update the path to match your installation):
```
0 2 * * * /path/to/immich/backup_script/backup-immich.sh
```

## 📁 Backup Location

By default, all backups are stored in:
```
/mnt/data/immich/backup/
├── immich_db_backup_YYYYMMDD_HHMMSS.sql.gz  # Database backups (up to 4 kept)
├── library/                                   # Full library backup (synced)
├── env_backup                                 # Latest .env backup
├── docker-compose_backup.yml                  # Latest docker-compose.yml backup
└── backup.log                                 # Latest backup log
```

## ⚙️ Configuration

### Required Environment Variables

Add these to your `.env` file (they're likely already there from your Immich setup):

```bash
# Database configuration (required by Immich)
DB_PASSWORD=your-secure-database-password
DB_USERNAME=postgres
DB_DATABASE_NAME=immich

# Upload location (required by Immich)
UPLOAD_LOCATION=/mnt/data/immich/library

# Optional backup configuration (add these if you want to customize)
BACKUP_DIR=/mnt/data/immich/backup    # Where backups are stored
MAX_BACKUPS=4                          # Number of database backups to keep
DB_CONTAINER=immich_postgres          # Database container name
```

### Auto-Detection

The script automatically detects:
- **Script location**: Finds the Immich directory relative to the script
- **`.env` file**: Loads from the Immich directory
- **Default values**: Uses sensible defaults if optional variables aren't set

No hardcoded paths needed! The script adapts to your installation location.

## 📊 What Gets Backed Up

### 1. PostgreSQL Database
- **Format**: Compressed SQL dump (`.sql.gz`)
- **Retention**: Last 4 backups (older ones automatically deleted)
- **Includes**: All database tables, users, permissions
- **Options**: `--clean --if-exists` flags for safe restoration

### 2. Media Library
- **Method**: rsync with `--delete` flag
- **Location**: `/mnt/data/immich/library/`
- **Features**: 
  - Incremental sync (only changed files copied)
  - Mirror of source (deleted files removed from backup)
  - Preserves permissions and timestamps

### 3. Configuration Files
- **Files**: `.env` and `docker-compose.yml`
- **Retention**: Latest version only
- **Purpose**: Quick disaster recovery

## � Container Management & Safety

### Immich Server Stop/Start Process

The script **stops the `immich_server` container** during backup to ensure data consistency:

```bash
# Stops before backup
docker stop immich_server

# Performs all backup operations...

# Restarts after backup
docker start immich_server
```

### Safety Trap Mechanism

The script includes a **safety trap** that guarantees the server restarts even if the backup fails:

```bash
trap 'docker start immich_server' EXIT
```

This means:
- ✅ If backup succeeds → server restarts normally
- ✅ If backup fails → server still restarts (via trap)
- ✅ If script is interrupted → server still restarts (via trap)
- ✅ Power loss during backup → server starts automatically on next boot (Docker restart policy)

### Why Stop the Server?

Stopping `immich_server` (while keeping database running) ensures:
- **Data consistency**: No writes during database dump
- **Clean snapshots**: Library files aren't being modified during rsync
- **Reliable restores**: Backup represents a consistent point in time

**Note**: Only `immich_server` is stopped. The database container continues running for the pg_dump operation.

## �🔄 Restore Process

### Restore Database

1. **Stop Immich services**:
   ```bash
   cd /home/gadol/projects/immich
   docker compose down
   ```

2. **Restore the database**:
   ```bash
   # Choose your backup file
   BACKUP_FILE="/mnt/data/immich/backup/immich_db_backup_YYYYMMDD_HHMMSS.sql.gz"
   
   # Start only the database
   docker compose up -d database
   
   # Wait for database to be ready
   sleep 5
   
   # Restore
   gunzip -c "$BACKUP_FILE" | docker exec -i immich_postgres psql -U postgres -d immich
   ```

3. **Restart all services**:
   ```bash
   docker compose up -d
   ```

### Restore Media Library

To restore individual files:
```bash
cp /mnt/data/immich/backup/library/path/to/file /mnt/data/immich/library/path/to/file
```

For complete restore:
```bash
rsync -avh /mnt/data/immich/backup/library/ /mnt/data/immich/library/
```

### Restore Configuration

```bash
cp /mnt/data/immich/backup/env_backup /home/gadol/projects/immich/.env
cp /mnt/data/immich/backup/docker-compose_backup.yml /home/gadol/projects/immich/docker-compose.yml
```

## 📝 Logging

All backup operations are logged to:
```
/mnt/data/immich/backup/backup.log
```

The log includes:
- Start/end timestamps
- Operations performed
- File sizes
- Errors and warnings
- Total backup duration

View the last backup log:
```bash
cat /mnt/data/immich/backup/backup.log
```

## ⚠️ Important Notes

### Downtime
The script **stops only the `immich_server` container** during backup (database, Redis, and ML containers keep running). This ensures data consistency while minimizing downtime:

- **Container stopped**: `immich_server` only
- **Containers running**: `database` (for pg_dump), `redis`, `immich_machine_learning`
- **Database backup**: 10-30 seconds (varies by size)
- **Library rsync**: Varies by changes (initial backup takes longer)
- **Total downtime**: Usually under 1 minute for incremental backups
- **Safety**: Automatic restart even if backup fails (via trap mechanism)

### Storage Requirements
Ensure sufficient space in `/mnt/data/immich/backup/`:
- Database: Usually a few hundred MB (compressed)
- Library: Same size as your media collection
- **Total**: `library_size + (4 × database_size)`

### Backup Rotation
- **Database**: Keeps last 4 backups automatically
- **Library**: Mirrors current state (no history)
- **Config**: Keeps only latest version

To change database retention, edit `MAX_BACKUPS` in the script.

## 🔍 Verification

### Check Backup Status

```bash
# View backup directory
ls -lh /mnt/data/immich/backup/

# Check database backups
ls -lh /mnt/data/immich/backup/immich_db_backup_*.sql.gz

# View last backup log
cat /mnt/data/immich/backup/backup.log
```

### Test Backup Integrity

Test database backup:
```bash
gunzip -t /mnt/data/immich/backup/immich_db_backup_YYYYMMDD_HHMMSS.sql.gz
echo $?  # Should output 0 for success
```

### Dry Run Restore

Test restore without making changes:
```bash
gunzip -c /mnt/data/immich/backup/immich_db_backup_YYYYMMDD_HHMMSS.sql.gz | head -n 20
```

## 🐛 Troubleshooting

### Script Fails to Run

Check permissions:
```bash
chmod +x /home/gadol/projects/immich/backup_script/backup-immich.sh
```

### Database Backup Fails

Verify credentials:
```bash
source /home/gadol/projects/immich/.env
echo $DB_PASSWORD
docker exec immich_postgres psql -U $DB_USERNAME -d $DB_NAME -c "SELECT 1"
```

### Out of Disk Space

Check available space:
```bash
df -h /mnt/data/immich/backup
```

Reduce backup retention:
```bash
# Edit MAX_BACKUPS in backup-immich.sh
nano /home/gadol/projects/immich/backup_script/backup-immich.sh
```

### Immich Server Won't Restart

The script has a trap to ensure restart even on failure. If it still fails:
```bash
cd /home/gadol/projects/immich
docker start immich_server
# or
docker compose up -d
```

## 🔐 Security Considerations

1. **Backup Directory Permissions**: Ensure only authorized users can access backups (they contain sensitive data)
   ```bash
   chmod 700 /mnt/data/immich/backup
   ```

2. **Environment File**: The `.env` backup contains passwords
   ```bash
   chmod 600 /mnt/data/immich/backup/env_backup
   ```

3. **Off-Site Backups**: Consider copying backups to another location:
   ```bash
   rsync -avh /mnt/data/immich/backup/ user@remote:/path/to/offsite/backup/
   ```

## 📈 Best Practices

1. **Test Restores Regularly**: Verify backups work before you need them
2. **Monitor Disk Space**: Set up alerts for low disk space
3. **Off-Site Copies**: Keep backups in multiple locations
4. **Schedule During Low Usage**: Run backups during off-peak hours
5. **Review Logs**: Periodically check `backup.log` for issues

## 🆘 Emergency Recovery

If your Immich installation is completely broken:

1. **Fresh Install**:
   ```bash
   cd /home/gadol/projects/immich
   docker compose down -v
   ```

2. **Restore Configuration**:
   ```bash
   cp /mnt/data/immich/backup/env_backup .env
   cp /mnt/data/immich/backup/docker-compose_backup.yml docker-compose.yml
   ```

3. **Start Database**:
   ```bash
   docker compose up -d database
   sleep 10
   ```

4. **Restore Database**:
   ```bash
   LATEST_BACKUP=$(ls -t /mnt/data/immich/backup/immich_db_backup_*.sql.gz | head -1)
   gunzip -c "$LATEST_BACKUP" | docker exec -i immich_postgres psql -U postgres -d immich
   ```

5. **Restore Library**:
   ```bash
   rsync -avh /mnt/data/immich/backup/library/ /mnt/data/immich/library/
   ```

6. **Start All Services**:
   ```bash
   docker compose up -d
   ```

## 📞 Support

For backup-related issues:
- Check the log: `/mnt/data/immich/backup/backup.log`
- Verify disk space: `df -h /mnt/data/immich/backup`
- Test database connection: `docker exec immich_postgres psql -U postgres -d immich -c "SELECT 1"`

For Immich-specific issues, see the main [README](../README.md#-support).

---

**Regular backups save lives! 💾**
