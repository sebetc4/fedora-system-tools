#!/bin/bash
# =============================================================================
# NOTIFICATIONS INSTALL - Desktop notification daemon installation
# =============================================================================
# Installs the notification system:
#   - Notification dependencies (jq, libnotify)
#   - notify-daemon and notify-manage scripts
#   - systemd user service
#
# Module: notifications
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   ./modules/notifications/install.sh
#
# Note: Do NOT run as root (installs user service)
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MODULE_YML="$SCRIPT_DIR/module.yml"
readonly MODULE_NAME="notifications"
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    MODULE_VERSION="$(yq -r '.version' "$MODULE_YML")"
else
    MODULE_VERSION="0.1.0"
fi
readonly MODULE_VERSION

# ===================
# Check lib is installed
# ===================
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

# ===================
# Safety checks
# ===================
if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root" "exit"
fi

if ! systemctl --user list-units &>/dev/null; then
    error "systemd user instance not available (no graphical/login session?)" "exit"
fi

# ===================
# Notification dependencies
# ===================
info "Checking notification dependencies..."
bash "$SCRIPT_DIR/scripts/check-notify-dependencies.sh"

# ===================
# Install binaries
# ===================
info "Installing notification scripts..."
sudo install -m 755 "$SCRIPT_DIR/scripts/notify-daemon.sh" /usr/local/bin/notify-daemon
sudo install -m 755 "$SCRIPT_DIR/scripts/notify-manage.sh" /usr/local/bin/notify-manage

# ===================
# Log directory & logrotate
# ===================
info "Configuring log rotation..."
mkdir -p "$HOME/.local/log/notifications"
CURRENT_USER="$(whoami)"
LOGROTATE_FILE="/etc/logrotate.d/${CURRENT_USER}-notifications"
sed -e "s|__HOME__|$HOME|g" \
    -e "s|__USER__|$CURRENT_USER|g" \
    "$SCRIPT_DIR/logrotate/user-logs.tpl" \
    | sudo tee "$LOGROTATE_FILE" > /dev/null

# ===================
# systemd user service
# ===================
info "Installing systemd user service..."
mkdir -p ~/.config/systemd/user
install -m 644 "$SCRIPT_DIR/services/notify-daemon.service" \
    ~/.config/systemd/user/notify-daemon.service

systemctl --user daemon-reload
systemctl --user enable --now notify-daemon.service

# ===================
# Status
# ===================
systemctl --user --no-pager status notify-daemon.service || true

registry_set "$MODULE_NAME" "$MODULE_VERSION"

ui_banner "$MODULE_NAME v$MODULE_VERSION installed" \
    "" \
    "Usage:" \
    "  notify-manage list        List monitored services" \
    "  notify-manage add <svc>   Add a service to monitor" \
    "  notify-manage test <svc>  Send a test notification"

ui_press_enter
