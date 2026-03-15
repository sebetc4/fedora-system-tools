#!/bin/bash
# =============================================================================
# NOTIFICATIONS UNINSTALL - Notification daemon removal
# =============================================================================
# Removes the notification daemon: stops user service, deletes scripts and
# systemd unit. Config files in ~/.config/notify-daemon/ are NOT removed.
#
# Module: notifications
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   ./modules/notifications/uninstall.sh
#
# Note: Do NOT run as root (manages user service)
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

readonly MODULE_NAME="notifications"

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

# ===================
# Safety check
# ===================
if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root" "exit"
fi

# ===================
# Check module is installed
# ===================
if ! registry_is_installed "$MODULE_NAME"; then
    warn "$MODULE_NAME is not registered in the registry"
fi

info "Uninstalling $MODULE_NAME..."

# ===================
# Stop & disable user service
# ===================
info "Stopping notify-daemon..."
systemctl --user disable --now notify-daemon.service 2>/dev/null || true
systemctl --user daemon-reload

# ===================
# Remove installed files
# ===================
info "Removing scripts..."
sudo rm -f /usr/local/bin/notify-daemon
sudo rm -f /usr/local/bin/notify-manage

info "Removing user service..."
rm -f ~/.config/systemd/user/notify-daemon.service
systemctl --user daemon-reload

info "Removing logrotate config..."
CURRENT_USER="$(whoami)"
sudo rm -f "/etc/logrotate.d/${CURRENT_USER}-notifications"

# ===================
# Unregister & done
# ===================
registry_remove "$MODULE_NAME"

info "Removing log directory..."
rm -rf "$HOME/.local/log/notifications"

ui_banner "$MODULE_NAME uninstalled" \
    "" \
    "Config files in ~/.config/notify-daemon/ were NOT removed."

ui_press_enter
