#!/bin/bash
# =============================================================================
# BACKUP-HDD - Simple HDD mirror backup
# =============================================================================
# Performs backup from HDD1 (active) to Backup1 (cold storage)
# with optional Btrfs snapshots for versioning.
#
# Module: backup
# Requires: core, log, yaml, validate, backup
# Version: 0.1.0
#
# Usage:
#   sudo backup-hdd [OPTIONS]
# =============================================================================

set -euo pipefail

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/backup.sh"

# =============================================================================
# ROOT CHECK
# =============================================================================
check_root "$@"

# =============================================================================
# LOCK FILE
# =============================================================================
readonly LOCK_FILE="/run/lock/backup-hdd.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: Another instance is already running" >&2
    exit 1
fi

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly VERSION="0.1.0"

detect_real_user
readonly DEFAULT_CONFIG_FILE="$REAL_HOME/.config/backup/hdd.yml"

# Logger tag for notify-daemon integration
readonly LOG_TAG="notify-backup-hdd"

# Global config variables
# shellcheck disable=SC2034  # used by log.sh for timestamp formatting
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"

# =============================================================================
# NOTIFICATIONS (via notify-daemon / logger)
# =============================================================================
# Filtering is handled by notify-daemon based on the tag's level in levels.conf.
# Use: notify-manage level notify-backup-hdd [all|important|none]
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
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${C_BOLD}BTRFS HDD Backup Script v${VERSION}${C_NC}

Simple HDD mirror backup with optional Btrfs snapshots.

${C_GREEN}Usage:${C_NC}
    $SCRIPT_NAME [options]

${C_GREEN}Options:${C_NC}
    -c, --config <file>    Config file (default: $DEFAULT_CONFIG_FILE)
    -n, --dry-run          Simulate without making changes
    -y, --yes              Skip confirmation prompts
    --snapshot             Create snapshot before backup (overrides config)
    --no-snapshot          Disable snapshots (overrides config)
    --scrub                Run integrity check after backup
    --stats                Show compression statistics
    -h, --help             Show this help

${C_GREEN}Examples:${C_NC}
    $SCRIPT_NAME                    # Standard backup
    $SCRIPT_NAME --snapshot         # Backup with snapshot
    $SCRIPT_NAME -n                 # Dry run (test)
    $SCRIPT_NAME -y --scrub         # No confirm + integrity check

EOF
    exit 0
}

# =============================================================================
# CONFIG FUNCTIONS
# =============================================================================
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    # Load all config values
    SOURCE_PATH=$(parse_yaml "source.path")
    SOURCE_LABEL=$(parse_yaml "source.label")
    [[ -z "$SOURCE_LABEL" ]] && SOURCE_LABEL="Source"

    BACKUP_PATH=$(parse_yaml "backup.path")
    BACKUP_LABEL=$(parse_yaml "backup.label")
    [[ -z "$BACKUP_LABEL" ]] && BACKUP_LABEL="Backup"

    # Directories
    DIRECTORIES=$(parse_yaml_array "directories" 2>/dev/null || echo "/")

    # Excludes
    EXCLUDES=$(parse_yaml_array "exclude" 2>/dev/null || echo "")

    # Snapshots
    SNAP_ENABLED=$(parse_yaml "snapshots.enabled")
    [[ -z "$SNAP_ENABLED" ]] && SNAP_ENABLED="false"

    SNAP_DIR=$(parse_yaml "snapshots.directory")
    [[ -z "$SNAP_DIR" ]] && SNAP_DIR=".snapshots"

    SNAP_KEEP=$(parse_yaml "snapshots.retention")
    [[ -z "$SNAP_KEEP" ]] && SNAP_KEEP=3

    SNAP_PREFIX=$(parse_yaml "snapshots.prefix")
    [[ -z "$SNAP_PREFIX" ]] && SNAP_PREFIX="backup"

    # Rsync
    RSYNC_DELETE=$(parse_yaml "rsync.delete")
    [[ -z "$RSYNC_DELETE" ]] && RSYNC_DELETE="true"

    RSYNC_PROGRESS=$(parse_yaml "rsync.progress")
    [[ -z "$RSYNC_PROGRESS" ]] && RSYNC_PROGRESS="true"

    RSYNC_COMPRESS=$(parse_yaml "rsync.compress")
    [[ -z "$RSYNC_COMPRESS" ]] && RSYNC_COMPRESS="false"

    RSYNC_ARCHIVE=$(parse_yaml "rsync.archive")
    [[ -z "$RSYNC_ARCHIVE" ]] && RSYNC_ARCHIVE="true"

    # Btrfs
    BTRFS_SCRUB=$(parse_yaml "btrfs.scrub_after_backup")
    [[ -z "$BTRFS_SCRUB" ]] && BTRFS_SCRUB="false"

    BTRFS_STATS=$(parse_yaml "btrfs.show_compression_stats")
    [[ -z "$BTRFS_STATS" ]] && BTRFS_STATS="false"

    # Logging
    LOG_FILE=$(parse_yaml "logging.file")
    [[ -z "$LOG_FILE" ]] && LOG_FILE="/var/log/backup/backup-hdd.log"
    log_open_fd

    # Safety
    CONFIRM=$(parse_yaml "safety.confirm_before_start")
    [[ -z "$CONFIRM" ]] && CONFIRM="true"

    CHECK_SPACE=$(parse_yaml "safety.check_disk_space")
    [[ -z "$CHECK_SPACE" ]] && CHECK_SPACE="true"

    DRY_RUN=$(parse_yaml "safety.dry_run")
    [[ -z "$DRY_RUN" ]] && DRY_RUN="false"

    # Validate configuration
    validate_config
}

# =============================================================================
# CONFIG VALIDATION
# =============================================================================
validate_config() {
    validation_reset

    # Required fields
    validate_required "source.path" "$SOURCE_PATH"
    validate_required "backup.path" "$BACKUP_PATH"

    # Booleans
    validate_boolean "snapshots.enabled" "$SNAP_ENABLED"
    validate_boolean "rsync.delete" "$RSYNC_DELETE"
    validate_boolean "rsync.progress" "$RSYNC_PROGRESS"
    validate_boolean "rsync.compress" "$RSYNC_COMPRESS"
    validate_boolean "rsync.archive" "$RSYNC_ARCHIVE"
    validate_boolean "btrfs.scrub_after_backup" "$BTRFS_SCRUB"
    validate_boolean "btrfs.show_compression_stats" "$BTRFS_STATS"
    validate_boolean "safety.confirm_before_start" "$CONFIRM"
    validate_boolean "safety.check_disk_space" "$CHECK_SPACE"
    validate_boolean "safety.dry_run" "$DRY_RUN"

    # Integers
    validate_integer "snapshots.retention" "$SNAP_KEEP"

    # Paths
    validate_path "source.path" "$SOURCE_PATH"
    validate_path "backup.path" "$BACKUP_PATH"
    [[ -n "$LOG_FILE" ]] && validate_path "logging.file" "$LOG_FILE"

    # Logical
    if [[ "$SNAP_ENABLED" == "true" ]] && [[ "$SNAP_KEEP" -lt 1 ]] 2>/dev/null; then
        validation_add_error "snapshots.retention should be at least 1 when snapshots are enabled"
    fi

    validation_check "$YAML_FILE"
}

validate_paths() {
    if [[ ! -d "$SOURCE_PATH" ]]; then
        log_error "Source not found: $SOURCE_PATH"
        echo "Is HDD1 mounted?"
        exit 1
    fi

    if [[ ! -d "$BACKUP_PATH" ]]; then
        log_error "Backup drive not found: $BACKUP_PATH"
        echo "Is Backup1 mounted? Use: sudo mount $BACKUP_PATH"
        exit 1
    fi

    if [[ "$SOURCE_PATH" == "$BACKUP_PATH" ]]; then
        log_error "Source and backup cannot be the same path!"
        exit 1
    fi
}

# =============================================================================
# SNAPSHOT FUNCTIONS
# =============================================================================
list_snapshots() {
    local source="$1"
    local snap_dir="$source/$SNAP_DIR"

    if [[ ! -d "$snap_dir" ]]; then
        echo "No snapshots found"
        return
    fi

    echo "Snapshots in $snap_dir:"
    find "$snap_dir" -maxdepth 1 -name "${SNAP_PREFIX}-*" 2>/dev/null | sort | while read -r snap; do
        local name
        name=$(basename "$snap")
        local size
        size=$(btrfs subvolume show "$snap" 2>/dev/null | grep "Total" || echo "")
        echo "  - $name $size"
    done
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================
perform_backup() {
    local source="$1"
    local dest="$2"

    log_section "Starting Backup"

    echo "Source:      $source ($SOURCE_LABEL)"
    echo "Destination: $dest ($BACKUP_LABEL)"
    echo ""

    local rsync_opts
    read -ra rsync_opts <<< "$(build_rsync_options)"

    # Add excludes
    for exclude in $EXCLUDES; do
        rsync_opts+=("--exclude=$exclude")
    done

    # Handle directories
    if [[ "$DIRECTORIES" == "/" ]] || [[ -z "$DIRECTORIES" ]]; then
        log_step "Syncing entire drive..."
        rsync "${rsync_opts[@]}" "$source/" "$dest/"
    else
        for dir in $DIRECTORIES; do
            dir="${dir#/}"

            if [[ ! -d "$source/$dir" ]]; then
                log_warn "Directory not found: $source/$dir (skipping)"
                continue
            fi

            log_step "Syncing: $dir"
            mkdir -p "$dest/$dir"
            rsync "${rsync_opts[@]}" "$source/$dir/" "$dest/$dir/"
        done
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed (no changes made)"
    else
        log_success "Backup completed successfully"
    fi
}

# =============================================================================
# DISPLAY FUNCTIONS
# =============================================================================
print_summary() {
    echo ""
    echo -e "${C_BOLD}╔════════════════════════════════════════════════════════════╗${C_NC}"
    echo -e "${C_BOLD}║              BACKUP CONFIGURATION                          ║${C_NC}"
    echo -e "${C_BOLD}╚════════════════════════════════════════════════════════════╝${C_NC}"
    echo ""
    echo -e "${C_CYAN}Source:${C_NC}      $SOURCE_PATH"
    echo -e "             $SOURCE_LABEL"
    is_mounted "$SOURCE_PATH" && echo -e "             $(get_disk_usage "$SOURCE_PATH")"
    echo ""
    echo -e "${C_CYAN}Destination:${C_NC} $BACKUP_PATH"
    echo -e "             $BACKUP_LABEL"
    is_mounted "$BACKUP_PATH" && echo -e "             $(get_disk_usage "$BACKUP_PATH")"
    echo ""
    echo -e "${C_CYAN}Directories:${C_NC} ${DIRECTORIES:-"/ (entire drive)"}"
    echo ""
    echo -e "${C_CYAN}Options:${C_NC}"
    echo "  Snapshots:    $([[ "$SNAP_ENABLED" == "true" ]] && echo "✓ Enabled (keep $SNAP_KEEP)" || echo "✗ Disabled")"
    echo "  Delete mode:  $([[ "$RSYNC_DELETE" == "true" ]] && echo "✓ Mirror (delete extra files)" || echo "✗ Additive only")"
    echo "  Dry run:      $([[ "$DRY_RUN" == "true" ]] && echo "✓ Yes (no changes)" || echo "✗ No")"
    echo "  Scrub:        $([[ "$BTRFS_SCRUB" == "true" ]] && echo "✓ After backup" || echo "✗ Skip")"
    echo "  Log file:     ${LOG_FILE:-"(console only)"}"
    echo ""

    if [[ "$RSYNC_DELETE" == "true" ]]; then
        echo -e "${C_YELLOW}⚠ WARNING: Files on backup not in source will be DELETED${C_NC}"
        echo ""
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local config_file="$DEFAULT_CONFIG_FILE"
    local force_snapshot=""
    local force_scrub=false
    local force_stats=false
    local skip_confirm=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                skip_confirm=true
                shift
                ;;
            --snapshot)
                force_snapshot="true"
                shift
                ;;
            --no-snapshot)
                force_snapshot="false"
                shift
                ;;
            --scrub)
                force_scrub=true
                shift
                ;;
            --stats)
                force_stats=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Check dependencies
    check_deps "yq" "rsync"

    # Load config
    load_config "$config_file"

    # Apply overrides
    [[ -n "$force_snapshot" ]] && SNAP_ENABLED="$force_snapshot"
    [[ "$force_scrub" == "true" ]] && BTRFS_SCRUB="true"
    [[ "$force_stats" == "true" ]] && BTRFS_STATS="true"

    # Cleanup on exit
    trap 'log_close_fd' EXIT

    # Validate
    validate_paths

    # Print summary
    print_summary

    # Check disk space
    if [[ "$CHECK_SPACE" == "true" ]]; then
        check_disk_space "$SOURCE_PATH" "$BACKUP_PATH"
        echo ""
    fi

    # Confirm
    if [[ "$CONFIRM" == "true" ]] && [[ "$skip_confirm" != "true" ]]; then
        local response
        read -rp "Proceed with backup? [y/N] " response
        if [[ ! "$response" =~ ^[yY]$ ]]; then
            log_warn "Backup cancelled"
            exit 0
        fi
    fi

    # Create snapshot if enabled
    if [[ "$SNAP_ENABLED" == "true" ]]; then
        log_section "Creating Snapshot"
        btrfs_create_snapshot "$SOURCE_PATH" "$SNAP_DIR" "$SNAP_PREFIX"
        btrfs_rotate_snapshots "$SOURCE_PATH/$SNAP_DIR" "$SNAP_PREFIX" "$SNAP_KEEP"
    fi

    # Perform backup
    perform_backup "$SOURCE_PATH" "$BACKUP_PATH"

    # Run scrub if enabled
    if [[ "$BTRFS_SCRUB" == "true" ]]; then
        log_section "Integrity Check"
        btrfs_run_scrub "$BACKUP_PATH" "$BACKUP_LABEL"
    fi

    # Show stats if enabled
    if [[ "$BTRFS_STATS" == "true" ]]; then
        log_section "Compression Statistics"
        btrfs_show_stats "$SOURCE_PATH" "$SOURCE_LABEL"
        btrfs_show_stats "$BACKUP_PATH" "$BACKUP_LABEL"
    fi

    # Final summary
    log_section "Backup Complete"
    echo "Source:      $(get_disk_usage "$SOURCE_PATH")"
    echo "Destination: $(get_disk_usage "$BACKUP_PATH")"

    if [[ "$SNAP_ENABLED" == "true" ]]; then
        echo ""
        list_snapshots "$SOURCE_PATH"
    fi

    echo ""
    log_success "All done!"

    send_notification "success" \
        "HDD Backup completed" \
        "$SOURCE_LABEL → $BACKUP_LABEL backup completed successfully"
}

main "$@"
