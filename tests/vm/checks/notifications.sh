#!/bin/bash
# =============================================================================
# NOTIFICATIONS - VM checks for the notifications module
# =============================================================================
# Sourced by guest-checks.sh inside a test VM, after each install.
#
# Module: tests
# Requires: none
# Version: 0.1.0
# =============================================================================

# What the uninstall keeps: the user's daemon config, as its uninstaller says
# shellcheck disable=SC2034  # read by guest-checks.sh
KEEP=("$HOME/.config/notify-daemon")

check_binaries_installed() {
    local bin
    for bin in notify-daemon notify-manage; do
        [[ -x "/usr/local/bin/$bin" ]] || fail "/usr/local/bin/$bin is missing or not executable"
    done
}

check_daemon_enabled() {
    systemctl --user is-enabled --quiet notify-daemon.service \
        || fail "notify-daemon.service is not enabled"
}

check_daemon_active() {
    systemctl --user is-active --quiet notify-daemon.service \
        || fail "notify-daemon.service is not active"
}

check_logrotate_config() {
    local conf="/etc/logrotate.d/${USER}-notifications"
    [[ -f "$conf" ]] || fail "$conf is missing"
    sudo logrotate --debug "$conf" >/dev/null 2>&1 || fail "logrotate rejects $conf"
}

check_manage_list() {
    notify-manage list >/dev/null || fail "notify-manage list failed"
}

check_registered() {
    grep -qx '\[notifications\]' "$HOME/.config/system-scripts/registry" \
        || fail "notifications is not in the user registry"
}
