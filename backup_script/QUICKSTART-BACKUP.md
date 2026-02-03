# Immich Backup Scripts - Quick Start

## 📦 What You Got

A complete backup and restore solution for your Immich installation with 8 files:

### Core Scripts (executable)
- **backup-immich.sh** - Main backup script (pg_dump + rsync)
- **restore-immich.sh** - Restore from backup
- **verify-backup.sh** - Check backup integrity
- **setup-ubuntu.sh** - Ubuntu setup helper for SMB

### Configuration Files
- **backup-config.example.sh** - Template with all options
- **backup-config-local.sh** - Quick config for local storage
- **backup-config-smb.sh** - Quick config for SMB shares

### Documentation
- **README-BACKUP.md** - Full documentation

## 🚀 Quick Start (3 Steps)

### Step 1: Choose Your Config

**For Local Backups (easiest):**
```bash
cp backup-config-local.sh backup-config.sh
nano backup-config.sh
```

Edit these two lines:
```bash
IMMICH_DIR="/Users/gadol/dev/immich"      # ← Your Immich path
BACKUP_DESTINATION="/path/to/backups"     # ← Where to save backups
```

**For SMB Share (Ubuntu):**
```bash
cp backup-config-smb.sh backup-config.sh
nano backup-config.sh
```

Edit these lines:
```bash
IMMICH_DIR="/Users/gadol/dev/immich"
SMB_SHARE="//192.168.1.100/backups"       # ← Your SMB server
SMB_USERNAME="your_username"              # ← Your credentials
SMB_PASSWORD="your_password"
```

### Step 2: Run Your First Backup

```bash
./backup-immich.sh
```

That's it! The script will:
- ✅ Backup database using pg_dump (compressed)
- ✅ Backup all files using rsync
- ✅ Save to timestamped folder
- ✅ Clean up old backups

### Step 3: Verify It Worked

```bash
./verify-backup.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS
```

## 📋 What Gets Backed Up

```
immich_backup_20260202_143000/
├── database_20260202_143000.sql.gz  ← PostgreSQL dump (compressed)
├── backup_info.txt                   ← Backup metadata
└── files/
    ├── config/
    │   ├── docker-compose.yml
    │   └── .env
    └── library/                      ← All your photos/videos
```

## 🔄 Restoring

```bash
./restore-immich.sh /path/to/backup/immich_backup_20260202_143000
```

⚠️ **Warning:** This will overwrite your current Immich installation!

## ⏰ Automate It (Cron)

Daily backups at 2 AM:
```bash
crontab -e
```

Add:
```cron
0 2 * * * /Users/gadol/dev/immich/backup-immich.sh >> /var/log/immich-backup.log 2>&1
```

## 🐧 Ubuntu SMB Setup

If you're on Ubuntu and want to backup to a network share:

```bash
./setup-ubuntu.sh
```

This interactive script will:
- Install required packages (cifs-utils, rsync)
- Configure sudo permissions
- Create secure credentials file
- Test SMB mounting
- Create your config file

## 📝 Common Configurations

### Backup to External Drive (macOS)
```bash
BACKUP_DESTINATION="/Volumes/External/Immich-Backups"
```

### Backup to NAS (Ubuntu)
```bash
BACKUP_TYPE="smb"
SMB_SHARE="//192.168.1.100/backups"
SMB_MOUNT_POINT="/mnt/nas-backup"
```

### Keep Backups for 30 Days
```bash
BACKUP_RETENTION_DAYS=30
```

### Exclude Certain Files
```bash
RSYNC_EXCLUDE="*.tmp *.log cache/*"
```

## 🔍 Troubleshooting

### "Database container not running"
```bash
docker ps | grep postgres
# Make sure Immich is running
```

### "Failed to mount SMB share"
```bash
# Test manually:
sudo mount -t cifs //server/share /mnt/test -o username=user,password=pass

# Check network:
ping server_ip
```

### "Permission denied"
```bash
# Check write permissions:
ls -ld /path/to/backup

# For SMB, check uid/gid:
id  # Note your uid/gid numbers
# Add to config: SMB_MOUNT_OPTIONS="uid=1000,gid=1000,vers=3.0"
```

## 📚 Learn More

See [README-BACKUP.md](README-BACKUP.md) for:
- Detailed configuration options
- Security best practices
- Complete troubleshooting guide
- Testing procedures
- Monitoring tips

## 🎯 Key Features

✅ Uses pg_dump for clean database backups  
✅ Uses rsync for efficient file backups  
✅ Supports local and network storage  
✅ Automatic cleanup of old backups  
✅ Color-coded output  
✅ Comprehensive error handling  
✅ Backup verification tool  
✅ Interactive restore process  

## 💡 Pro Tips

1. **Test your backups regularly**
   ```bash
   ./verify-backup.sh /path/to/latest/backup
   ```

2. **Always backup before upgrading Immich**
   ```bash
   ./backup-immich.sh
   ```

3. **Use credentials file for SMB** (more secure than password in config)

4. **Monitor backup logs** when using cron
   ```bash
   tail -f /var/log/immich-backup.log
   ```

5. **Keep at least 7 days of backups** in case you don't notice a problem immediately

## 🆘 Need Help?

1. Check [README-BACKUP.md](README-BACKUP.md) - Full documentation
2. Run verify script to diagnose backup issues
3. Check script output for detailed error messages
4. Test individual components (docker, rsync, mount) separately

---

**Ready to backup?**
```bash
./backup-immich.sh
```

**Questions?** Read [README-BACKUP.md](README-BACKUP.md) for complete documentation.
