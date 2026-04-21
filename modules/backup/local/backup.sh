#!/bin/bash
# shellcheck disable=SC2317,SC2329
# =============================================================================
# BACKUP-LOCAL - Local machine backup to external HDD
# =============================================================================
# Dynamic backup driven by config with per-path strategy selection:
#   - rsync   : incremental mirror (default, good for home/projects)
#   - archive : tar.zst dated archives (SMR-friendly for system paths)
#
# Cross-filesystem destination support: BTRFS snapshots on BTRFS, dated
# directory timelines on ext4/xfs/other. Pre/post hooks for extensibility.
#
# Module: backup
# Requires: core, log, ui, yaml, validate, fs, backup-lib
# Version: 0.2.0
#
# Usage:
#   sudo backup-local [OPTIONS]
#
# Options:
#   -c, --config <file>  Configuration file
#   -n, --dry-run        Simulate backup
#   -y, --yes            Skip hook confirmation prompts
#   --scrub              Run BTRFS scrub after backup
#   --stats              Display compression statistics
#   -h, --help           Display this help
# =============================================================================

set -euo pipefail

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"
readonly BACKUP_LIB_DIR="/usr/local/lib/backup-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/fs.sh"
source "$BACKUP_LIB_DIR/backup-lib.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.2.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

detect_real_user

readonly DEFAULT_CONFIG_FILE="$REAL_HOME/.config/backup/local.yml"
readonly LOCK_FILE="/run/lock/backup-local.lock"

# Logger tag for notify-daemon integration
readonly LOG_TAG="notify-backup-local"

# shellcheck disable=SC2034  # used by log.sh for timestamp formatting
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"

# =============================================================================
# NOTIFICATIONS (via notify-daemon / logger)
# =============================================================================
# Filtering is handled by notify-daemon based on the tag's level in levels.conf.
# Use: notify-manage level notify-backup-local [all|important|none]
send_notification() {
    local type="$1"     # "success" or "error"
    local title="$2"
    local message="$3"

    case "$type" in
        success)
            logger -t "$LOG_TAG" -p user.notice "[ICON:drive-harddisk] $title: $message" 2>/dev/null || true
            ;;
        error)
            logger -t "$LOG_TAG" -p user.err "[ICON:dialog-error] $title: $message" 2>/dev/null || true
            ;;
    esac
}

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
${C_CYAN}System Backup v${VERSION}${C_NC}

Dynamic rsync backup to external HDD with hook support.

${C_GREEN}Usage:${C_NC}
    sudo $SCRIPT_NAME [OPTIONS]

${C_GREEN}Options:${C_NC}
    -c, --config <file>  Configuration file (default: $DEFAULT_CONFIG_FILE)
    -n, --dry-run        Simulate backup (test exclusions and paths)
    -y, --yes            Skip hook confirmation prompts
    --scrub              Run BTRFS scrub after backup (check integrity)
    --stats              Display BTRFS compression statistics
    -h, --help           Display this help

${C_GREEN}Configuration:${C_NC}
    Default: $DEFAULT_CONFIG_FILE

    Modify this file to change:
    - Paths to backup (with per-path exclusions)
    - Pre/post-backup hooks
    - Notifications
    - Rsync options

${C_GREEN}Examples:${C_NC}
    # Normal backup
    sudo $SCRIPT_NAME

    # Backup with integrity check
    sudo $SCRIPT_NAME --scrub

    # Dry run to test
    sudo $SCRIPT_NAME --dry-run

    # Skip hook confirmations
    sudo $SCRIPT_NAME --yes

EOF
}

# =============================================================================
# CONFIG
# =============================================================================
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Configuration file not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    # Backup paths
    BACKUP_MOUNT=$(parse_yaml "backup.hdd_mount")
    BACKUP_ROOT=$(parse_yaml "backup.backup_root")

    # Logging
    LOG_FILE=$(parse_yaml "logging.file")
    [[ -z "$LOG_FILE" ]] && LOG_FILE="/var/log/backup/backup-local.log"

    # Rsync (structured, aligned with hdd-to-hdd / hdd-to-both-hdd)
    RSYNC_DELETE=$(parse_yaml "rsync.delete")
    [[ -z "$RSYNC_DELETE" ]] && RSYNC_DELETE="true"

    RSYNC_PROGRESS=$(parse_yaml "rsync.progress")
    [[ -z "$RSYNC_PROGRESS" ]] && RSYNC_PROGRESS="true"

    RSYNC_COMPRESS=$(parse_yaml "rsync.compress")
    [[ -z "$RSYNC_COMPRESS" ]] && RSYNC_COMPRESS="false"

    RSYNC_ARCHIVE=$(parse_yaml "rsync.archive")
    [[ -z "$RSYNC_ARCHIVE" ]] && RSYNC_ARCHIVE="true"

    RSYNC_PARTIAL=$(parse_yaml "rsync.partial")
    [[ -z "$RSYNC_PARTIAL" ]] && RSYNC_PARTIAL="true"

    RSYNC_INPLACE=$(parse_yaml "rsync.inplace")
    [[ -z "$RSYNC_INPLACE" ]] && RSYNC_INPLACE="false"

    # System-backup-critical metadata (defaults ON for backup-local)
    RSYNC_ACLS=$(parse_yaml "rsync.acls")
    [[ -z "$RSYNC_ACLS" ]] && RSYNC_ACLS="true"

    RSYNC_XATTRS=$(parse_yaml "rsync.xattrs")
    [[ -z "$RSYNC_XATTRS" ]] && RSYNC_XATTRS="true"

    RSYNC_HARD_LINKS=$(parse_yaml "rsync.hard_links")
    [[ -z "$RSYNC_HARD_LINKS" ]] && RSYNC_HARD_LINKS="true"

    RSYNC_NUMERIC_IDS=$(parse_yaml "rsync.numeric_ids")
    [[ -z "$RSYNC_NUMERIC_IDS" ]] && RSYNC_NUMERIC_IDS="true"

    RSYNC_ONE_FILE_SYSTEM=$(parse_yaml "rsync.one_file_system")
    [[ -z "$RSYNC_ONE_FILE_SYSTEM" ]] && RSYNC_ONE_FILE_SYSTEM="true"

    # Optional tuning (defaults OFF)
    RSYNC_CHECKSUM=$(parse_yaml "rsync.checksum")
    [[ -z "$RSYNC_CHECKSUM" ]] && RSYNC_CHECKSUM="false"

    RSYNC_SPARSE=$(parse_yaml "rsync.sparse")
    [[ -z "$RSYNC_SPARSE" ]] && RSYNC_SPARSE="false"

    RSYNC_WHOLE_FILE=$(parse_yaml "rsync.whole_file")
    [[ -z "$RSYNC_WHOLE_FILE" ]] && RSYNC_WHOLE_FILE="false"

    RSYNC_STATS=$(parse_yaml "rsync.stats")
    [[ -z "$RSYNC_STATS" ]] && RSYNC_STATS="false"

    # Bandwidth limit (string: "0"/"" = unlimited, or "50M", "100m", "10240" kB/s)
    RSYNC_BWLIMIT=$(parse_yaml "rsync.bwlimit")
    [[ -z "$RSYNC_BWLIMIT" ]] && RSYNC_BWLIMIT="0"

    # BTRFS options
    BTRFS_SCRUB_CFG=$(parse_yaml "btrfs.scrub_after_backup")
    [[ -z "$BTRFS_SCRUB_CFG" ]] && BTRFS_SCRUB_CFG="false"

    BTRFS_STATS_CFG=$(parse_yaml "btrfs.show_compression_stats")
    [[ -z "$BTRFS_STATS_CFG" ]] && BTRFS_STATS_CFG="false"

    # Destination snapshots / timeline
    SNAP_ENABLED=$(parse_yaml "snapshots.enabled")
    [[ -z "$SNAP_ENABLED" ]] && SNAP_ENABLED="false"

    SNAP_DIR=$(parse_yaml "snapshots.directory")
    [[ -z "$SNAP_DIR" ]] && SNAP_DIR=".snapshots"

    SNAP_KEEP=$(parse_yaml "snapshots.retention")
    [[ -z "$SNAP_KEEP" ]] && SNAP_KEEP=3

    SNAP_PREFIX=$(parse_yaml "snapshots.prefix")
    [[ -z "$SNAP_PREFIX" ]] && SNAP_PREFIX="backup"

    SNAP_MODE=$(parse_yaml "snapshots.mode")
    [[ -z "$SNAP_MODE" ]] && SNAP_MODE="backup-dir"

    # Open log file descriptor
    log_open_fd

    # Validate configuration
    validate_config
}

validate_config() {
    validation_reset

    # Required fields
    validate_required "backup.hdd_mount" "$BACKUP_MOUNT"
    validate_required "backup.backup_root" "$BACKUP_ROOT"

    # Paths
    validate_path "backup.hdd_mount" "$BACKUP_MOUNT"
    validate_mount "backup.hdd_mount" "$BACKUP_MOUNT"
    validate_path "backup.backup_root" "$BACKUP_ROOT"
    validate_path "logging.file" "$LOG_FILE"

    # Rsync / BTRFS / snapshots booleans
    validate_boolean "rsync.delete" "$RSYNC_DELETE"
    validate_boolean "rsync.progress" "$RSYNC_PROGRESS"
    validate_boolean "rsync.compress" "$RSYNC_COMPRESS"
    validate_boolean "rsync.archive" "$RSYNC_ARCHIVE"
    validate_boolean "rsync.partial" "$RSYNC_PARTIAL"
    validate_boolean "rsync.inplace" "$RSYNC_INPLACE"
    validate_boolean "rsync.acls" "$RSYNC_ACLS"
    validate_boolean "rsync.xattrs" "$RSYNC_XATTRS"
    validate_boolean "rsync.hard_links" "$RSYNC_HARD_LINKS"
    validate_boolean "rsync.numeric_ids" "$RSYNC_NUMERIC_IDS"
    validate_boolean "rsync.one_file_system" "$RSYNC_ONE_FILE_SYSTEM"
    validate_boolean "rsync.checksum" "$RSYNC_CHECKSUM"
    validate_boolean "rsync.sparse" "$RSYNC_SPARSE"
    validate_boolean "rsync.whole_file" "$RSYNC_WHOLE_FILE"
    validate_boolean "rsync.stats" "$RSYNC_STATS"
    validate_boolean "btrfs.scrub_after_backup" "$BTRFS_SCRUB_CFG"
    validate_boolean "btrfs.show_compression_stats" "$BTRFS_STATS_CFG"
    validate_boolean "snapshots.enabled" "$SNAP_ENABLED"
    validate_integer "snapshots.retention" "$SNAP_KEEP"
    if [[ "$SNAP_MODE" != "backup-dir" ]] && [[ "$SNAP_MODE" != "link-dest" ]]; then
        validation_add_error "snapshots.mode must be 'backup-dir' or 'link-dest' (got: $SNAP_MODE)"
    fi

    # Validate paths[] entries
    local path_count
    path_count=$(parse_yaml_count "paths")

    for ((i=0; i<path_count; i++)); do
        local p_name p_source p_dest p_enabled p_strategy p_btrfs_snap
        p_name=$(parse_yaml_index "paths" "$i" "name")
        p_source=$(parse_yaml_index "paths" "$i" "source")
        p_dest=$(parse_yaml_index "paths" "$i" "dest_subdir")
        p_enabled=$(parse_yaml_index "paths" "$i" "enabled")
        p_strategy=$(parse_yaml_index "paths" "$i" "strategy")
        p_btrfs_snap=$(parse_yaml_index "paths" "$i" "btrfs_snapshot")

        validate_required "paths[$i].name" "$p_name"
        validate_required "paths[$i].source" "$p_source"
        [[ -n "$p_source" ]] && validate_path "paths[$i].source" "$p_source"
        [[ -n "$p_enabled" ]] && validate_boolean "paths[$i].enabled" "$p_enabled"
        [[ -n "$p_btrfs_snap" ]] && validate_boolean "paths[$i].btrfs_snapshot" "$p_btrfs_snap"

        # Strategy: default "rsync", must be rsync|archive
        [[ -z "$p_strategy" ]] && p_strategy="rsync"
        if [[ "$p_strategy" != "rsync" ]] && [[ "$p_strategy" != "archive" ]]; then
            validation_add_error "paths[$i].strategy must be 'rsync' or 'archive' (got: $p_strategy, path: $p_name)"
        fi

        # Archive strategy: validate archive sub-options
        if [[ "$p_strategy" == "archive" ]] && [[ "$p_enabled" == "true" ]]; then
            local a_level a_retention
            a_level=$(parse_yaml_index "paths" "$i" "archive.compression_level")
            a_retention=$(parse_yaml_index "paths" "$i" "archive.retention")
            [[ -n "$a_level" ]] && validate_integer "paths[$i].archive.compression_level" "$a_level"
            [[ -n "$a_retention" ]] && validate_integer "paths[$i].archive.retention" "$a_retention"
        fi

        # dest_subdir required when enabled
        if [[ "$p_enabled" == "true" ]] && [[ -z "$p_dest" ]]; then
            validation_add_error "paths[$i].dest_subdir is required when enabled (path: $p_name)"
        fi
    done

    # Validate hooks
    local phase
    for phase in pre_backup post_backup; do
        local hook_count
        hook_count=$(parse_yaml_count "hooks.${phase}")

        for ((i=0; i<hook_count; i++)); do
            local h_name h_script h_enabled h_confirm
            h_name=$(parse_yaml_index "hooks.${phase}" "$i" "name")
            h_script=$(parse_yaml_index "hooks.${phase}" "$i" "script")
            h_enabled=$(parse_yaml_index "hooks.${phase}" "$i" "enabled")
            h_confirm=$(parse_yaml_index "hooks.${phase}" "$i" "confirm")

            validate_required "hooks.${phase}[$i].name" "$h_name"
            validate_required "hooks.${phase}[$i].script" "$h_script"
            [[ -n "$h_enabled" ]] && validate_boolean "hooks.${phase}[$i].enabled" "$h_enabled"
            [[ -n "$h_confirm" ]] && validate_boolean "hooks.${phase}[$i].confirm" "$h_confirm"
        done
    done

    validation_check "$YAML_FILE"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
ENABLE_SCRUB=false
ENABLE_STATS=false
DRY_RUN=false
SKIP_CONFIRM=false

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                YAML_FILE="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            --scrub)
                ENABLE_SCRUB=true
                shift
                ;;
            --stats)
                ENABLE_STATS=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1

Use --help to see available options" "exit"
                ;;
        esac
    done
}

# =============================================================================
# MAIN BACKUP LOGIC
# =============================================================================

# =========================================================================
# PER-PATH BACKUP DISPATCH
# =========================================================================
# Iterates over paths[] from config and dispatches to strategy:
#   rsync   → incremental mirror under backup_root/dest_subdir/
#   archive → tar.zst dated archive in backup_root/dest_subdir/
# Destination snapshots (timeline) wrap the rsync-strategy paths as a group.
backup_paths() {
    local path_count
    path_count=$(parse_yaml_count "paths")

    if [[ "$path_count" -eq 0 ]]; then
        log_warn "No paths configured in config"
        return
    fi

    # Build shared rsync option array once (applies to all rsync-strategy paths)
    local base_rsync_opts=()
    read -ra base_rsync_opts <<< "$(build_rsync_options)"

    # Inject destination timeline args (non-BTRFS backup-dir mode)
    if [[ "$SNAP_ENABLED" == "true" ]]; then
        timeline_begin "$BACKUP_ROOT" "$SNAP_DIR" "$SNAP_PREFIX" "$SNAP_MODE"
        base_rsync_opts+=("${TIMELINE_RSYNC_ARGS[@]}")
    fi

    local did_rsync=false

    for ((i=0; i<path_count; i++)); do
        local p_name p_source p_dest p_enabled p_strategy p_btrfs_snap
        p_name=$(parse_yaml_index "paths" "$i" "name")
        p_source=$(parse_yaml_index "paths" "$i" "source")
        p_dest=$(parse_yaml_index "paths" "$i" "dest_subdir")
        p_enabled=$(parse_yaml_index "paths" "$i" "enabled")
        p_strategy=$(parse_yaml_index "paths" "$i" "strategy")
        p_btrfs_snap=$(parse_yaml_index "paths" "$i" "btrfs_snapshot")
        [[ -z "$p_strategy" ]] && p_strategy="rsync"

        # Skip disabled paths
        if [[ "$p_enabled" != "true" ]]; then
            info "Path '$p_name': disabled (skipping)"
            continue
        fi

        # Skip if source doesn't exist
        if [[ ! -d "$p_source" ]]; then
            log_warn "Path '$p_name': source not found: $p_source (skipping)"
            continue
        fi

        log_section "BACKUP $p_name ($p_source) [strategy: $p_strategy]"

        local dest="$BACKUP_ROOT/$p_dest"

        # Collect exclusions
        local exclusions=()
        while IFS= read -r excl; do
            [[ -z "$excl" ]] && continue
            exclusions+=("$excl")
        done < <(parse_yaml_index_array "paths" "$i" "exclusions")

        case "$p_strategy" in
            rsync)
                backup_path_rsync "$p_name" "$p_source" "$dest" "$p_btrfs_snap" \
                    base_rsync_opts exclusions
                did_rsync=true
                ;;
            archive)
                backup_path_archive "$i" "$p_name" "$p_source" "$dest" exclusions
                ;;
        esac
    done

    # Finalize destination timeline (only if at least one rsync ran)
    if [[ "$SNAP_ENABLED" == "true" ]] && [[ "$did_rsync" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        log_section "FINALIZING SNAPSHOT"
        timeline_end "$BACKUP_ROOT" "$SNAP_DIR" "$SNAP_PREFIX" "$SNAP_KEEP" "$SNAP_MODE"
    fi
}

# Rsync one path. Takes source rsync opts array by nameref.
backup_path_rsync() {
    local name="$1"
    local source="$2"
    local dest="$3"
    local btrfs_snap="$4"
    local -n _opts=$5
    local -n _exclusions=$6

    mkdir -p "$dest"

    # Always exclude the snapshots directory from source side
    local rsync_excludes=()
    local excl
    for excl in "${_exclusions[@]}"; do
        rsync_excludes+=("--exclude=$excl")
    done
    rsync_excludes+=("--exclude=$SNAP_DIR")

    info "Source      : $source/"
    info "Destination : $dest/"
    info "Exclusions  : ${#rsync_excludes[@]} rules"

    # Optional source-side temporary snapshot for consistency (BTRFS only)
    local rsync_source="$source"
    local temp_snapshot=""

    if [[ "$btrfs_snap" == "true" ]] && [[ "$DRY_RUN" != "true" ]]; then
        temp_snapshot="${source%/}/.backup-snapshot-$$"
        if btrfs subvolume snapshot -r "$source" "$temp_snapshot" 2>/dev/null; then
            log "Temporary source snapshot for consistency: $temp_snapshot"
            rsync_source="$temp_snapshot"
        else
            log_warn "Cannot create temp source snapshot, backup without consistency guarantee"
            temp_snapshot=""
        fi
    fi

    log "Starting rsync $source/..."
    rsync_safe "${_opts[@]}" "${rsync_excludes[@]}" "$rsync_source/" "$dest/"

    # Cleanup temp snapshot
    if [[ -n "$temp_snapshot" ]] && [[ -d "$temp_snapshot" ]]; then
        log "Deleting temporary source snapshot..."
        btrfs subvolume delete "$temp_snapshot" 2>/dev/null || log_warn "Failed to delete temporary snapshot"
    fi

    log_success "Backup $name completed"
}

# Create a dated tar.zst archive for one path.
backup_path_archive() {
    local idx="$1"
    local name="$2"
    local source="$3"
    local dest="$4"
    local -n _exclusions=$5

    # Archive options (with defaults)
    local a_level a_retention
    a_level=$(parse_yaml_index "paths" "$idx" "archive.compression_level")
    a_retention=$(parse_yaml_index "paths" "$idx" "archive.retention")
    [[ -z "$a_level" ]] && a_level=10
    [[ -z "$a_retention" ]] && a_retention=6

    info "Source           : $source"
    info "Destination      : $dest/"
    info "Compression      : zstd -$a_level"
    info "Retention        : $a_retention archives"
    info "Exclusions       : ${#_exclusions[@]} rules"

    archive_create "$source" "$dest" "$name" "$a_level" "${_exclusions[@]}"
    archive_rotate "$dest" "$name" "$a_retention"

    log_success "Archive $name completed"
}

# =========================================================================
# HOOK ENGINE
# =========================================================================
# Runs hooks declared in hooks.pre_backup[] or hooks.post_backup[].
# Each hook is a standalone script with its own config file.
# Hooks are validated, optionally confirmed (ui_confirm), and executed.
# A failing hook logs a warning but does NOT stop the backup.
run_hooks() {
    local phase="$1"   # "pre_backup" or "post_backup"

    local hook_count
    hook_count=$(parse_yaml_count "hooks.${phase}")
    [[ "$hook_count" -eq 0 ]] && return 0

    log_section "HOOKS: ${phase^^}"

    for ((i=0; i<hook_count; i++)); do
        local h_name h_script h_enabled h_confirm h_run_as_user
        h_name=$(parse_yaml_index "hooks.${phase}" "$i" "name")
        h_script=$(parse_yaml_index "hooks.${phase}" "$i" "script")
        h_enabled=$(parse_yaml_index "hooks.${phase}" "$i" "enabled")
        h_confirm=$(parse_yaml_index "hooks.${phase}" "$i" "confirm")
        h_run_as_user=$(parse_yaml_index "hooks.${phase}" "$i" "run_as_user")

        # Skip disabled hooks
        if [[ "$h_enabled" != "true" ]]; then
            info "Hook '$h_name': disabled (skipping)"
            continue
        fi

        # Validate hook script exists and is executable
        if [[ ! -x "$h_script" ]]; then
            log_warn "Hook '$h_name': script not found or not executable: $h_script"
            continue
        fi

        # Confirmation prompt (skipped with --yes or in dry-run mode)
        if [[ "$h_confirm" == "true" ]] && [[ "$SKIP_CONFIRM" != "true" ]]; then
            if ! ui_confirm "Run hook '$h_name'?"; then
                info "Hook '$h_name': skipped by user"
                continue
            fi
        fi

        # Execute hook with context
        log_step "Running hook: $h_name"

        local hook_args=()
        [[ "$DRY_RUN" == "true" ]] && hook_args+=(--dry-run)
        [[ "$SKIP_CONFIRM" == "true" ]] && hook_args+=(-y)

        # Export context for hooks (they manage their own config internally)
        export BACKUP_ROOT BACKUP_MOUNT LOG_FILE DRY_RUN

        # run_as_user: drop privileges to the invoking user (for hooks that
        # don't need root, e.g. backup-bitwarden which calls user-installed CLIs)
        local hook_rc=0
        if [[ "$h_run_as_user" == "true" ]] && [[ -n "${SUDO_USER:-}" ]]; then
            local user_home
            user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6)
            sudo -u "$SUDO_USER" env \
                "HOME=$user_home" \
                "SUDO_USER=" \
                "PATH=$(sudo -u "$SUDO_USER" bash -lc 'echo $PATH')" \
                "BACKUP_ROOT=${BACKUP_ROOT:-}" \
                "BACKUP_MOUNT=${BACKUP_MOUNT:-}" \
                "LOG_FILE=${LOG_FILE:-}" \
                "DRY_RUN=${DRY_RUN:-}" \
                "$h_script" "${hook_args[@]}" || hook_rc=$?
        else
            "$h_script" "${hook_args[@]}" || hook_rc=$?
        fi

        if [[ "$hook_rc" -eq 0 ]]; then
            log_success "Hook '$h_name' completed"
        else
            log_warn "Hook '$h_name' failed (continuing)"
            send_notification "error" "Backup Hook" "Hook '$h_name' failed"
        fi
    done
}

# =========================================================================
# FINAL REPORT
# =========================================================================
generate_report() {
    local start_time="$1"

    local END_TIME
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - start_time))
    local DURATION_MIN=$((DURATION / 60))
    local DURATION_SEC=$((DURATION % 60))

    log_section "BACKUP COMPLETED SUCCESSFULLY"

    # Disk space
    info "External HDD space:"
    df -h "$BACKUP_MOUNT"

    # Backup sizes (dynamic from enabled paths)
    info "Backup sizes:"
    local path_count
    path_count=$(parse_yaml_count "paths")

    for ((i=0; i<path_count; i++)); do
        local p_enabled p_dest p_name
        p_enabled=$(parse_yaml_index "paths" "$i" "enabled")
        p_dest=$(parse_yaml_index "paths" "$i" "dest_subdir")
        p_name=$(parse_yaml_index "paths" "$i" "name")

        if [[ "$p_enabled" == "true" ]] && [[ -d "$BACKUP_ROOT/$p_dest" ]]; then
            du -sh "$BACKUP_ROOT/$p_dest" 2>/dev/null || true
        fi
    done

    # Duration
    log_success "Total duration: ${DURATION_MIN}m ${DURATION_SEC}s"
    log_success "Full log: $LOG_FILE"

    # Notification
    send_notification "success" \
        "Backup completed" \
        "System backup completed successfully (${DURATION_MIN}m ${DURATION_SEC}s)"

    log "========================================================================="
}

main() {
    # Parse command line arguments first (for --help without root)
    parse_arguments "$@"

    # Check that script is run as root (before load_config which opens log FD)
    check_root

    # Check dependencies
    check_deps "yq" "rsync"

    # Load configuration (also opens log file descriptor)
    load_config "${YAML_FILE:-$DEFAULT_CONFIG_FILE}"

    # Dynamic variables
    local START_TIME
    START_TIME=$(date +%s)

    # Acquire lock (prevents concurrent executions)
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        error "A backup is already running (lock: $LOCK_FILE)" "exit"
    fi
    trap 'log_close_fd; flock -u 200; rm -f "$LOCK_FILE"' EXIT

    # =========================================================================
    # BACKUP START
    # =========================================================================
    if [[ "$DRY_RUN" == "true" ]]; then
        log_section "DRY-RUN MODE - BACKUP SIMULATION"
        log_warn "No files will be modified"
    else
        log_section "SYSTEM BACKUP START"
    fi

    info "Date: $(date '+%A %d %B %Y, %H:%M:%S')"
    info "Configuration: $YAML_FILE"
    info "Destination: $BACKUP_MOUNT"
    info ""

    # Check if HDD is mounted
    if ! is_mounted "$BACKUP_MOUNT"; then
        error "External HDD not mounted on $BACKUP_MOUNT

The HDD should be mounted automatically.

Checks:
1. Is the HDD plugged in?
2. Did LUKS decryption succeed?
3. Check: lsblk
4. Check mounts: mount | grep hdd1

If necessary, mount manually:
    sudo mount /mnt/hdd1" "exit"
    fi

    success "External HDD detected and mounted"

    # Check available space
    local AVAILABLE_SPACE
    AVAILABLE_SPACE=$(df -BG "$BACKUP_MOUNT" | tail -1 | awk '{print $4}' | tr -d 'G')
    info "Available space: ${AVAILABLE_SPACE}G"

    if [[ "$AVAILABLE_SPACE" -lt 50 ]]; then
        log_warn "Low available space: ${AVAILABLE_SPACE}G"
        log_warn "Consider cleaning up or increasing retention"
    fi

    # =========================================================================
    # PRE-BACKUP HOOKS
    # =========================================================================
    run_hooks "pre_backup"

    # =========================================================================
    # RSYNC BACKUP (dynamic paths)
    # =========================================================================
    backup_paths

    # =========================================================================
    # POST-BACKUP HOOKS
    # =========================================================================
    run_hooks "post_backup"

    # =========================================================================
    # OPTIONAL CHECKS (CLI flags override config toggles)
    # =========================================================================
    if [[ "$ENABLE_SCRUB" == "true" ]] || [[ "$BTRFS_SCRUB_CFG" == "true" ]]; then
        log_section "BTRFS SCRUB (INTEGRITY CHECK)"
        btrfs_run_scrub "$BACKUP_MOUNT" "External HDD"
    fi

    if [[ "$ENABLE_STATS" == "true" ]] || [[ "$BTRFS_STATS_CFG" == "true" ]]; then
        log_section "COMPRESSION STATISTICS"
        btrfs_show_stats "$BACKUP_ROOT" "Backup"
    fi

    # =========================================================================
    # FINAL REPORT
    # =========================================================================
    generate_report "$START_TIME"

    exit 0
}

# Execute main function
main "$@"
