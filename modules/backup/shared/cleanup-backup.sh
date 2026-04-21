#!/bin/bash
# =============================================================================
# CLEANUP-BACKUP.SH - Backup module shared cleanup
# =============================================================================
# Runs when the backup/core submodule is uninstalled. Removes the backup
# shared library directory.
#
# Module: backup (shared)
# Requires: core.sh
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Backup shared cleanup failed at line $LINENO" >&2; exit 1' ERR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

readonly BACKUP_LIB_DIR="/usr/local/lib/backup-scripts"

if [[ -d "$BACKUP_LIB_DIR" ]]; then
    info "Removing $BACKUP_LIB_DIR..."
    rm -rf "$BACKUP_LIB_DIR"
    success "Removed backup library directory"
fi
