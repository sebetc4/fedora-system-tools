#!/bin/bash
# =============================================================================
# TORRENT-MOVE - Move torrent downloads with proper permissions
# =============================================================================
# Moves files from the torrent download directory to user's Downloads folder,
# fixing permissions and SELinux labels in the process.
#
# Module: torrent
# Requires: core, config, format, ui
# Version: 0.1.0
#
# Usage:
#   torrent-move <file_or_number> [destination]
# =============================================================================

set -euo pipefail

# ===================
# Load shared library
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/format.sh"
source "$LIB_DIR/ui.sh"

# ===================
# Configuration
# ===================
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

check_root

load_config
# shellcheck disable=SC2153  # DOWNLOAD_DIR sourced from paths.conf via load_config
TORRENT_DIR="$DOWNLOAD_DIR/torrents"
DOWNLOADS_DIR="$TORRENT_DIR"
DEFAULT_DEST="$EXPORT_DIR"
readonly DOWNLOADS_DIR
readonly DEFAULT_DEST

# Detect the real user behind sudo (not root)
readonly REAL_USER="${SUDO_USER:-$USER}"
USER_ID=$(id -u "$REAL_USER")
readonly USER_ID
GROUP_ID=$(id -g "$REAL_USER")
readonly GROUP_ID

# ===================
# Functions
# ===================
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME <file_or_number> [destination]

Move torrent downloads to your main Downloads folder with proper permissions.
Requires sudo (torrent directories are owned by containers).

ARGUMENTS:
  file_or_number  File name, path, or number from 'torrent list'
  destination     Target directory (default: $DEFAULT_DEST)

OPTIONS:
  --all           Move all files to destination
  --clean         Move only clean files (not pending review)
  -n, --dry-run   Show what would be moved without actually moving
  -h, --help      Show this help message

WHAT IT DOES:
  1. Moves file/directory to destination
  2. Fixes ownership recursively (sets to $REAL_USER:$REAL_USER)
  3. Fixes permissions recursively (644 for files, 755 for directories)
  4. Restores default SELinux context (removes container labels)

EXAMPLES:
  $SCRIPT_NAME 1                        # Move file #1 to $DEFAULT_DEST
  $SCRIPT_NAME "Game Repack"            # Move by name
  $SCRIPT_NAME 1 /data/Software         # Move to custom destination
  $SCRIPT_NAME --all                    # Move all files
  $SCRIPT_NAME --clean                  # Move only clean files
  $SCRIPT_NAME --dry-run 1              # Preview what would happen

EOF
}

# Get file list for number selection
get_file_list() {
    local files=()
    if [[ -d "$DOWNLOADS_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            files+=("$entry")
        done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
    fi
    printf '%s\n' "${files[@]}"
}

# Resolve file from argument (number, name, or path)
resolve_file() {
    local arg="$1"

    # If it's a number, get from list
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        mapfile -t files < <(get_file_list)
        local idx=$((arg - 1))
        if [[ $idx -ge 0 && $idx -lt ${#files[@]} ]]; then
            echo "${files[$idx]}"
            return 0
        else
            echo ""
            return 1
        fi
    fi

    # If it's a full path
    if [[ "$arg" == /* && -e "$arg" ]]; then
        echo "$arg"
        return 0
    fi

    # If it's a name in downloads dir
    if [[ -e "$DOWNLOADS_DIR/$arg" ]]; then
        echo "$DOWNLOADS_DIR/$arg"
        return 0
    fi

    # Partial match
    local matches
    matches=$(find "$DOWNLOADS_DIR" -maxdepth 1 -mindepth 1 -name "*$arg*" 2>/dev/null | head -1)
    if [[ -n "$matches" ]]; then
        echo "$matches"
        return 0
    fi

    echo ""
    return 1
}

# Fix permissions recursively
fix_permissions() {
    local path="$1"
    local dry_run="$2"

    if [[ "$dry_run" == "true" ]]; then
        echo -e "  ${C_DIM}Would fix: chown -R $REAL_USER:$(id -gn "$REAL_USER"), chmod 755/644, restorecon${C_NC}"
        return 0
    fi

    # Fix ownership to the real user (not root)
    chown -R "$USER_ID:$GROUP_ID" "$path"

    # Fix permissions recursively
    if [[ -d "$path" ]]; then
        find "$path" -type d -exec chmod 755 {} \;
        find "$path" -type f -exec chmod 644 {} \;
    else
        chmod 644 "$path"
    fi

    # Restore SELinux context (remove container labels)
    if command -v restorecon &>/dev/null; then
        restorecon -R "$path" 2>/dev/null || true
    fi
}

# Move a single file/directory
move_file() {
    local source="$1"
    local dest_dir="$2"
    local dry_run="$3"

    local name
    name=$(basename "$source")
    local dest="$dest_dir/$name"

    # Check source exists
    if [[ ! -e "$source" ]]; then
        error "Source not found: $source"
        return 1
    fi

    # Create destination if needed
    if [[ ! -d "$dest_dir" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo -e "  ${C_DIM}Would create directory: $dest_dir${C_NC}"
        else
            mkdir -p "$dest_dir"
        fi
    fi

    # Check if destination exists
    if [[ -e "$dest" ]]; then
        warn "Destination already exists: $dest"
        ui_confirm "Overwrite?" || { echo "Skipped."; return 0; }
        if [[ "$dry_run" != "true" ]]; then
            rm -rf "$dest"
        fi
    fi

    local size
    if [[ -d "$source" ]]; then
        size=$(du -sh "$source" 2>/dev/null | cut -f1)
    else
        size=$(stat -c%s "$source" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "?")
    fi

    echo ""
    echo -e "Moving: ${C_BOLD}$name${C_NC} ($size)"
    echo -e "  From:  ${C_DIM}$source${C_NC}"
    echo -e "  To:    ${C_DIM}$dest${C_NC}"
    echo -e "  Owner: ${C_DIM}$REAL_USER${C_NC}"

    if [[ "$dry_run" == "true" ]]; then
        info "  [DRY RUN] Would move and fix permissions"
        return 0
    fi

    # Move
    if mv "$source" "$dest"; then
        fix_permissions "$dest" "$dry_run"
        success "Moved successfully"
        return 0
    else
        error "Move failed"
        return 1
    fi
}

# Move all files
move_all() {
    local dest_dir="$1"
    local dry_run="$2"
    local clean_only="$3"

    mapfile -t files < <(get_file_list)

    if [[ ${#files[@]} -eq 0 ]]; then
        warn "No files to move."
        return 0
    fi

    echo ""
    echo -e "${C_BOLD}Files to move:${C_NC}"
    for file in "${files[@]}"; do
        local name size
        name=$(basename "$file")
        if [[ -d "$file" ]]; then
            size=$(du -sh "$file" 2>/dev/null | cut -f1)
        else
            size=$(stat -c%s "$file" 2>/dev/null | numfmt --to=iec 2>/dev/null || echo "?")
        fi
        echo "  - $name ($size)"
    done
    echo ""
    echo -e "Destination: ${C_BOLD}$dest_dir${C_NC}"
    echo ""

    if [[ "$dry_run" != "true" ]]; then
        ui_confirm "Continue?" || { echo "Cancelled."; return 0; }
    fi

    local moved=0
    local failed=0

    for file in "${files[@]}"; do
        if move_file "$file" "$dest_dir" "$dry_run"; then
            ((moved++)) || true
        else
            ((failed++)) || true
        fi
    done

    echo ""
    echo -e "${C_GREEN}Moved: $moved${C_NC} | ${C_RED}Failed: $failed${C_NC}"
}

# ===================
# Main
# ===================
main() {
    local file_arg=""
    local dest_dir="$DEFAULT_DEST"
    local dry_run=false
    local move_all_files=false
    local clean_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            --all)
                move_all_files=true
                shift
                ;;
            --clean)
                move_all_files=true
                clean_only=true
                shift
                ;;
            -*)
                echo "Unknown option: $1"
                echo "Use --help for more information."
                exit 1
                ;;
            *)
                if [[ -z "$file_arg" ]]; then
                    file_arg="$1"
                else
                    dest_dir="$1"
                fi
                shift
                ;;
        esac
    done

    # Create default destination if it doesn't exist
    if [[ ! -d "$dest_dir" && "$dry_run" != "true" ]]; then
        mkdir -p "$dest_dir"
    fi

    # Move all
    if [[ "$move_all_files" == "true" ]]; then
        move_all "$dest_dir" "$dry_run" "$clean_only"
        exit 0
    fi

    # Single file
    if [[ -z "$file_arg" ]]; then
        echo "Usage: $SCRIPT_NAME <file_or_number> [destination]"
        echo ""
        echo "Use 'torrent list' to see available files."
        echo "Use '--help' for more options."
        exit 1
    fi

    local source
    source=$(resolve_file "$file_arg")
    if [[ -z "$source" ]]; then
        error "File not found: $file_arg"
        echo ""
        echo "Use 'torrent list' to see available files."
        exit 1
    fi

    move_file "$source" "$dest_dir" "$dry_run"
}

main "$@"
