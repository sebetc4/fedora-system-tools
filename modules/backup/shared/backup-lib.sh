#!/bin/bash
# =============================================================================
# BACKUP-LIB.SH - Backup module shared library
# =============================================================================
# Backup-specific helpers used by backup-local, backup-hdd, backup-hdd-both,
# and backup-bitwarden.
#
# Scope:
#   - BTRFS operations (snapshots, rotation, scrub, compression stats)
#   - Rsync helpers (safe wrapper, option builder, exclude builder)
#   - FS-agnostic destination timeline (backup-dir / link-dest / BTRFS snapshot)
#   - Archive creation (tar + zstd + SHA-256, with rotation)
#
# This file is owned by the backup module and installed to
# /usr/local/lib/backup-scripts/backup-lib.sh by the core submodule's
# install hook (modules/backup/shared/setup-backup.sh).
#
# Requires: core.sh, log.sh, fs.sh (from /usr/local/lib/system-scripts/)
#
# Usage:
#   readonly BACKUP_LIB_DIR="/usr/local/lib/backup-scripts"
#   source "$BACKUP_LIB_DIR/backup-lib.sh"
# =============================================================================

[[ -n "${_BACKUP_LIB_LOADED:-}" ]] && return 0
readonly _BACKUP_LIB_LOADED=1

# Depend on lib/fs.sh (which sources core.sh + log.sh).
readonly _SYSTEM_LIB_DIR="${LIB_DIR:-/usr/local/lib/system-scripts}"
source "$_SYSTEM_LIB_DIR/core.sh"
source "$_SYSTEM_LIB_DIR/log.sh"
source "$_SYSTEM_LIB_DIR/fs.sh"

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
# Expects: RSYNC_ARCHIVE, RSYNC_DELETE, RSYNC_PROGRESS, RSYNC_COMPRESS,
#          RSYNC_PARTIAL, RSYNC_INPLACE, RSYNC_ACLS, RSYNC_XATTRS,
#          RSYNC_HARD_LINKS, RSYNC_NUMERIC_IDS, RSYNC_ONE_FILE_SYSTEM,
#          RSYNC_CHECKSUM, RSYNC_SPARSE, RSYNC_WHOLE_FILE, RSYNC_STATS,
#          RSYNC_BWLIMIT, DRY_RUN
# Outputs space-separated options string.
build_rsync_options() {
    local opts=()

    [[ "${RSYNC_ARCHIVE:-true}" == "true" ]] && opts+=("-a")
    [[ "${RSYNC_DELETE:-true}" == "true" ]] && opts+=("--delete")
    [[ "${RSYNC_PROGRESS:-true}" == "true" ]] && opts+=("--info=progress2")
    [[ "${RSYNC_COMPRESS:-false}" == "true" ]] && opts+=("-z")
    [[ "${RSYNC_PARTIAL:-false}" == "true" ]] && opts+=("--partial")
    [[ "${RSYNC_INPLACE:-false}" == "true" ]] && opts+=("--inplace")
    [[ "${RSYNC_ACLS:-false}" == "true" ]] && opts+=("-A")
    [[ "${RSYNC_XATTRS:-false}" == "true" ]] && opts+=("-X")
    [[ "${RSYNC_HARD_LINKS:-false}" == "true" ]] && opts+=("-H")
    [[ "${RSYNC_NUMERIC_IDS:-false}" == "true" ]] && opts+=("--numeric-ids")
    [[ "${RSYNC_ONE_FILE_SYSTEM:-false}" == "true" ]] && opts+=("-x")
    [[ "${RSYNC_CHECKSUM:-false}" == "true" ]] && opts+=("-c")
    [[ "${RSYNC_SPARSE:-false}" == "true" ]] && opts+=("-S")
    [[ "${RSYNC_WHOLE_FILE:-false}" == "true" ]] && opts+=("-W")
    [[ "${RSYNC_STATS:-false}" == "true" ]] && opts+=("--stats")
    [[ "${DRY_RUN:-false}" == "true" ]] && opts+=("--dry-run")

    # Non-boolean: bandwidth limit (accepts "0"/"" for unlimited, or a rate
    # like "50M", "100m", "10240"). Passed verbatim to rsync --bwlimit.
    local _bw="${RSYNC_BWLIMIT:-}"
    if [[ -n "$_bw" ]] && [[ "$_bw" != "0" ]]; then
        opts+=("--bwlimit=$_bw")
    fi

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

# =============================================================================
# Dated-directory timeline (non-BTRFS versioning)
# =============================================================================
# Timestamped history on destinations whose filesystem has no native snapshot
# support (ext4, xfs, …). Complements btrfs_create_snapshot / btrfs_rotate_snapshots
# so callers can dispatch uniformly via timeline_begin / timeline_end.

# Produce a timestamped name: "<prefix>-YYYYMMDD-HHMMSS"
dated_name() {
    local prefix="$1"
    echo "${prefix}-$(date +%Y%m%d-%H%M%S)"
}

# Rotate dated directories beyond retention count (non-BTRFS).
#   rotate_dated_dirs "/mnt/backup/.snapshots" "backup" 3
rotate_dated_dirs() {
    local parent="$1"
    local prefix="$2"
    local keep="$3"

    [[ ! -d "$parent" ]] && return 0

    local dirs=()
    while IFS= read -r dir; do
        [[ -n "$dir" ]] && dirs+=("$dir")
    done < <(find "$parent" -maxdepth 1 -mindepth 1 -type d -name "${prefix}-*" 2>/dev/null | sort)

    local count=${#dirs[@]}
    local to_delete=$((count - keep))

    if [[ $to_delete -gt 0 ]]; then
        log_step "Rotating timeline dirs (keeping $keep, deleting $to_delete)"

        for ((i=0; i<to_delete; i++)); do
            local old="${dirs[$i]}"
            local name
            name=$(basename "$old")

            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                echo "[DRY RUN] Would delete: $name"
            else
                if rm -rf "$old"; then
                    log_success "Deleted: $name"
                else
                    log_warn "Failed to delete: $name"
                fi
            fi
        done
    fi
}

# =============================================================================
# FS-agnostic timeline dispatch
# =============================================================================
# Usage flow:
#   timeline_begin "$DEST" "$SNAP_DIR" "$PREFIX" "$MODE"
#   rsync "${rsync_opts[@]}" "${TIMELINE_RSYNC_ARGS[@]}" "$src/" "$DEST/"
#   timeline_end "$DEST" "$SNAP_DIR" "$PREFIX" "$KEEP" "$MODE"
#
# Mode is ignored on BTRFS destinations. On non-BTRFS:
#   backup-dir  : injects --backup --backup-dir=<dated> (space-efficient; only
#                 changed/deleted files are preserved in the timeline entry)
#   link-dest   : no rsync args; post-sync creates a hardlinked point-in-time
#                 copy of DEST under <DEST>/<SNAP_DIR>/<dated>/

# Populate the global TIMELINE_RSYNC_ARGS array with rsync args to inject.
# Safe for paths containing spaces.
# shellcheck disable=SC2034  # TIMELINE_RSYNC_ARGS is read by callers
timeline_begin() {
    local dest="$1"
    local snap_dir="$2"
    local prefix="$3"
    local mode="${4:-backup-dir}"

    TIMELINE_RSYNC_ARGS=()

    if is_btrfs "$dest"; then
        return
    fi

    case "$mode" in
        backup-dir)
            local ts_name
            ts_name=$(dated_name "$prefix")
            TIMELINE_RSYNC_ARGS=(--backup "--backup-dir=$dest/$snap_dir/$ts_name")
            ;;
        link-dest)
            : # Handled post-sync in timeline_end
            ;;
        *)
            log_warn "Unknown timeline mode: $mode (no versioning applied)"
            ;;
    esac
}

# Finalize the timeline entry: BTRFS snapshot, or non-BTRFS post-sync action,
# then rotate old entries.
timeline_end() {
    local dest="$1"
    local snap_dir="$2"
    local prefix="$3"
    local keep="$4"
    local mode="${5:-backup-dir}"

    if is_btrfs "$dest"; then
        btrfs_create_snapshot "$dest" "$snap_dir" "$prefix"
        btrfs_rotate_snapshots "$dest/$snap_dir" "$prefix" "$keep"
        return
    fi

    # link-dest: post-sync hardlink-copy of DEST into a dated directory
    if [[ "$mode" == "link-dest" ]]; then
        local ts_name
        ts_name=$(dated_name "$prefix")
        local snap_root="$dest/$snap_dir"
        local target="$snap_root/$ts_name"

        log_step "Creating hardlinked snapshot: $ts_name"

        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            echo "[DRY RUN] Would hardlink-copy $dest/ to $target/"
        else
            mkdir -p "$target"
            local entry
            shopt -s dotglob nullglob
            for entry in "$dest"/*; do
                local basename
                basename=$(basename "$entry")
                [[ "$basename" == "$snap_dir" ]] && continue
                cp -al "$entry" "$target/" 2>/dev/null || log_warn "cp -al failed for: $basename"
            done
            shopt -u dotglob nullglob
            log_success "Hardlinked snapshot created: $ts_name"
        fi
    fi

    rotate_dated_dirs "$dest/$snap_dir" "$prefix" "$keep"
}

# =============================================================================
# Archive (tar + zstd) — SMR-friendly sequential write strategy
# =============================================================================

# Create a tar.zst archive with ACL/xattr support and a SHA-256 companion.
#   archive_create <source> <dest_dir> <name_prefix> <zstd_level> [excludes...]
# Produces: <dest_dir>/<name_prefix>-YYYY-MM-DD.tar.zst (+ .sha256)
archive_create() {
    local source="$1"
    local dest_dir="$2"
    local name_prefix="$3"
    local level="${4:-10}"
    shift 4
    local excludes=("$@")

    mkdir -p "$dest_dir"

    local date_str
    date_str=$(date +%Y-%m-%d)
    local archive_name="${name_prefix}-${date_str}.tar.zst"
    local archive_path="$dest_dir/$archive_name"

    log_step "Creating archive: $archive_name (zstd -$level)"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        echo "[DRY RUN] Would create: $archive_path"
        echo "[DRY RUN] Source: $source"
        echo "[DRY RUN] Excludes: ${#excludes[@]} rules"
        return 0
    fi

    local tar_args=(
        --use-compress-program="zstd -T0 -$level"
        --acls
        --xattrs
    )

    local excl
    for excl in "${excludes[@]}"; do
        tar_args+=(--exclude="$excl")
    done

    tar_args+=(-cf "$archive_path" "$source")

    if tar "${tar_args[@]}"; then
        log_success "Archive created: $archive_name"

        log_step "Computing SHA-256..."
        (cd "$dest_dir" && sha256sum "$archive_name" > "${archive_name}.sha256")
        log_success "Hash: ${archive_name}.sha256"

        local size
        size=$(du -h "$archive_path" 2>/dev/null | awk '{print $1}')
        log_success "Size: $size"
    else
        log_error "Archive creation failed"
        rm -f "$archive_path"
        return 1
    fi
}

# Rotate archive files matching <prefix>-*.tar.zst, keeping <keep> most recent.
#   archive_rotate <dir> <prefix> <keep>
archive_rotate() {
    local dir="$1"
    local prefix="$2"
    local keep="$3"

    [[ ! -d "$dir" ]] && return 0

    local archives=()
    while IFS= read -r f; do
        [[ -n "$f" ]] && archives+=("$f")
    done < <(find "$dir" -maxdepth 1 -type f -name "${prefix}-*.tar.zst" 2>/dev/null | sort)

    local count=${#archives[@]}
    local to_delete=$((count - keep))

    if [[ $to_delete -gt 0 ]]; then
        log_step "Rotating archives (keeping $keep, deleting $to_delete)"

        for ((i=0; i<to_delete; i++)); do
            local old="${archives[$i]}"
            local name
            name=$(basename "$old")

            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                echo "[DRY RUN] Would delete: $name"
            else
                rm -f "$old" "${old}.sha256"
                log_success "Deleted: $name"
            fi
        done
    fi
}
