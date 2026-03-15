#!/bin/bash
# =============================================================================
# <MODULE> UNINSTALL - <Module name> removal
# =============================================================================
# Removes the <module> module: stops services, deletes scripts and configs.
#
# Example: modules/torrent/uninstall.sh, modules/nautilus/uninstall.sh
#
# Module: <module-name>
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/<module>/uninstall.sh
# =============================================================================

set -euo pipefail

readonly MODULE_NAME="<module>"

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

check_root

# ===================
# Check module is installed
# ===================
if ! registry_is_installed "$MODULE_NAME"; then
    warn "$MODULE_NAME is not registered in the registry"
fi

info "Uninstalling $MODULE_NAME..."

# ===================
# Stop & disable services (if any)
# ===================
# systemctl disable --now example.timer 2>/dev/null || true
# systemctl disable --now example.service 2>/dev/null || true
# systemctl daemon-reload

# ===================
# Remove installed files
# ===================
# for bin in example-cmd1 example-cmd2; do
#     if [[ -f "/usr/local/bin/$bin" ]]; then
#         rm -f "/usr/local/bin/$bin"
#         success "Removed /usr/local/bin/$bin"
#     fi
# done

# rm -f /etc/systemd/system/example.service
# rm -f /etc/systemd/system/example.timer

# ===================
# Unregister & done
# ===================
registry_remove "$MODULE_NAME"

echo ""
success "$MODULE_NAME uninstalled"
echo ""
# warn "Config and data were NOT removed."
# echo "  To remove config: rm -rf ~/.config/<module>"
# echo ""
