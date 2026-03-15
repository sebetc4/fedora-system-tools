#!/bin/bash
# =============================================================================
# BTRFS-SAVE-STRUCTURE - Pre-backup hook for BTRFS documentation
# =============================================================================
# Saves BTRFS subvolume structure, fstab, file attributes, system info,
# and generates a subvolume recreation script for disaster recovery.
#
# This hook is specific to BTRFS systems. It documents the filesystem
# layout so it can be recreated during restoration.
#
# Module: backup (hook)
# Requires: core, log, yaml, validate
# Version: 0.1.0
#
# Usage (standalone):
#   sudo btrfs-save-structure.sh [--dry-run] [-c <custom-config>]
#
# Usage (as hook):
#   Called automatically by backup-system via hooks.pre_backup[]
#   Receives BACKUP_ROOT, BACKUP_MOUNT, DRY_RUN via environment
#   Uses config: ~/.config/backup/hooks/btrfs-save-structure.yml
#
# Options:
#   -c, --config <file>  Override default config path (optional)
#   --dry-run            Simulate (no files written)
#   -h, --help           Display this help
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: btrfs-save-structure failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"

# Detect real user (when invoked via sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Default config path (hook manages its own config internally)
readonly DEFAULT_CONFIG="$REAL_HOME/.config/backup/hooks/btrfs-save-structure.yml"

# Inherit from parent script (backup-system exports these)
BACKUP_ROOT="${BACKUP_ROOT:-}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
${C_CYAN}BTRFS Save Structure Hook v${VERSION}${C_NC}

Pre-backup hook: saves BTRFS subvolume structure for disaster recovery.

${C_GREEN}Usage:${C_NC}
    sudo $0 [--dry-run] [-c <custom-config>]

${C_GREEN}Options:${C_NC}
    -c, --config <file>  Override default config (optional)
                         Default: ~/.config/backup/hooks/btrfs-save-structure.yml
    --dry-run            Simulate without writing files
    -h, --help           Display this help

${C_GREEN}Environment (set by backup-system):${C_NC}
    BACKUP_ROOT          Backup destination root path
    DRY_RUN              true/false

EOF
}

# =============================================================================
# CONFIG
# =============================================================================
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Hook config not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    OUTPUT_DIR=$(parse_yaml "output_dir")

    # Defaults
    : "${OUTPUT_DIR:=btrfs-structure}"
}

validate_hook_config() {
    validation_reset

    validate_required "BACKUP_ROOT (env)" "$BACKUP_ROOT"
    validate_required "output_dir" "$OUTPUT_DIR"

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
# SAVE BTRFS STRUCTURE
# =============================================================================
save_subvolumes() {
    local output_path="$1"

    log "Saving subvolume list..."
    btrfs subvolume list / > "$output_path/subvolumes-list.txt" 2>&1 || log_warn "Cannot list subvolumes"
}

save_fstab() {
    local output_path="$1"

    log "Saving fstab..."
    cp /etc/fstab "$output_path/fstab.backup"
}

save_attributes() {
    local output_path="$1"

    log "Saving BTRFS attributes..."

    local attr_count
    attr_count=$(parse_yaml_count "attribute_paths")

    for ((i=0; i<attr_count; i++)); do
        local attr_path
        attr_path=$(yq e ".attribute_paths[$i]" "$YAML_FILE" 2>/dev/null)

        if [[ -d "$attr_path" ]]; then
            local attr_file
            attr_file="$output_path/$(echo "$attr_path" | tr '/' '-' | sed 's/^-//')-attributes.txt"
            lsattr -d "$attr_path" > "$attr_file" 2>/dev/null || true
        fi
    done
}

save_system_uuids() {
    local output_path="$1"

    log "Saving system UUIDs..."
    blkid > "$output_path/blkid.txt"

    log "Saving current mount options..."
    mount | grep btrfs > "$output_path/current-mounts.txt" || true
}

# =============================================================================
# ADDITIONAL DISKS DOCUMENTATION
# =============================================================================
document_additional_disks() {
    local output_path="$1"

    local disk_count
    disk_count=$(parse_yaml_count "additional_disks")
    [[ "$disk_count" -eq 0 ]] && return 0

    log "Documenting additional disks..."

    {
        echo "========================================"
        echo "ADDITIONAL DISKS (not backed up)"
        echo "========================================"
        echo "Generated on: $(date)"
        echo ""
        echo "These disks are NOT backed up by the main backup script."
        echo "They require separate management."
        echo ""
    } > "$output_path/additional-disks-info.txt"

    for ((i=0; i<disk_count; i++)); do
        local mount_point description
        mount_point=$(parse_yaml_index "additional_disks" "$i" "mount_point")
        description=$(parse_yaml_index "additional_disks" "$i" "description")

        {
            echo "========================================"
            echo "$mount_point DISK — $description"
            echo "========================================"
        } >> "$output_path/additional-disks-info.txt"

        if mountpoint -q "$mount_point" 2>/dev/null; then
            local dev uuid disk_size disk_used
            dev=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || echo "unknown")
            uuid=$(findmnt -n -o UUID "$mount_point" 2>/dev/null || echo "unknown")
            disk_size=$(df -h "$mount_point" | tail -1 | awk '{print $2}')
            disk_used=$(df -h "$mount_point" | tail -1 | awk '{print $3}')

            cat >> "$output_path/additional-disks-info.txt" << DISK_MOUNTED
Status  : Mounted
Device  : $dev
UUID    : $uuid
Size    : $disk_size
Used    : $disk_used

Fstab entry:
$(grep "$mount_point" /etc/fstab 2>/dev/null || echo "None")

Mount options:
$(mount | grep "$mount_point" 2>/dev/null || echo "None")

Content (top 10):
$(du -sh "$mount_point"/* 2>/dev/null | sort -hr | head -10 || echo "Empty")

RESTORATION:
1. Connect the same disk (UUID: $uuid)
2. The restored fstab will mount it automatically
3. Verify: sudo mount -a && df -h | grep ${mount_point##*/}

DISK_MOUNTED
        else
            cat >> "$output_path/additional-disks-info.txt" << DISK_NOT_MOUNTED
Status : Not mounted or doesn't exist

If $mount_point existed:
- Check connection: lsblk
- Check UUID: sudo blkid | grep btrfs
- Mount: sudo mount $mount_point

DISK_NOT_MOUNTED
        fi
    done

    # All BTRFS disks summary
    {
        echo "========================================"
        echo "ALL BTRFS DISKS"
        echo "========================================"
    } >> "$output_path/additional-disks-info.txt"
    blkid | grep btrfs >> "$output_path/additional-disks-info.txt" 2>/dev/null || echo "No BTRFS disk detected" >> "$output_path/additional-disks-info.txt"
}

# =============================================================================
# GENERATE RECREATION SCRIPT
# =============================================================================
generate_recreate_script() {
    local output_path="$1"

    log "Generating subvolume recreation script..."

    local subvol_count
    subvol_count=$(parse_yaml_count "subvolumes")
    [[ "$subvol_count" -eq 0 ]] && return 0

    local script_file="$output_path/recreate-subvolumes.sh"

    cat > "$script_file" << 'SCRIPT_HEADER'
#!/bin/bash
# BTRFS subvolume recreation script
# Automatically generated during backup

set -e

BTRFS_ROOT="/mnt/btrfs-root"

echo "========================================="
echo "BTRFS Subvolume Recreation"
echo "========================================="

if [ ! -d "$BTRFS_ROOT" ] || ! mountpoint -q "$BTRFS_ROOT"; then
    echo "ERROR: Mount the BTRFS root first:"
    echo "  sudo mount /dev/mapper/luks-XXXX -o subvolid=5 /mnt/btrfs-root"
    exit 1
fi

echo "Creating subvolumes..."
SCRIPT_HEADER

    # Add subvolume creation commands from config
    for ((i=0; i<subvol_count; i++)); do
        local sv_name sv_chattr
        sv_name=$(parse_yaml_index "subvolumes" "$i" "name")
        sv_chattr=$(parse_yaml_index "subvolumes" "$i" "chattr")

        {
            echo "btrfs subvolume create \"\$BTRFS_ROOT/$sv_name\""

            if [[ -n "$sv_chattr" ]]; then
                echo ""
                echo "echo \"Applying chattr $sv_chattr to /$sv_name...\""
                echo "chattr $sv_chattr \"\$BTRFS_ROOT/$sv_name\""
            fi
        } >> "$script_file"
    done

    cat >> "$script_file" << 'SCRIPT_FOOTER'

echo ""
echo "Subvolumes recreated!"
btrfs subvolume list "$BTRFS_ROOT"
SCRIPT_FOOTER

    chmod +x "$script_file"
}

# =============================================================================
# SAVE SYSTEM INFO
# =============================================================================
save_system_info() {
    local output_path="$1"

    log "Saving system information..."

    cat > "$output_path/system-info.txt" << SYSINFO
========================================
SYSTEM INFORMATION
========================================
Date     : $(date)
Hostname : $(hostname)
Kernel   : $(uname -r)
OS       : $(cat /etc/fedora-release 2>/dev/null || echo "Unknown")

DISKS:
$(lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE)

MEMORY:
$(free -h)

BTRFS SUBVOLUMES:
$(btrfs subvolume list / 2>/dev/null || echo "Error")
SYSINFO
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_arguments "$@"
    load_config "$HOOK_CONFIG"
    validate_hook_config

    local output_path="$BACKUP_ROOT/$OUTPUT_DIR"

    log_section "SAVE BTRFS STRUCTURE"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would save BTRFS structure to: $output_path"
        info "[DRY RUN] Attribute paths: $(parse_yaml_count "attribute_paths")"
        info "[DRY RUN] Subvolumes: $(parse_yaml_count "subvolumes")"
        info "[DRY RUN] Additional disks: $(parse_yaml_count "additional_disks")"
        return 0
    fi

    mkdir -p "$output_path"

    save_subvolumes "$output_path"
    save_fstab "$output_path"
    save_attributes "$output_path"
    save_system_uuids "$output_path"
    document_additional_disks "$output_path"
    generate_recreate_script "$output_path"
    save_system_info "$output_path"

    log_success "BTRFS structure saved to $output_path"
}

main "$@"
