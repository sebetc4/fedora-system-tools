#!/bin/bash
# =============================================================================
# BACKUP.SH - Shared backup utilities
# =============================================================================
# Reusable functions for backup scripts: filesystem checks, BTRFS operations,
# rsync helpers, and sudo-aware user detection.
#
# Requires: core.sh, log.sh
#
# Usage:
#   source "$LIB_DIR/backup.sh"
#   detect_real_user
#   is_mounted "/mnt/hdd1" || error "HDD not mounted" "exit"
#   rsync_safe -aAXHv --delete /source/ /dest/
# =============================================================================

[[ -n "${_LIB_BACKUP_LOADED:-}" ]] && return 0
readonly _LIB_BACKUP_LOADED=1

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
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
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

# =============================================================================
# BTRFS operations
# =============================================================================

# Create a read-only BTRFS snapshot.
#   btrfs_create_snapshot "/mnt/hdd1" ".snapshots" "backup"
# Creates: /mnt/hdd1/.snapshots/backup-20260211-143022
btrfs_create_snapshot() {
    local source="$1"
    local snap_dir="$2"
    local prefix="$3"

    if ! is_btrfs "$source"; then
        log_warn "Not a BTRFS filesystem, skipping snapshot: $source"
        return 0
    fi

    local snap_path="$source/$snap_dir"
    mkdir -p "$snap_path"

    local snap_name
    snap_name="${prefix}-$(date +%Y%m%d-%H%M%S)"

    log_step "Creating snapshot: $snap_name"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would create snapshot: $snap_path/$snap_name"
    else
        if btrfs subvolume snapshot -r "$source" "$snap_path/$snap_name"; then
            log_success "Snapshot created: $snap_name"
        else
            log_error "Failed to create snapshot"
            return 1
        fi
    fi
}

# Delete old snapshots beyond the retention count.
#   btrfs_rotate_snapshots "/mnt/hdd1/.snapshots" "backup" 3
btrfs_rotate_snapshots() {
    local snap_dir="$1"
    local prefix="$2"
    local keep="$3"

    [[ ! -d "$snap_dir" ]] && return 0

    local snapshots=()
    while IFS= read -r snap; do
        [[ -n "$snap" ]] && snapshots+=("$snap")
    done < <(find "$snap_dir" -maxdepth 1 -name "${prefix}-*" 2>/dev/null | sort)

    local count=${#snapshots[@]}
    local to_delete=$((count - keep))

    if [[ $to_delete -gt 0 ]]; then
        log_step "Rotating snapshots (keeping $keep, deleting $to_delete)"

        for ((i=0; i<to_delete; i++)); do
            local old_snap="${snapshots[$i]}"
            local snap_name
            snap_name=$(basename "$old_snap")

            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                echo "[DRY RUN] Would delete: $snap_name"
            else
                if btrfs subvolume delete "$old_snap" &>/dev/null; then
                    log_success "Deleted old snapshot: $snap_name"
                else
                    log_warn "Failed to delete: $snap_name"
                fi
            fi
        done
    fi
}

# Run BTRFS scrub (integrity check) on a path.
#   btrfs_run_scrub "/mnt/hdd1" "Backup HDD"
btrfs_run_scrub() {
    local path="$1"
    local label="$2"

    if ! is_btrfs "$path"; then
        log_warn "$label is not BTRFS, skipping scrub"
        return 0
    fi

    log_step "Running integrity check on $label..."
    echo "This may take a while..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would run: btrfs scrub start -B $path"
    else
        if btrfs scrub start -B "$path"; then
            log_success "Scrub completed on $label"
            btrfs scrub status "$path"
        else
            log_error "Scrub failed on $label"
            return 1
        fi
    fi
}

# Show BTRFS compression statistics using compsize.
#   btrfs_show_stats "/mnt/hdd1" "Backup HDD"
btrfs_show_stats() {
    local path="$1"
    local label="$2"

    if ! is_btrfs "$path"; then
        return 0
    fi

    echo ""
    echo "Compression stats for $label:"
    echo "─────────────────────────────"

    if command -v compsize &>/dev/null; then
        compsize "$path" 2>/dev/null || echo "Unable to get stats"
    else
        log_warn "Install 'compsize' for detailed stats: sudo dnf install compsize"
        btrfs filesystem df "$path"
    fi
}

# =============================================================================
# Rsync helpers
# =============================================================================

# Rsync wrapper that treats exit codes 23 (partial) and 24 (vanished) as non-fatal.
rsync_safe() {
    local exit_code=0
    rsync "$@" || exit_code=$?

    case $exit_code in
        0)  return 0 ;;
        24)
            log_warn "Some files vanished during transfer (rsync code 24) - normal for temp files"
            return 0
            ;;
        23)
            log_warn "Some files could not be transferred (rsync code 23) - check logs for details"
            return 0
            ;;
        *)
            log_error "rsync failed with exit code $exit_code"
            return "$exit_code"
            ;;
    esac
}

# Build rsync options array from global variables.
# Expects: RSYNC_ARCHIVE, RSYNC_DELETE, RSYNC_PROGRESS, RSYNC_COMPRESS, DRY_RUN
# Outputs space-separated options string.
build_rsync_options() {
    local opts=()

    [[ "${RSYNC_ARCHIVE:-true}" == "true" ]] && opts+=("-a")
    [[ "${RSYNC_DELETE:-true}" == "true" ]] && opts+=("--delete")
    [[ "${RSYNC_PROGRESS:-true}" == "true" ]] && opts+=("--info=progress2")
    [[ "${RSYNC_COMPRESS:-false}" == "true" ]] && opts+=("-z")
    [[ "${DRY_RUN:-false}" == "true" ]] && opts+=("--dry-run")

    opts+=("-v" "-h")

    echo "${opts[@]}"
}

# Build --exclude arguments from a newline-separated string.
#   local args=$(build_exclude_args "$EXCLUDES")
build_exclude_args() {
    local excludes="$1"
    local exclude_args=()

    if [[ -n "$excludes" ]]; then
        while IFS= read -r pattern; do
            [[ -n "$pattern" ]] && exclude_args+=("--exclude=$pattern")
        done <<< "$excludes"
    fi

    echo "${exclude_args[@]}"
}
