#!/bin/bash
# =============================================================================
# CLEANUP-VPS - VPS backup cleanup hook
# =============================================================================
# Runs when the vps submodule is uninstalled. Handles cleanup that the
# submodule engine cannot:
#   - Logrotate config removal (user-prefixed filename)
#   - Log directory removal
#
# Module: backup (vps uninstall hook)
# Requires: core
# Version: 0.1.0
# =============================================================================

set -euo pipefail

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# Resolve real user (running under sudo)
readonly REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
readonly REAL_HOME

# ===================
# Remove logrotate config
# ===================
info "Removing logrotate config..."
rm -f "/etc/logrotate.d/${REAL_USER}-backup-vps"

# ===================
# Remove log directory
# ===================
info "Removing log directory..."
rm -rf "$REAL_HOME/.local/log/backup-vps"

success "VPS backup cleanup complete"
