#!/bin/bash

#############################################################
# Immich Backup Setup Helper for Ubuntu
# 
# Installs required packages and helps configure SMB backups
#############################################################

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════╗"
echo "║    Immich Backup Setup Helper for Ubuntu          ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    echo "This script is designed for Ubuntu/Debian Linux."
    echo "You appear to be running: $OSTYPE"
    echo ""
    echo "For macOS, SMB mounting works differently. Please configure manually."
    exit 1
fi

# Check for root/sudo
if [[ $EUID -eq 0 ]]; then
   echo "Please run this script as a normal user (with sudo available)"
   echo "Do not run as root"
   exit 1
fi

log_section "Checking System"
log_info "OS: $(lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown")"
log_info "User: $USER"

# Check and install required packages
log_section "Installing Required Packages"

PACKAGES="cifs-utils rsync docker.io docker-compose"
TO_INSTALL=""

for pkg in $PACKAGES; do
    if dpkg -l | grep -q "^ii  $pkg"; then
        log_info "$pkg is already installed"
    else
        TO_INSTALL="$TO_INSTALL $pkg"
    fi
done

if [[ -n "$TO_INSTALL" ]]; then
    log_info "The following packages will be installed:$TO_INSTALL"
    echo ""
    read -p "Continue? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo apt-get update
        sudo apt-get install -y $TO_INSTALL
        log_info "Packages installed successfully"
    else
        echo "Installation cancelled"
        exit 0
    fi
else
    log_info "All required packages are already installed"
fi

# Configure sudo for mount/umount
log_section "Configuring Sudo Permissions"

SUDOERS_LINE="$USER ALL=(ALL) NOPASSWD: /bin/mount, /bin/umount, /bin/mkdir"

if sudo grep -q "$USER.*NOPASSWD.*mount" /etc/sudoers 2>/dev/null; then
    log_info "Sudo permissions already configured"
else
    echo ""
    echo "To allow automatic SMB mounting, we need to add sudo permissions."
    echo "This will add the following line to /etc/sudoers:"
    echo "  $SUDOERS_LINE"
    echo ""
    read -p "Add sudo permissions? (y/n): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "$SUDOERS_LINE" | sudo EDITOR='tee -a' visudo -f /etc/sudoers.d/immich-backup
        sudo chmod 0440 /etc/sudoers.d/immich-backup
        log_info "Sudo permissions configured"
    else
        log_info "Skipped - you'll need to enter sudo password during backups"
    fi
fi

# Create SMB credentials file
log_section "SMB Credentials Configuration"

echo ""
echo "Would you like to create a secure credentials file for SMB?"
echo "This is more secure than storing passwords in the config file."
read -p "Create credentials file? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "SMB Username: " smb_user
    read -s -p "SMB Password: " smb_pass
    echo
    read -p "SMB Domain (leave empty if none): " smb_domain
    
    CRED_FILE="/etc/immich-backup-credentials"
    
    sudo bash -c "cat > $CRED_FILE" <<EOF
username=$smb_user
password=$smb_pass
EOF
    
    if [[ -n "$smb_domain" ]]; then
        echo "domain=$smb_domain" | sudo tee -a $CRED_FILE > /dev/null
    fi
    
    sudo chmod 600 $CRED_FILE
    sudo chown root:root $CRED_FILE
    
    log_info "Credentials file created at: $CRED_FILE"
    echo ""
    echo "Use this in your backup-config.sh:"
    echo '  SMB_MOUNT_OPTIONS="credentials=/etc/immich-backup-credentials,vers=3.0,uid=$(id -u),gid=$(id -g)"'
    echo "  SMB_USERNAME=\"\""
    echo "  SMB_PASSWORD=\"\""
fi

# Test SMB mount
log_section "SMB Mount Test"

echo ""
read -p "Would you like to test SMB mounting? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "SMB Share (e.g., //192.168.1.100/backups): " smb_share
    read -p "Mount point (e.g., /mnt/test-backup): " mount_point
    
    sudo mkdir -p "$mount_point"
    
    if [[ -f "/etc/immich-backup-credentials" ]]; then
        log_info "Using credentials file..."
        sudo mount -t cifs "$smb_share" "$mount_point" -o "credentials=/etc/immich-backup-credentials,vers=3.0,uid=$(id -u),gid=$(id -g)"
    else
        sudo mount -t cifs "$smb_share" "$mount_point"
    fi
    
    if mountpoint -q "$mount_point"; then
        log_info "✓ SMB share mounted successfully!"
        log_info "Mount point: $mount_point"
        echo ""
        echo "Contents:"
        ls -lh "$mount_point" || echo "(empty or no permission)"
        echo ""
        read -p "Unmount now? (y/n): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo umount "$mount_point"
            log_info "Unmounted"
        fi
    fi
fi

# Create sample config
log_section "Configuration File Setup"

echo ""
echo "A sample configuration file 'backup-config.sh' will help you get started."
read -p "Create backup-config.sh from template? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [[ -f "backup-config.sh" ]]; then
        echo "backup-config.sh already exists!"
        read -p "Overwrite? (y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Yy]$ ]] && log_info "Skipped" && exit 0
    fi
    
    read -p "Immich directory path: " immich_dir
    read -p "Backup type (local/smb): " backup_type
    
    if [[ "$backup_type" == "smb" ]]; then
        cp backup-config-smb.sh backup-config.sh
        log_info "Created backup-config.sh from SMB template"
        echo ""
        echo "Next steps:"
        echo "1. Edit backup-config.sh and set your SMB share details"
        echo "2. If you created credentials file, update SMB_MOUNT_OPTIONS"
        echo "3. Run: ./backup-immich.sh"
    else
        cp backup-config-local.sh backup-config.sh
        read -p "Backup destination path: " backup_dest
        sed -i "s|IMMICH_DIR=.*|IMMICH_DIR=\"$immich_dir\"|" backup-config.sh
        sed -i "s|BACKUP_DESTINATION=.*|BACKUP_DESTINATION=\"$backup_dest\"|" backup-config.sh
        log_info "Created backup-config.sh for local backups"
        echo ""
        echo "Next steps:"
        echo "1. Review backup-config.sh"
        echo "2. Run: ./backup-immich.sh"
    fi
fi

log_section "Setup Complete!"
echo ""
echo "All done! You're ready to backup Immich."
echo ""
echo "Quick reference:"
echo "  - Run backup: ./backup-immich.sh"
echo "  - Verify backup: ./verify-backup.sh /path/to/backup"
echo "  - Restore backup: ./restore-immich.sh /path/to/backup"
echo "  - Documentation: README-BACKUP.md"
echo ""
