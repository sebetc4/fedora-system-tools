#!/bin/bash
# =============================================================================
# NAUTILUS UNINSTALL - Nautilus integration module removal
# =============================================================================
# Removes the bookmark-manager script.
#
# Module: nautilus
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/nautilus/uninstall.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

readonly MODULE_NAME="nautilus"

# ===================
# Check lib is installed
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed." >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/ui.sh"

check_root

# ===================
# Check module is installed
# ===================
if ! registry_is_installed "$MODULE_NAME"; then
    warn "$MODULE_NAME is not registered in the registry"
fi

info "Uninstalling $MODULE_NAME..."

# ===================
# Remove installed files
# ===================
info "Removing scripts..."
rm -f /usr/local/bin/bookmark-manager

# ===================
# Unregister & done
# ===================
registry_remove "$MODULE_NAME"

# --- Show preserved user data ---
local_user="${SUDO_USER:-$USER}"
local_home="$(getent passwd "$local_user" | cut -d: -f6)"
if [[ -d "$local_home/Bookmarks" ]]; then
    ui_banner "$MODULE_NAME uninstalled" \
        "" \
        "User data was NOT removed:" \
        "  $local_home/Bookmarks/"
else
    ui_banner "$MODULE_NAME uninstalled"
fi

ui_press_enter
