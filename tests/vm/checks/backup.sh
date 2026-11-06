#!/bin/bash
# =============================================================================
# BACKUP - VM checks for the backup module
# =============================================================================
# Sourced by guest-checks.sh inside a test VM, after each install of every
# backup submodule. Checks that each file module.yml declares is in place,
# with the owner its type gives it, and that nothing in the user's home
# belongs to root.
#
# Module: tests
# Requires: none
# Version: 0.1.0
# =============================================================================

# What the uninstall keeps: the user's config files, as the engine says
# shellcheck disable=SC2034  # read by guest-checks.sh
KEEP=("$HOME/.config/backup")

# owned_by <user> <path>: fail unless <path> exists and belongs to <user>
owned_by() {
    local owner
    owner=$(stat -c %U "$2" 2>/dev/null) || fail "$2 is missing"
    [[ "$owner" == "$1" ]] || fail "$2 belongs to $owner, not $1"
}

check_system_binaries() {
    local bin
    for bin in backup-local backup-hdd backup-hdd-both backup-bitwarden; do
        [[ -x "/usr/local/bin/$bin" ]] || fail "/usr/local/bin/$bin is missing or not executable"
        owned_by root "/usr/local/bin/$bin"
    done
}

check_user_binary() {
    [[ -x "$HOME/.local/bin/backup-vps" ]] || fail "$HOME/.local/bin/backup-vps is missing or not executable"
    owned_by "$USER" "$HOME/.local/bin/backup-vps"
    owned_by "$USER" "$HOME/.local/bin"
}

check_core_files() {
    [[ -f /usr/local/lib/backup-scripts/backup-lib.sh ]] || fail "backup-lib.sh is missing"
    [[ -d /var/log/backup ]] || fail "/var/log/backup is missing"
}

check_log_dirs_owned() {
    owned_by "$USER" "$HOME/.local/log/backup-vps"
    owned_by "$USER" "$HOME/.local/log"
}

check_logrotate_configs() {
    local conf
    for conf in /etc/logrotate.d/backup-scripts "/etc/logrotate.d/${USER}-backup-bitwarden" \
        "/etc/logrotate.d/${USER}-backup-vps"; do
        [[ -f "$conf" ]] || fail "$conf is missing"
        sudo logrotate --debug "$conf" >/dev/null 2>&1 || fail "logrotate rejects $conf"
    done
}

check_configs_owned() {
    local name
    for name in local hdd hdd-both bitwarden vps hooks/btrfs-save-structure; do
        owned_by "$USER" "$HOME/.config/backup/$name.yml"
    done
    owned_by "$USER" "$HOME/.config/backup/hooks"
}

check_hook_script() {
    [[ -x /usr/local/lib/system-scripts/hooks.d/pre-backup/btrfs-save-structure.sh ]] \
        || fail "the btrfs-save-structure hook is missing or not executable"
}

check_vps_timer() {
    systemctl --user is-enabled --quiet backup-vps.timer || fail "backup-vps.timer is not enabled"
    systemctl --user is-active --quiet backup-vps.timer || fail "backup-vps.timer is not active"
    owned_by "$USER" "$HOME/.config/systemd/user/backup-vps.service"
    owned_by "$USER" "$HOME/.config/systemd/user/backup-vps.timer"
}

check_notification_tags() {
    local tag
    for tag in notify-backup-local notify-backup-hdd notify-backup-hdd-both notify-backup-vps; do
        grep -qx "$tag" "$HOME/.config/notify-daemon/services.conf" 2>/dev/null \
            || fail "$tag is not registered"
    done
    owned_by "$USER" "$HOME/.config/notify-daemon/services.conf"
}

check_registries() {
    local sub
    for sub in core local hdd hdd-both bitwarden; do
        grep -qx "\[backup/$sub\]" /etc/system-scripts/registry || fail "backup/$sub is not in the system registry"
    done
    grep -qx '\[backup/vps\]' "$HOME/.config/system-scripts/registry" || fail "backup/vps is not in the user registry"
    owned_by "$USER" "$HOME/.config/system-scripts/registry"
}

check_nothing_of_root_in_home() {
    local found
    found=$(find "$HOME" -xdev -user root -print -quit 2>/dev/null)
    [[ -z "$found" ]] || fail "$found belongs to root"
}
