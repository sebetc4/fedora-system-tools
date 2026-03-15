#!/bin/bash
# =============================================================================
# TORRENT UNINSTALL - Torrent module removal
# =============================================================================
# Removes the torrent module binaries from /usr/local/bin.
# Does NOT remove containers, Podman secrets, or downloaded data.
#
# Module: torrent
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/torrent/uninstall.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

readonly MODULE_NAME="torrent"

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
# Remove binaries
# ===================
for bin in torrent torrent-list torrent-move torrent-container; do
    if [[ -f "/usr/local/bin/$bin" ]]; then
        rm -f "/usr/local/bin/$bin"
        success "Removed /usr/local/bin/$bin"
    fi
done

# ===================
# Unregister & done
# ===================
registry_remove "$MODULE_NAME"

ui_banner "$MODULE_NAME uninstalled" \
    "" \
    "Containers and data were NOT removed." \
    "" \
    "To clean up manually:" \
    "  podman rm -f gluetun qbittorrent" \
    "  podman secret rm torrent-openvpn-user torrent-openvpn-password torrent-wireguard-key" \
    "  rm -rf ~/.config/torrent"

ui_press_enter
