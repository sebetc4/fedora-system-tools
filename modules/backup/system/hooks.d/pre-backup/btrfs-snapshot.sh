#!/bin/bash
# =============================================================================
# BTRFS-SNAPSHOT - Pre-backup hook for versioned snapshots
# =============================================================================
# Creates versioned read-only BTRFS snapshots of the backup destination
# BEFORE rsync overwrites data. This preserves the last known-good backup
# state, ensuring recovery is possible even if rsync fails mid-transfer.
#
# Requires backup_root to be a BTRFS subvolume.
#
# Module: backup (hook)
# Requires: core, log, yaml, validate, backup
# Version: 0.1.0
#
# Usage (standalone):
#   sudo btrfs-snapshot.sh [--dry-run] [-c <custom-config>]
#
# Usage (as hook):
#   Called automatically by backup-system via hooks.pre_backup[]
#   Receives BACKUP_ROOT, BACKUP_MOUNT, DRY_RUN via environment
#   Uses config: ~/.config/backup/hooks/btrfs-snapshot.yml
#
# Options:
#   -c, --config <file>  Override default config path (optional)
#   --dry-run            Simulate (no snapshots created)
#   -h, --help           Display this help
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: btrfs-snapshot failed at line $LINENO" >&2; exit 1' ERR

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
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"

# Detect real user (when invoked via sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Default config path (hook manages its own config internally)
readonly DEFAULT_CONFIG="$REAL_HOME/.config/backup/hooks/btrfs-snapshot.yml"

# Inherit from parent script (backup-system exports these)
BACKUP_ROOT="${BACKUP_ROOT:-}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
${C_CYAN}BTRFS Snapshot Hook v${VERSION}${C_NC}

Pre-backup hook: snapshots the current backup state before rsync overwrites it.

${C_GREEN}Usage:${C_NC}
    sudo $0 [--dry-run] [-c <custom-config>]

${C_GREEN}Options:${C_NC}
    -c, --config <file>  Override default config (optional)
                         Default: ~/.config/backup/hooks/btrfs-snapshot.yml
    --dry-run            Simulate without creating snapshots
    -h, --help           Display this help

${C_GREEN}Environment (set by backup-system):${C_NC}
    BACKUP_ROOT          Backup destination root path
    DRY_RUN              true/false

EOF
}

# =============================================================================
# CONFIG
# =============================================================================
SNAPSHOT_DIR=""
SNAPSHOT_RETENTION=4
SNAPSHOT_PREFIX="backup"

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Hook config not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    SNAPSHOT_DIR=$(parse_yaml "directory")
    SNAPSHOT_RETENTION=$(parse_yaml "retention")
    SNAPSHOT_PREFIX=$(parse_yaml "prefix")

    # Defaults
    : "${SNAPSHOT_RETENTION:=4}"
    : "${SNAPSHOT_PREFIX:=backup}"
}

validate_hook_config() {
    validation_reset

    validate_required "BACKUP_ROOT (env)" "$BACKUP_ROOT"
    validate_required "directory" "$SNAPSHOT_DIR"
    validate_path "directory" "$SNAPSHOT_DIR"
    validate_integer "retention" "$SNAPSHOT_RETENTION"

    if [[ "$SNAPSHOT_RETENTION" -lt 1 ]] 2>/dev/null; then
        validation_add_error "retention must be at least 1"
    fi

    validation_check "$YAML_FILE"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
HOOK_CONFIG="$DEFAULT_CONFIG"

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                HOOK_CONFIG="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                # Accept silently (compatibility with hook engine)
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1" "exit"
                ;;
        esac
    done
}

# =============================================================================
# SNAPSHOT LOGIC
# =============================================================================
create_versioned_snapshot() {
    local date_stamp
    date_stamp=$(date +%Y-%m-%d_%H-%M-%S)

    log_section "BTRFS SNAPSHOT (VERSIONING)"

    # Check that BACKUP_ROOT is a BTRFS subvolume
    if ! btrfs subvolume show "$BACKUP_ROOT" &>/dev/null; then
        log_warn "$BACKUP_ROOT is not a BTRFS subvolume — cannot create snapshots"
        info ""
        info "To enable snapshots:"
        info "  1. Backup existing data: sudo mv $BACKUP_ROOT ${BACKUP_ROOT}-old"
        info "  2. Create subvolume: sudo btrfs subvolume create $BACKUP_ROOT"
        info "  3. Restore data: sudo rsync -aAXHv ${BACKUP_ROOT}-old/ $BACKUP_ROOT/"
        return 1
    fi

    mkdir -p "$SNAPSHOT_DIR"

    local snap_name="${SNAPSHOT_PREFIX}-${date_stamp}"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would create snapshot: $SNAPSHOT_DIR/$snap_name"
        info "[DRY RUN] Retention: $SNAPSHOT_RETENTION"
        return 0
    fi

    # Create read-only snapshot
    log "Creating readonly snapshot: $snap_name"
    if btrfs subvolume snapshot -r "$BACKUP_ROOT" "$SNAPSHOT_DIR/$snap_name" 2>&1; then
        log_success "Snapshot created: $snap_name"
    else
        log_warn "Failed to create snapshot"
        return 1
    fi

    # Rotate old snapshots
    log "Cleaning snapshots (retention: $SNAPSHOT_RETENTION)"

    local snap_count
    snap_count=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "${SNAPSHOT_PREFIX}-*" -type d 2>/dev/null | wc -l)
    info "Current snapshots: $snap_count"

    if [[ "$snap_count" -gt "$SNAPSHOT_RETENTION" ]]; then
        local to_delete=$((snap_count - SNAPSHOT_RETENTION))
        log "Deleting $to_delete old snapshot(s)..."

        find "$SNAPSHOT_DIR" -maxdepth 1 -name "${SNAPSHOT_PREFIX}-*" -type d -printf '%T@\t%p\n' \
            | sort -n | head -n "$to_delete" | cut -f2 \
            | while read -r old_snapshot; do
                log "Deleting: $(basename "$old_snapshot")"
                btrfs subvolume delete "$old_snapshot" 2>&1 || log_warn "Failed to delete: $old_snapshot"
            done

        log_success "Cleanup completed"
    else
        info "Retention OK, no cleanup necessary"
    fi

    # Summary
    local final_count
    final_count=$(find "$SNAPSHOT_DIR" -maxdepth 1 -name "${SNAPSHOT_PREFIX}-*" -type d 2>/dev/null | wc -l)
    info "Available backup snapshots: $final_count"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_arguments "$@"
    load_config "$HOOK_CONFIG"
    validate_hook_config

    create_versioned_snapshot
}

main "$@"
