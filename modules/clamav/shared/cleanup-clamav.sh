#!/bin/bash
# =============================================================================
# CLEANUP-CLAMAV.SH - ClamAV shared cleanup (services, config, SELinux)
# =============================================================================
# Runs when the core submodule is uninstalled (all other submodules already
# removed due to deps: protection). Stops ClamAV shared services, restores
# configs, and resets SELinux booleans.
#
# Module: clamav (core uninstall hook)
# Requires: none (standalone, called by submodule_uninstall)
# Version: 0.1.0
# =============================================================================

set -euo pipefail

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# ===================
# Stop shared ClamAV services
# ===================
info "Stopping ClamAV shared services..."
systemctl stop clamd@scan 2>/dev/null || true
systemctl disable clamd@scan 2>/dev/null || true
systemctl stop clamav-freshclam 2>/dev/null || true
systemctl disable clamav-freshclam 2>/dev/null || true

# ===================
# Remove management tool + quarantine state library
# ===================
rm -f /usr/local/bin/clamav-manage
rm -f "$LIB_DIR/quarantine-state.sh"

if [[ -f /etc/system-scripts/quarantine.state ]]; then
    info "State preserved: /etc/system-scripts/quarantine.state"
    info "Remove manually if no longer needed: sudo rm /etc/system-scripts/quarantine.state"
fi

# ===================
# Clean shared config
# ===================
if [[ -f /etc/system-scripts/clamav.conf ]]; then
    info "Config preserved: /etc/system-scripts/clamav.conf"
    info "Remove manually if no longer needed: sudo rm /etc/system-scripts/clamav.conf"
fi

# ===================
# Restore scan.conf
# ===================
if ls /etc/clamd.d/scan.conf.backup-* &>/dev/null; then
    LATEST_BACKUP=$(find /etc/clamd.d -maxdepth 1 -name 'scan.conf.backup-*' -printf '%T@\t%p\n' | sort -rn | head -1 | cut -f2)
    cp "$LATEST_BACKUP" /etc/clamd.d/scan.conf
    rm -f /etc/clamd.d/scan.conf.backup-*
    info "Restored scan.conf from backup"
fi

# ===================
# Reset SELinux
# ===================
if command -v setsebool &>/dev/null; then
    setsebool -P antivirus_can_scan_system off 2>/dev/null || true
fi

success "ClamAV shared cleanup complete"
