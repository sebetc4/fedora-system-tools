#!/bin/bash
# shellcheck disable=SC2317,SC2329
# =============================================================================
# BACKUP-SYSTEM - Full system backup to external HDD
# =============================================================================
# Dynamic rsync backup driven by config: paths with exclusions, pre/post
# hooks for extensibility (BTRFS, Bitwarden, custom scripts).
#
# Module: backup
# Requires: core, log, ui, yaml, validate, backup
# Version: 0.1.0
#
# Usage:
#   sudo backup-system [OPTIONS]
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

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/backup.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

detect_real_user

readonly DEFAULT_CONFIG_FILE="$REAL_HOME/.config/backup/system.yml"
readonly LOCK_FILE="/run/lock/backup-system.lock"

# Logger tag for notify-daemon integration
readonly LOG_TAG="notify-backup-system"

# shellcheck disable=SC2034  # used by log.sh for timestamp formatting
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"

# =============================================================================
# NOTIFICATIONS (via notify-daemon / logger)
# =============================================================================
# Filtering is handled by notify-daemon based on the tag's level in levels.conf.
# Use: notify-manage level notify-backup-system [all|important|none]
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

    # Load configuration
    BACKUP_MOUNT=$(parse_yaml "backup.hdd_mount")
    BACKUP_ROOT=$(parse_yaml "backup.backup_root")

    # Logging
    LOG_FILE=$(parse_yaml "logging.file")

    # Advanced options
    RSYNC_OPTIONS=$(parse_yaml "advanced.rsync_options")

    # Set defaults if empty
    [[ -z "$LOG_FILE" ]] && LOG_FILE="/var/log/backup/backup-system.log"

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
    validate_path "backup.backup_root" "$BACKUP_ROOT"
    validate_path "logging.file" "$LOG_FILE"

    # Validate paths[] entries
    local path_count
    path_count=$(parse_yaml_count "paths")

    for ((i=0; i<path_count; i++)); do
        local p_name p_source p_dest p_enabled p_btrfs_snap
        p_name=$(parse_yaml_index "paths" "$i" "name")
        p_source=$(parse_yaml_index "paths" "$i" "source")
        p_dest=$(parse_yaml_index "paths" "$i" "dest_subdir")
        p_enabled=$(parse_yaml_index "paths" "$i" "enabled")
        p_btrfs_snap=$(parse_yaml_index "paths" "$i" "btrfs_snapshot")

        validate_required "paths[$i].name" "$p_name"
        validate_required "paths[$i].source" "$p_source"
        [[ -n "$p_source" ]] && validate_path "paths[$i].source" "$p_source"
        [[ -n "$p_enabled" ]] && validate_boolean "paths[$i].enabled" "$p_enabled"
        [[ -n "$p_btrfs_snap" ]] && validate_boolean "paths[$i].btrfs_snapshot" "$p_btrfs_snap"

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
# DYNAMIC RSYNC BACKUP
# =========================================================================
# Iterates over paths[] from config: each enabled path is rsynced to
# its dest_subdir under BACKUP_ROOT. Optional per-path btrfs_snapshot
# creates a temporary read-only snapshot for consistency.
backup_paths() {
    local path_count
    path_count=$(parse_yaml_count "paths")

    if [[ "$path_count" -eq 0 ]]; then
        log_warn "No paths configured in config"
        return
    fi

    for ((i=0; i<path_count; i++)); do
        local p_name p_source p_dest p_enabled p_btrfs_snap
        p_name=$(parse_yaml_index "paths" "$i" "name")
        p_source=$(parse_yaml_index "paths" "$i" "source")
        p_dest=$(parse_yaml_index "paths" "$i" "dest_subdir")
        p_enabled=$(parse_yaml_index "paths" "$i" "enabled")
        p_btrfs_snap=$(parse_yaml_index "paths" "$i" "btrfs_snapshot")

        # Skip disabled paths
        if [[ "$p_enabled" != "true" ]]; then
            info "Path '$p_name': disabled (skipping)"
            continue
        fi

        # Skip if source doesn't exist or is empty
        if [[ ! -d "$p_source" ]]; then
            log_warn "Path '$p_name': source not found: $p_source (skipping)"
            continue
        fi

        log_section "BACKUP $p_name ($p_source)"

        local dest="$BACKUP_ROOT/$p_dest"
        mkdir -p "$dest"

        # Build exclusions for this path
        local exclusions=()
        while IFS= read -r excl; do
            [[ -z "$excl" ]] && continue
            exclusions+=("--exclude=$excl")
        done < <(parse_yaml_index_array "paths" "$i" "exclusions")
        exclusions+=("--exclude=.snapshots")

        info "Source      : $p_source/"
        info "Destination : $dest/"
        info "Exclusions  : ${#exclusions[@]} rules"

        if [[ "$DRY_RUN" == "true" ]]; then
            info "Rules: ${exclusions[*]}"
        fi

        # Optional: temporary read-only snapshot for consistency
        local rsync_source="$p_source"
        local temp_snapshot=""

        if [[ "$p_btrfs_snap" == "true" ]] && [[ "$DRY_RUN" == "false" ]]; then
            temp_snapshot="${p_source%/}/.backup-snapshot-$$"
            if btrfs subvolume snapshot -r "$p_source" "$temp_snapshot" 2>/dev/null; then
                log "Temporary snapshot for consistency: $temp_snapshot"
                rsync_source="$temp_snapshot"
            else
                log_warn "Cannot create temp snapshot, backup without consistency guarantee"
                temp_snapshot=""
            fi
        fi

        # Run rsync
        log "Starting rsync $p_source/..."
        # shellcheck disable=SC2086  # RSYNC_OPTIONS intentionally word-split
        rsync_safe $RSYNC_OPTIONS --delete "${exclusions[@]}" "$rsync_source/" "$dest/"

        # Cleanup temp snapshot
        if [[ -n "$temp_snapshot" ]] && [[ -d "$temp_snapshot" ]]; then
            log "Deleting temporary snapshot..."
            btrfs subvolume delete "$temp_snapshot" 2>/dev/null || log_warn "Failed to delete temporary snapshot"
        fi

        log_success "Backup $p_name completed"
    done
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
        RSYNC_OPTIONS="$RSYNC_OPTIONS --dry-run"
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
    # OPTIONAL CHECKS
    # =========================================================================
    if [[ "$ENABLE_SCRUB" == "true" ]]; then
        log_section "BTRFS SCRUB (INTEGRITY CHECK)"
        btrfs_run_scrub "$BACKUP_MOUNT" "External HDD"
    fi

    if [[ "$ENABLE_STATS" == "true" ]] && command -v compsize &> /dev/null; then
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
