#!/bin/bash
# =============================================================================
# FS.SH - Filesystem helpers
# =============================================================================
# Generic filesystem utilities: mount checks, BTRFS detection, disk usage,
# and sudo-aware user/home resolution.
#
# Requires: core.sh, log.sh
#
# Usage:
#   source "$LIB_DIR/fs.sh"
#   detect_real_user
#   is_mounted "/mnt/hdd1" || error "HDD not mounted" "exit"
#   is_btrfs "/mnt/backup" && echo "BTRFS"
# =============================================================================

[[ -n "${_LIB_FS_LOADED:-}" ]] && return 0
readonly _LIB_FS_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# =============================================================================
# User/Home detection (sudo-aware)
# =============================================================================

# Sets REAL_USER and REAL_HOME, resolving through sudo if present.
# shellcheck disable=SC2034  # REAL_USER/REAL_HOME are used by callers
detect_real_user() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        REAL_USER="$SUDO_USER"
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6) || true
        [[ -n "$REAL_HOME" ]] || error "No home found for user '$SUDO_USER'" "exit"
    else
        REAL_USER="$USER"
        REAL_HOME="$HOME"
    fi
}

# =============================================================================
# Filesystem helpers
# =============================================================================

# Check if a path resides on a BTRFS filesystem.
is_btrfs() {
    local path="$1"
    [[ "$(df -T "$path" 2>/dev/null | tail -1 | awk '{print $2}')" == "btrfs" ]]
}

# Check if a path is a mount point.
is_mounted() {
    local path="$1"
    mountpoint -q "$path" 2>/dev/null
}

# Print human-readable disk usage: "Used: 1.2T / 2.0T (60%)"
get_disk_usage() {
    local path="$1"
    df -h "$path" | tail -1 | awk '{print "Used: "$3" / "$2" ("$5")"}'
}

# Compare source usage vs destination available space, warn if >90% full.
# Requires: log_step, log_warn, log_success from log.sh
check_disk_space() {
    local source="$1"
    local dest="$2"

    log_step "Checking disk space..."

    local source_used dest_avail dest_total
    source_used=$(df -k "$source" | tail -1 | awk '{print $3}')
    dest_avail=$(df -k "$dest" | tail -1 | awk '{print $4}')
    dest_total=$(df -k "$dest" | tail -1 | awk '{print $2}')

    echo "  Source used:       $(numfmt --to=iec-i --suffix=B $((source_used * 1024)) 2>/dev/null || echo "${source_used}K")"
    echo "  Destination free:  $(numfmt --to=iec-i --suffix=B $((dest_avail * 1024)) 2>/dev/null || echo "${dest_avail}K")"
    echo "  Destination total: $(numfmt --to=iec-i --suffix=B $((dest_total * 1024)) 2>/dev/null || echo "${dest_total}K")"

    local after_backup=$((dest_total - source_used))
    if [[ $after_backup -lt $((dest_total / 10)) ]]; then
        log_warn "Destination will be more than 90% full after backup"
    else
        log_success "Sufficient space available"
    fi
}
