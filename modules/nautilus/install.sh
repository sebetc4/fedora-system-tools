#!/bin/bash
# =============================================================================
# NAUTILUS INSTALL - Nautilus integration module installation
# =============================================================================
# Installs the Nautilus bookmark manager:
#   - bookmark-manager CLI (bookmarks + symlinks)
#   - Optional bash completion
#
# Module: nautilus
# Requires: core (checks lib is installed)
# Version: 0.1.0
#
# Usage:
#   ./modules/nautilus/install.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MODULE_YML="$SCRIPT_DIR/module.yml"
readonly MODULE_NAME="nautilus"
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    MODULE_VERSION="$(yq -r '.version' "$MODULE_YML")"
else
    MODULE_VERSION="0.1.0"
fi
readonly MODULE_VERSION

# Check lib is installed
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: system-scripts library not found in $LIB_DIR"
    echo "Install it first: make install-lib"
    exit 1
fi
source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/ui.sh"

# Check minimum lib version
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    _min_lib=$(yq -r '.min_lib_version // ""' "$MODULE_YML")
    if [[ -n "$_min_lib" ]]; then
        _lib_cmp=$(version_compare "$LIB_VERSION" "$_min_lib" 2>/dev/null || echo "ok")
        if [[ "$_lib_cmp" == "lt" ]]; then
            echo "ERROR: Module $MODULE_NAME requires lib >= $_min_lib (installed: $LIB_VERSION). Run: make install-lib" >&2
            exit 1
        fi
    fi
fi

check_root

# ===================
# Install scripts
# ===================
info "Installing $MODULE_NAME v$MODULE_VERSION..."

install -m 755 "$SCRIPT_DIR/scripts/bookmark-manager.sh" /usr/local/bin/bookmark-manager

success "Scripts installed"

# ===================
# Initialize
# ===================
CURRENT_USER="${SUDO_USER:-$USER}"
info "Initializing bookmark-manager for $CURRENT_USER..."
sudo -u "$CURRENT_USER" HOME="$(getent passwd "$CURRENT_USER" | cut -d: -f6)" \
    /usr/local/bin/bookmark-manager init
success "bookmark-manager initialized"

# ===================
# Summary
# ===================
registry_set "$MODULE_NAME" "$MODULE_VERSION"

ui_banner "$MODULE_NAME v$MODULE_VERSION installed" \
    "" \
    "Usage:" \
    "  bookmark-manager              Interactive menu" \
    "  bookmark-manager init         Create ~/Bookmarks directory" \
    "  bookmark-manager add          Bookmark current directory" \
    "  bookmark-manager add -s       Bookmark + symlink" \
    "  bookmark-manager list         List all bookmarks & symlinks" \
    "  bookmark-manager help         Show all commands" \
    "" \
    "Optional:" \
    "  bookmark-manager install-completion   Bash tab completion"

ui_press_enter
