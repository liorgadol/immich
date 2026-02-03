#!/bin/bash

#############################################################
# Immich Backup Verification Script
# 
# Checks backup integrity and provides a report
#
# Usage:
#   ./verify-backup.sh /path/to/backup/immich_backup_YYYYMMDD_HHMMSS
#############################################################

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 /path/to/backup/immich_backup_YYYYMMDD_HHMMSS"
    exit 1
fi

BACKUP_DIR="$1"
ERRORS=0
WARNINGS=0

if [[ ! -d "$BACKUP_DIR" ]]; then
    log_error "Backup directory not found: $BACKUP_DIR"
    exit 1
fi

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════╗"
echo "║        Immich Backup Verification Report          ║"
echo "╚════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Backup Info
log_section "Backup Information"
echo "Location: $BACKUP_DIR"
echo "Backup Name: $(basename "$BACKUP_DIR")"

if [[ -f "${BACKUP_DIR}/backup_info.txt" ]]; then
    log_info "Backup info file found"
    echo ""
    cat "${BACKUP_DIR}/backup_info.txt" | head -n 10
else
    log_warn "Backup info file missing"
    ((WARNINGS++))
fi

# Check Database Backup
log_section "Database Backup"
DB_BACKUP=$(find "$BACKUP_DIR" -name "database_*.sql.gz" 2>/dev/null | head -n 1)

if [[ -n "$DB_BACKUP" ]]; then
    log_info "Database backup found: $(basename "$DB_BACKUP")"
    
    DB_SIZE=$(du -h "$DB_BACKUP" | cut -f1)
    echo "  Size: $DB_SIZE"
    
    # Test if it's a valid gzip file
    if gunzip -t "$DB_BACKUP" 2>/dev/null; then
        log_info "Database backup is a valid gzip file"
        
        # Check if it contains SQL
        if gunzip -c "$DB_BACKUP" 2>/dev/null | head -n 5 | grep -q "PostgreSQL"; then
            log_info "Database backup contains PostgreSQL dump"
        else
            log_warn "Database backup may not be a valid PostgreSQL dump"
            ((WARNINGS++))
        fi
    else
        log_error "Database backup is corrupted (invalid gzip)"
        ((ERRORS++))
    fi
else
    log_error "Database backup not found"
    ((ERRORS++))
fi

# Check Files Backup
log_section "Files Backup"
FILES_DIR="${BACKUP_DIR}/files"

if [[ -d "$FILES_DIR" ]]; then
    log_info "Files directory found"
    
    TOTAL_SIZE=$(du -sh "$FILES_DIR" 2>/dev/null | cut -f1)
    echo "  Total size: $TOTAL_SIZE"
    
    # Check configuration files
    echo ""
    echo "Configuration Files:"
    if [[ -f "${FILES_DIR}/config/docker-compose.yml" ]]; then
        log_info "docker-compose.yml found"
    else
        log_warn "docker-compose.yml missing"
        ((WARNINGS++))
    fi
    
    if [[ -f "${FILES_DIR}/config/.env" ]]; then
        log_info ".env file found"
    else
        log_warn ".env file missing"
        ((WARNINGS++))
    fi
    
    # Check library directory
    echo ""
    echo "Data Directories:"
    if [[ -d "${FILES_DIR}/library" ]]; then
        SIZE=$(du -sh "${FILES_DIR}/library" 2>/dev/null | cut -f1)
        FILE_COUNT=$(find "${FILES_DIR}/library" -type f 2>/dev/null | wc -l | tr -d ' ')
        log_info "library/ - $SIZE ($FILE_COUNT files)"
    else
        log_error "library/ directory missing"
        ((ERRORS++))
    fi
else
    log_error "Files directory not found"
    ((ERRORS++))
fi

# Backup Age
log_section "Backup Age"
if [[ -d "$BACKUP_DIR" ]]; then
    BACKUP_DATE=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$BACKUP_DIR" 2>/dev/null || stat -c "%y" "$BACKUP_DIR" 2>/dev/null | cut -d'.' -f1)
    echo "Created: $BACKUP_DATE"
    
    # Calculate age in days (macOS compatible)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        BACKUP_TIME=$(stat -f "%m" "$BACKUP_DIR")
    else
        BACKUP_TIME=$(stat -c "%Y" "$BACKUP_DIR")
    fi
    CURRENT_TIME=$(date +%s)
    AGE_SECONDS=$((CURRENT_TIME - BACKUP_TIME))
    AGE_DAYS=$((AGE_SECONDS / 86400))
    
    echo "Age: $AGE_DAYS days old"
    
    if [[ $AGE_DAYS -gt 30 ]]; then
        log_warn "Backup is more than 30 days old"
        ((WARNINGS++))
    elif [[ $AGE_DAYS -gt 7 ]]; then
        log_warn "Backup is more than 7 days old"
        ((WARNINGS++))
    else
        log_info "Backup age is acceptable"
    fi
fi

# Summary
log_section "Summary"
echo ""

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ Backup appears to be valid and complete${NC}"
    echo ""
    echo "This backup should be safe to use for restore."
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Backup is valid but has $WARNINGS warning(s)${NC}"
    echo ""
    echo "Review the warnings above. The backup may still be usable."
    exit 0
else
    echo -e "${RED}✗ Backup has $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "This backup may not be suitable for restore."
    echo "Consider creating a new backup."
    exit 1
fi
