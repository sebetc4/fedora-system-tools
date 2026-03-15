#!/bin/bash
# shellcheck disable=SC2317,SC2329
# =============================================================================
# BACKUP-HDD-BOTH - Split backup to two drives
# =============================================================================
# Performs backup from source HDD to two backup drives with different
# folder selections per drive.
#
# Module: backup
# Requires: core, log, yaml, validate, backup
# Version: 0.1.0
#
# Usage:
#   sudo backup-hdd-both [OPTIONS]
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
# LOCK FILE
# =============================================================================
readonly LOCK_FILE="/run/lock/backup-hdd-both.lock"
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
readonly DEFAULT_CONFIG_FILE="$REAL_HOME/.config/backup/hdd-both.yml"

# Logger tag for notify-daemon integration
readonly LOG_TAG="notify-backup-hdd-both"

# Global config variables
# shellcheck disable=SC2034  # used by log.sh
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"
TARGET_DRIVE="both"
OVERRIDE_SNAPSHOT=""

# =============================================================================
# NOTIFICATIONS (via notify-daemon / logger)
# =============================================================================
# Filtering is handled by notify-daemon based on the tag's level in levels.conf.
# Use: notify-manage level notify-backup-hdd-both [all|important|none]
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
${C_BOLD}BTRFS HDD Split Backup Script v${VERSION}${C_NC}

Backup different folders from source to two separate backup drives.

${C_GREEN}Usage:${C_NC}
    $SCRIPT_NAME [options]

${C_GREEN}Options:${C_NC}
    -c, --config <file>    Config file (default: $DEFAULT_CONFIG_FILE)
    -d, --drive <num>      Backup to specific drive: 1, 2, or both (default: both)
    -n, --dry-run          Simulate without making changes
    -y, --yes              Skip confirmation prompts
    --snapshot             Create snapshot before backup (overrides config)
    --no-snapshot          Disable snapshots (overrides config)
    --scrub                Run integrity check after backup
    --stats                Show compression statistics
    -h, --help             Show this help

${C_GREEN}Examples:${C_NC}
    $SCRIPT_NAME                    # Backup to both drives
    $SCRIPT_NAME -d 1               # Backup to drive 1 only
    $SCRIPT_NAME -d 2               # Backup to drive 2 only
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

    # Drive 1
    BACKUP1_PATH=$(parse_yaml "backup_drive_1.path")
    BACKUP1_LABEL=$(parse_yaml "backup_drive_1.label")
    [[ -z "$BACKUP1_LABEL" ]] && BACKUP1_LABEL="Backup1"

    # Drive 2
    BACKUP2_PATH=$(parse_yaml "backup_drive_2.path")
    BACKUP2_LABEL=$(parse_yaml "backup_drive_2.label")
    [[ -z "$BACKUP2_LABEL" ]] && BACKUP2_LABEL="Backup2"

    # Excludes (global)
    EXCLUDES=$(parse_yaml_array "exclude" 2>/dev/null || echo "")

    # Snapshots (per drive)
    SNAP1_ENABLED=$(parse_yaml "backup_drive_1.snapshots.enabled")
    [[ -z "$SNAP1_ENABLED" ]] && SNAP1_ENABLED="false"

    SNAP1_DIR=$(parse_yaml "backup_drive_1.snapshots.directory")
    [[ -z "$SNAP1_DIR" ]] && SNAP1_DIR=".snapshots"

    SNAP1_KEEP=$(parse_yaml "backup_drive_1.snapshots.retention")
    [[ -z "$SNAP1_KEEP" ]] && SNAP1_KEEP=3

    SNAP1_PREFIX=$(parse_yaml "backup_drive_1.snapshots.prefix")
    [[ -z "$SNAP1_PREFIX" ]] && SNAP1_PREFIX="backup"

    SNAP2_ENABLED=$(parse_yaml "backup_drive_2.snapshots.enabled")
    [[ -z "$SNAP2_ENABLED" ]] && SNAP2_ENABLED="false"

    SNAP2_DIR=$(parse_yaml "backup_drive_2.snapshots.directory")
    [[ -z "$SNAP2_DIR" ]] && SNAP2_DIR=".snapshots"

    SNAP2_KEEP=$(parse_yaml "backup_drive_2.snapshots.retention")
    [[ -z "$SNAP2_KEEP" ]] && SNAP2_KEEP=3

    SNAP2_PREFIX=$(parse_yaml "backup_drive_2.snapshots.prefix")
    [[ -z "$SNAP2_PREFIX" ]] && SNAP2_PREFIX="backup"

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
    [[ -z "$LOG_FILE" ]] && LOG_FILE="/var/log/backup/backup-hdd-both.log"
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
    validate_required "backup_drive_1.path" "$BACKUP1_PATH"
    validate_required "backup_drive_2.path" "$BACKUP2_PATH"

    # Booleans
    validate_boolean "backup_drive_1.snapshots.enabled" "$SNAP1_ENABLED"
    validate_boolean "backup_drive_2.snapshots.enabled" "$SNAP2_ENABLED"
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
    validate_integer "backup_drive_1.snapshots.retention" "$SNAP1_KEEP"
    validate_integer "backup_drive_2.snapshots.retention" "$SNAP2_KEEP"

    # Paths
    validate_path "source.path" "$SOURCE_PATH"
    validate_path "backup_drive_1.path" "$BACKUP1_PATH"
    validate_path "backup_drive_2.path" "$BACKUP2_PATH"
    [[ -n "$LOG_FILE" ]] && validate_path "logging.file" "$LOG_FILE"

    # Logical
    if [[ "$SOURCE_PATH" == "$BACKUP1_PATH" ]] || [[ "$SOURCE_PATH" == "$BACKUP2_PATH" ]]; then
        validation_add_error "source.path cannot be the same as backup paths"
    fi
    if [[ "$BACKUP1_PATH" == "$BACKUP2_PATH" ]]; then
        validation_add_error "backup_drive_1.path and backup_drive_2.path cannot be the same"
    fi

    validation_check "$YAML_FILE"
}

validate_paths() {
    if [[ ! -d "$SOURCE_PATH" ]]; then
        log_error "Source not found: $SOURCE_PATH"
        echo "Is the source drive mounted?"
        exit 1
    fi

    if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        if [[ ! -d "$BACKUP1_PATH" ]]; then
            log_error "Backup drive 1 not found: $BACKUP1_PATH"
            echo "Is $BACKUP1_LABEL mounted? Use: sudo mount $BACKUP1_PATH"
            exit 1
        fi
    fi

    if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        if [[ ! -d "$BACKUP2_PATH" ]]; then
            log_error "Backup drive 2 not found: $BACKUP2_PATH"
            echo "Is $BACKUP2_LABEL mounted? Use: sudo mount $BACKUP2_PATH"
            exit 1
        fi
    fi
}

# =============================================================================
# FOLDER PARSING
# =============================================================================
get_drive_folders() {
    local drive_num="$1"
    local folders_key="backup_drive_${drive_num}.folders"

    local count
    count=$(yq e "${folders_key} | length" "$YAML_FILE" 2>/dev/null)

    if [[ "$count" == "null" ]] || [[ -z "$count" ]] || [[ "$count" -eq 0 ]]; then
        echo ""
        return
    fi

    for ((i=0; i<count; i++)); do
        local path
        path=$(yq e "${folders_key}[$i].path" "$YAML_FILE" 2>/dev/null)

        if [[ "$path" != "null" ]] && [[ -n "$path" ]]; then
            local subfolder_count
            subfolder_count=$(yq e "${folders_key}[$i].subfolders | length" "$YAML_FILE" 2>/dev/null)

            if [[ "$subfolder_count" != "null" ]] && [[ -n "$subfolder_count" ]] && [[ "$subfolder_count" -gt 0 ]]; then
                for ((j=0; j<subfolder_count; j++)); do
                    local subfolder
                    subfolder=$(yq e "${folders_key}[$i].subfolders[$j]" "$YAML_FILE" 2>/dev/null)
                    if [[ "$subfolder" != "null" ]] && [[ -n "$subfolder" ]]; then
                        echo "${path}/${subfolder}"
                    fi
                done
            else
                echo "$path"
            fi
        fi
    done
}

# =============================================================================
# BACKUP FUNCTIONS
# =============================================================================
backup_to_drive() {
    local drive_num="$1"
    local backup_path backup_label snap_enabled snap_dir snap_prefix snap_keep

    if [[ "$drive_num" == "1" ]]; then
        backup_path="$BACKUP1_PATH"
        backup_label="$BACKUP1_LABEL"
        snap_enabled="$SNAP1_ENABLED"
        snap_dir="$SNAP1_DIR"
        snap_prefix="$SNAP1_PREFIX"
        snap_keep="$SNAP1_KEEP"
    else
        backup_path="$BACKUP2_PATH"
        backup_label="$BACKUP2_LABEL"
        snap_enabled="$SNAP2_ENABLED"
        snap_dir="$SNAP2_DIR"
        snap_prefix="$SNAP2_PREFIX"
        snap_keep="$SNAP2_KEEP"
    fi

    log_section "BACKUP TO DRIVE $drive_num: $backup_label"

    # Create snapshot if enabled
    if [[ "$snap_enabled" == "true" ]]; then
        btrfs_create_snapshot "$backup_path" "$snap_dir" "$snap_prefix"
        btrfs_rotate_snapshots "$backup_path/$snap_dir" "$snap_prefix" "$snap_keep"
    fi

    # Get folders to backup for this drive
    local folders
    folders=$(get_drive_folders "$drive_num")

    if [[ -z "$folders" ]]; then
        log_warn "No folders configured for drive $drive_num, skipping"
        return
    fi

    # Build rsync options
    local rsync_opts
    rsync_opts=$(build_rsync_options)
    rsync_opts+=" --stats"
    local exclude_args
    exclude_args=$(build_exclude_args "$EXCLUDES")

    # Backup each folder
    while IFS= read -r folder; do
        local src="${SOURCE_PATH}/${folder}/"
        local dst="${backup_path}/${folder}/"

        if [[ ! -d "$src" ]]; then
            log_warn "Source folder not found, skipping: $src"
            continue
        fi

        log_step "Syncing: $folder"

        mkdir -p "$dst"

        # shellcheck disable=SC2086  # intentional word-splitting
        eval rsync $rsync_opts $exclude_args "$src" "$dst"

    done <<< "$folders"

    log_success "Drive $drive_num backup complete"
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
            YAML_FILE="$2"
            shift 2
            ;;
        -d|--drive)
            TARGET_DRIVE="$2"
            if [[ ! "$TARGET_DRIVE" =~ ^(1|2|both)$ ]]; then
                log_error "Invalid drive: $TARGET_DRIVE (must be 1, 2, or both)"
                exit 1
            fi
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN="true"
            shift
            ;;
        -y|--yes)
            CONFIRM="false"
            shift
            ;;
        --snapshot)
            OVERRIDE_SNAPSHOT="true"
            shift
            ;;
        --no-snapshot)
            OVERRIDE_SNAPSHOT="false"
            shift
            ;;
        --scrub)
            BTRFS_SCRUB="true"
            shift
            ;;
        --stats)
            BTRFS_STATS="true"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Check dependencies
check_deps "yq" "rsync"

# Load configuration
load_config "${YAML_FILE:-$DEFAULT_CONFIG_FILE}"

# Apply snapshot override if specified
if [[ -n "$OVERRIDE_SNAPSHOT" ]]; then
    SNAP1_ENABLED="$OVERRIDE_SNAPSHOT"
    SNAP2_ENABLED="$OVERRIDE_SNAPSHOT"
fi

# Cleanup on exit
trap 'log_close_fd' EXIT

# Display banner
echo -e "${C_BOLD}${C_BLUE}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        BTRFS HDD SPLIT BACKUP - TWO DRIVE SYSTEM            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${C_NC}"

log_success "Version: $VERSION"
log_success "Config: $YAML_FILE"
log_success "Target: Drive $TARGET_DRIVE"
if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_warn "DRY RUN MODE - No changes will be made"
fi
echo ""

# Validate paths
validate_paths

# Display info
log_section "CONFIGURATION"
log_success "Source: $SOURCE_PATH ($SOURCE_LABEL)"
if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    log_success "Backup Drive 1: $BACKUP1_PATH ($BACKUP1_LABEL)"
fi
if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    log_success "Backup Drive 2: $BACKUP2_PATH ($BACKUP2_LABEL)"
fi
echo ""

# Disk usage
log_section "DISK USAGE"
log_success "Source: $(get_disk_usage "$SOURCE_PATH")"
if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    log_success "Drive 1: $(get_disk_usage "$BACKUP1_PATH")"
fi
if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    log_success "Drive 2: $(get_disk_usage "$BACKUP2_PATH")"
fi
echo ""

# Confirmation
if [[ "${CONFIRM:-true}" == "true" ]] && [[ "${DRY_RUN:-false}" != "true" ]]; then
    local_response=""
    read -rp "Start backup to drive(s) $TARGET_DRIVE? [y/N] " local_response
    if [[ ! "$local_response" =~ ^[yY]$ ]]; then
        log_warn "Backup cancelled by user"
        exit 0
    fi
fi

# Execute backups
START_TIME=$(date +%s)

if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    backup_to_drive 1
fi

if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
    backup_to_drive 2
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Statistics
if [[ "${BTRFS_STATS:-false}" == "true" ]]; then
    if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        btrfs_show_stats "$BACKUP1_PATH" "$BACKUP1_LABEL"
    fi
    if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        btrfs_show_stats "$BACKUP2_PATH" "$BACKUP2_LABEL"
    fi
fi

# Scrub
if [[ "${BTRFS_SCRUB:-false}" == "true" ]]; then
    if [[ "$TARGET_DRIVE" == "1" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        btrfs_run_scrub "$BACKUP1_PATH" "$BACKUP1_LABEL"
    fi
    if [[ "$TARGET_DRIVE" == "2" ]] || [[ "$TARGET_DRIVE" == "both" ]]; then
        btrfs_run_scrub "$BACKUP2_PATH" "$BACKUP2_LABEL"
    fi
fi

# Final report
log_section "BACKUP COMPLETE"
log_success "Duration: ${DURATION}s ($(date -u -d @"${DURATION}" +"%H:%M:%S" 2>/dev/null || echo "${DURATION}s"))"
log_success "Target: Drive $TARGET_DRIVE"

send_notification "success" \
    "HDD Split Backup completed" \
    "Source → Drive $TARGET_DRIVE backup completed successfully"

echo ""
echo -e "${C_GREEN}${C_BOLD}"
cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║                   ✓  BACKUP SUCCESSFUL  ✓                   ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${C_NC}"

exit 0
