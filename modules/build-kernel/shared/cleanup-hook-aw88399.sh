#!/bin/bash
# =============================================================================
# CLEANUP-HOOK-AW88399.SH - hook-aw88399 submodule uninstall hook
# =============================================================================
# Removes the AW88399 hook and its internal libs from the module's share
# directory. User hook config (~/.config/build-kernel/hooks/aw88399.conf)
# is preserved.
#
# Module: build-kernel (submodule: hook-aw88399)
# Requires: core, log
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: cleanup-hook-aw88399 failed at line $LINENO" >&2; exit 1' ERR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"

info "Removing AW88399 hook..."
rm -rf /usr/local/share/build-kernel/hooks/aw88399
success "AW88399 hook removed"
