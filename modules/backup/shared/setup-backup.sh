#!/bin/bash
# =============================================================================
# SETUP-BACKUP.SH - Backup module shared setup
# =============================================================================
# Runs when the backup/core submodule is installed. Installs the backup-lib.sh
# shared library to /usr/local/lib/backup-scripts/ so all backup submodules
# (system, hdd, hdd-both, bitwarden, hooks) can source it uniformly.
#
# Module: backup (shared)
# Requires: core.sh
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Backup shared setup failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

readonly BACKUP_LIB_DIR="/usr/local/lib/backup-scripts"

info "Installing backup library to $BACKUP_LIB_DIR..."

install -d -m 755 "$BACKUP_LIB_DIR"
install -m 644 "$SCRIPT_DIR/backup-lib.sh" "$BACKUP_LIB_DIR/backup-lib.sh"

success "Installed: $BACKUP_LIB_DIR/backup-lib.sh"
