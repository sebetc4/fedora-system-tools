#!/bin/bash
# =============================================================================
# QUARANTINE - Universal quarantine manager
# =============================================================================
# Manage quarantined files from all sources (torrents, downloads, etc.)
# Provides inspection, VirusTotal analysis, restore/delete operations, and
# state tracking with original path for reliable restore.
# Uses shared lib for colors, messages, formatting, and interactive UI (Gum).
#
# REQUIRES ROOT: This script handles potentially infected files and must run
# with elevated privileges (except --help and --version).
#
# Module: clamav
# Requires: core, format, ui, quarantine-state
# Version: 0.1.0
#
# Usage:
#   sudo quarantine                      # Interactive mode (recommended)
#   sudo quarantine list [--pending|--confirmed]
#   sudo quarantine inspect <num>        # Show file details and state info
#   sudo quarantine vt <num>             # Check file on VirusTotal
#   sudo quarantine accept <num> [dest]  # Restore file to custom or original location
#   sudo quarantine restore <num>        # Restore file to original location
#   sudo quarantine delete <num>         # Permanently delete file
#   sudo quarantine confirm <num>        # Mark as confirmed quarantine
#   sudo quarantine purge                # Delete all confirmed quarantine files
#
# Exit codes: 0=success, 1=error
# =============================================================================

set -euo pipefail

# ===================
# Shared library
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/format.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/quarantine-state.sh"

# ===================
# Configuration
# ===================
readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly QUARANTINE_DIR="/var/quarantine"
readonly LOG_DIR="/var/log/clamav"
readonly VT_API_KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/virustotal_api_key"

# Use paths.conf if available, otherwise detect via xdg-user-dir
if [[ -f "${PATHS_CONF:-/etc/system-scripts/paths.conf}" ]]; then
    # shellcheck source=/dev/null
    source "${PATHS_CONF:-/etc/system-scripts/paths.conf}"
    DEFAULT_RESTORE_DIR="${DOWNLOAD_DIR:-$(xdg-user-dir DOWNLOAD)}"
else
    DEFAULT_RESTORE_DIR="$(xdg-user-dir DOWNLOAD)"
fi
readonly DEFAULT_RESTORE_DIR

# ===================
# Functions
# ===================
ensure_directories() {
    mkdir -p "$QUARANTINE_DIR"
    chmod 700 "$QUARANTINE_DIR"
}

# Build array of quarantined files
# Format: STATUS:PATH where STATUS is P (pending), C (confirmed), or U (unknown/untracked)
declare -a FILE_LIST=()

build_file_list() {
    local filter="${1:-all}"  # all, pending, confirmed
    FILE_LIST=()

    if [[ ! -d "$QUARANTINE_DIR" ]]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        [[ -f "$file" ]] || continue
        local filename
        filename=$(basename "$file")

        # Look up status from state file
        local status="U"
        local state_line
        if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
            local state_status
            state_status=$(echo "$state_line" | cut -d'|' -f5)
            case "$state_status" in
                pending)   status="P" ;;
                confirmed) status="C" ;;
                *)         status="U" ;;
            esac
        fi

        # Apply filter
        case "$filter" in
            pending)   [[ "$status" == "P" ]] && FILE_LIST+=("$status:$file") ;;
            confirmed) [[ "$status" == "C" ]] && FILE_LIST+=("$status:$file") ;;
            all)       FILE_LIST+=("$status:$file") ;;
        esac
    done < <(find "$QUARANTINE_DIR" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
}

get_file_by_number() {
    local num="$1"

    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        error "Invalid file number: $num" "exit"
    fi

    build_file_list "all"

    if [[ $num -lt 1 ]] || [[ $num -gt ${#FILE_LIST[@]} ]]; then
        error "File number $num out of range (1-${#FILE_LIST[@]})" "exit"
    fi

    echo "${FILE_LIST[$((num-1))]}"
}

# ===================
# Commands
# ===================
cmd_list() {
    local filter="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pending|-p)  filter="pending"; shift ;;
            --confirmed|-c) filter="confirmed"; shift ;;
            --help|-h)
                echo "Usage: $SCRIPT_NAME list [--pending|--confirmed]"
                echo ""
                echo "Options:"
                echo "  --pending, -p    Show only pending review files"
                echo "  --confirmed, -c  Show only confirmed quarantine files"
                exit 0
                ;;
            *) error "Unknown option: $1" "exit" ;;
        esac
    done

    ui_header "Quarantine Manager v$VERSION"
    build_file_list "$filter"

    if [[ ${#FILE_LIST[@]} -eq 0 ]]; then
        info "No quarantined files."
        return 0
    fi

    local pending_count=0
    local confirmed_count=0
    local unknown_count=0

    # Build table rows
    local rows=("#,Status,Date,Source,Size,Filename")

    local i=1
    for entry in "${FILE_LIST[@]}"; do
        local type="${entry%%:*}"
        local filepath="${entry#*:}"
        local filename
        filename=$(basename "$filepath")
        local size
        size=$(stat -c%s "$filepath" 2>/dev/null || echo "0")
        local size_fmt
        size_fmt=$(format_size "$size")

        local status_text date_text source_text
        local state_line
        if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
            date_text=$(echo "$state_line" | cut -d'|' -f3 | cut -d' ' -f1)
            source_text=$(echo "$state_line" | cut -d'|' -f4)
        else
            date_text="-"
            source_text="-"
        fi

        case "$type" in
            P) status_text="⚠️  PENDING";  ((pending_count++)) ;;
            C) status_text="🔒 CONFIRM";  ((confirmed_count++)) ;;
            *) status_text="❓ UNKNOWN";  ((unknown_count++)) ;;
        esac

        rows+=("$i,$status_text,$date_text,$source_text,$size_fmt,$filename")
        ((i++))
    done

    ui_table "${rows[@]}"

    echo ""
    local summary="Total: ${C_BOLD}${#FILE_LIST[@]}${C_NC} files (${C_YELLOW}${pending_count} pending${C_NC}, ${C_RED}${confirmed_count} confirmed${C_NC}"
    if [[ $unknown_count -gt 0 ]]; then
        summary+=", ${C_DIM}${unknown_count} untracked${C_NC}"
    fi
    summary+=")"
    echo -e "$summary"
    echo ""
    echo "Commands: inspect <#> | vt <#> | accept <#> | restore <#> | delete <#> | confirm <#>"
}

cmd_inspect() {
    local num="${1:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME inspect <number>"
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local type="${entry%%:*}"
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    ui_header "File Details"
    echo -e "Name:     ${C_CYAN}$filename${C_NC}"
    echo -e "Path:     $filepath"

    local status_label
    case "$type" in
        P) status_label="${C_YELLOW}Pending Review${C_NC}" ;;
        C) status_label="${C_RED}Confirmed Quarantine${C_NC}" ;;
        *) status_label="${C_DIM}Untracked${C_NC}" ;;
    esac
    echo -e "Status:   $status_label"

    # State info (original path, date, source, detection)
    local state_line
    if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
        local original_path q_date q_source q_detection
        original_path=$(echo "$state_line" | cut -d'|' -f2)
        q_date=$(echo "$state_line" | cut -d'|' -f3)
        q_source=$(echo "$state_line" | cut -d'|' -f4)
        q_detection=$(echo "$state_line" | cut -d'|' -f6)
        echo -e "Original: ${C_BOLD}$original_path${C_NC}"
        echo -e "Detected: $q_date"
        echo -e "Scanner:  $q_source"
        echo -e "Threat:   ${C_RED}$q_detection${C_NC}"
    fi

    if [[ -f "$filepath" ]]; then
        local size
        size=$(stat -c%s "$filepath")
        echo -e "Size:     $(format_size "$size")"
        echo -e "Modified: $(stat -c%y "$filepath" | cut -d. -f1)"

        # File type detection
        local filetype
        filetype=$(file -b "$filepath" 2>/dev/null || echo "Unknown")
        echo -e "Type:     $filetype"

        # SHA256 hash
        local hash
        hash=$(sha256sum "$filepath" 2>/dev/null | cut -d' ' -f1)
        echo -e "SHA256:   $hash"
    fi

    echo ""
    info "Actions: vt $num | accept $num | delete $num | confirm $num"
}

cmd_vt() {
    local num="${1:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME vt <number>"
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    # Check for API key
    local api_key=""
    if [[ -f "$VT_API_KEY_FILE" ]]; then
        api_key=$(cat "$VT_API_KEY_FILE")
    fi

    if [[ -z "$api_key" ]]; then
        warn "VirusTotal API key not configured."
        echo ""
        echo "To configure:"
        echo "  1. Get a free API key at https://www.virustotal.com/"
        echo "  2. Save it: echo 'YOUR_KEY' > ~/.config/virustotal_api_key"
        echo "  3. Secure it: chmod 600 ~/.config/virustotal_api_key"
        echo ""

        # Fallback: show hash for manual lookup
        if [[ -f "$filepath" ]]; then
            local hash
            hash=$(sha256sum "$filepath" | cut -d' ' -f1)
            info "Manual lookup:"
            echo "  https://www.virustotal.com/gui/file/$hash"
        fi
        return 0
    fi

    ui_header "VirusTotal Check"
    info "Checking $filename on VirusTotal..."
    echo ""

    # Calculate hash
    local hash
    hash=$(sha256sum "$filepath" | cut -d' ' -f1)

    # Query VirusTotal (with spinner if gum available)
    local response
    if has_gum; then
        response=$(gum spin --spinner dot --title "Querying VirusTotal..." -- \
            curl -s --request GET \
                --url "https://www.virustotal.com/api/v3/files/$hash" \
                --header "x-apikey: $api_key" 2>/dev/null)
    else
        response=$(curl -s --request GET \
            --url "https://www.virustotal.com/api/v3/files/$hash" \
            --header "x-apikey: $api_key" 2>/dev/null)
    fi

    if echo "$response" | grep -q '"error"'; then
        local error_code
        error_code=$(echo "$response" | grep -o '"code": *"[^"]*"' | cut -d'"' -f4)

        if [[ "$error_code" == "NotFoundError" ]]; then
            warn "File not found in VirusTotal database."
            echo ""
            echo "This file has never been scanned by VirusTotal."
            echo "You can upload it manually at: https://www.virustotal.com/"
        else
            error "VirusTotal API error: $error_code"
        fi
        return 0
    fi

    # Parse results
    local malicious harmless suspicious undetected
    malicious=$(echo "$response" | grep -o '"malicious": *[0-9]*' | head -1 | grep -o '[0-9]*')
    harmless=$(echo "$response" | grep -o '"harmless": *[0-9]*' | head -1 | grep -o '[0-9]*')
    suspicious=$(echo "$response" | grep -o '"suspicious": *[0-9]*' | head -1 | grep -o '[0-9]*')
    undetected=$(echo "$response" | grep -o '"undetected": *[0-9]*' | head -1 | grep -o '[0-9]*')

    local total=$((malicious + harmless + suspicious + undetected))

    echo -e "${C_BOLD}Results${C_NC}"
    echo "─────────────────────────────────────────────────────────"
    echo -e "SHA256:     $hash"
    echo ""

    if [[ $malicious -gt 0 ]]; then
        echo -e "${C_RED}Malicious:  $malicious / $total engines${C_NC}"
    else
        echo -e "${C_GREEN}Malicious:  $malicious / $total engines${C_NC}"
    fi

    if [[ $suspicious -gt 0 ]]; then
        echo -e "${C_YELLOW}Suspicious: $suspicious${C_NC}"
    fi

    echo -e "Harmless:   $harmless"
    echo -e "Undetected: $undetected"
    echo ""

    # Verdict
    if [[ $malicious -eq 0 ]] && [[ $suspicious -eq 0 ]]; then
        ui_banner "VERDICT: CLEAN" "No security vendors flagged this file."
    elif [[ $malicious -le 2 ]] && [[ $suspicious -le 2 ]]; then
        warn "Verdict: LOW RISK — Few detections, likely false positives."
    else
        ui_error_banner "VERDICT: SUSPICIOUS" "Multiple detections — exercise caution."
    fi

    echo "Full report: https://www.virustotal.com/gui/file/$hash"
}

cmd_accept() {
    local num="${1:-}"
    local dest="${2:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME accept <number> [destination]"
        echo ""
        echo "Default: original path from state, or current download directory."
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local type="${entry%%:*}"
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    # Determine default destination from state (original path's directory)
    local default_dest="$DEFAULT_RESTORE_DIR"
    local state_line
    if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
        local original_path
        original_path=$(echo "$state_line" | cut -d'|' -f2)
        default_dest=$(dirname "$original_path")
    fi

    # Ask for destination if not provided
    if [[ -z "$dest" ]]; then
        dest=$(ui_input "Restore destination" "$default_dest")
        dest="${dest:-$default_dest}"
    fi

    # Ensure destination exists
    if [[ ! -d "$dest" ]]; then
        mkdir -p "$dest"
    fi

    local dest_path="$dest/$filename"

    # Handle existing file
    if [[ -e "$dest_path" ]]; then
        local base="${filename%.*}"
        local ext="${filename##*.}"
        if [[ "$base" == "$ext" ]]; then
            ext=""
        else
            ext=".$ext"
        fi
        local counter=1
        while [[ -e "$dest/${base}_${counter}${ext}" ]]; do
            ((counter++))
        done
        dest_path="$dest/${base}_${counter}${ext}"
    fi

    # Move file
    mv "$filepath" "$dest_path"

    # Fix ownership (run as root, restore to user)
    local target_user
    target_user=$(stat -c%U "$dest")
    chown "$target_user:$target_user" "$dest_path"
    chmod 644 "$dest_path"

    # Remove state entry
    quarantine_state_remove "$filename"

    success "File restored: $dest_path"
}

cmd_restore() {
    local num="${1:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME restore <number>"
        echo ""
        echo "Restore file to its original location (from state)."
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    # Get original path from state
    local state_line
    if ! state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
        error "No state entry for $filename — use 'accept' to restore manually." "exit"
    fi

    local original_path
    original_path=$(echo "$state_line" | cut -d'|' -f2)
    local original_dir
    original_dir=$(dirname "$original_path")

    if [[ ! -d "$original_dir" ]]; then
        error "Original directory no longer exists: $original_dir" "exit"
    fi

    info "Restoring to: $original_path"
    if ! ui_confirm "Restore $filename to original location?"; then
        info "Cancelled."
        return 0
    fi

    local dest_path="$original_path"

    # Handle existing file at original path
    if [[ -e "$dest_path" ]]; then
        local base="${filename%.*}"
        local ext="${filename##*.}"
        if [[ "$base" == "$ext" ]]; then
            ext=""
        else
            ext=".$ext"
        fi
        local counter=1
        while [[ -e "${original_dir}/${base}_${counter}${ext}" ]]; do
            ((counter++))
        done
        dest_path="${original_dir}/${base}_${counter}${ext}"
        warn "Original file exists, restoring as: $(basename "$dest_path")"
    fi

    # Move file
    mv "$filepath" "$dest_path"

    # Fix ownership
    local target_user
    target_user=$(stat -c%U "$original_dir")
    chown "$target_user:$target_user" "$dest_path"
    chmod 644 "$dest_path"

    # Remove state entry
    quarantine_state_remove "$filename"

    success "File restored: $dest_path"
}

cmd_delete() {
    local num="${1:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME delete <number>"
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    if ! ui_confirm "Permanently delete $filename?"; then
        info "Cancelled."
        return 0
    fi

    # Delete file
    rm -f "$filepath"

    # Remove state entry
    quarantine_state_remove "$filename"

    success "File deleted: $filename"
}

cmd_confirm() {
    local num="${1:-}"

    if [[ -z "$num" ]]; then
        echo "Usage: $SCRIPT_NAME confirm <number>"
        echo ""
        echo "Mark a pending file as confirmed quarantine."
        exit 1
    fi

    local entry
    entry=$(get_file_by_number "$num")
    local type="${entry%%:*}"
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    if [[ "$type" == "C" ]]; then
        error "File is already confirmed." "exit"
    fi

    # Update status in state (no file move — flat structure)
    if ! quarantine_state_confirm "$filename"; then
        error "No state entry for $filename — cannot confirm." "exit"
    fi

    success "File confirmed as quarantined: $filename"
}

cmd_purge() {
    # Count confirmed files from state
    local confirmed_files=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        confirmed_files+=("$(echo "$line" | cut -d'|' -f1)")
    done < <(quarantine_state_list "confirmed")

    if [[ ${#confirmed_files[@]} -eq 0 ]]; then
        info "No confirmed quarantine files."
        return 0
    fi

    local count=${#confirmed_files[@]}

    ui_error_banner "PURGE WARNING" \
        "This will permanently delete $count confirmed file(s)."

    # List files to be deleted
    echo "Files to delete:"
    for f in "${confirmed_files[@]}"; do
        echo -e "  ${C_RED}• $f${C_NC}"
    done
    echo ""

    if ! ui_confirm "Type YES to purge all $count file(s)"; then
        info "Cancelled."
        return 0
    fi

    # Delete confirmed files from quarantine directory
    local deleted=0
    for f in "${confirmed_files[@]}"; do
        local fpath="$QUARANTINE_DIR/$f"
        if [[ -f "$fpath" ]]; then
            rm -f "$fpath"
            ((deleted++))
        fi
    done

    # Clear confirmed entries from state
    quarantine_state_clear "confirmed"

    success "Purged $deleted file(s) from quarantine."
}

cmd_logs() {
    local log_file=""

    # Determine log file
    if [[ -n "${1:-}" ]]; then
        log_file="$1"
    elif [[ -f "$LOG_DIR/daily-clamscan.log" ]] && [[ -f "$LOG_DIR/weekly-clamscan.log" ]]; then
        # Use the most recent
        if [[ "$LOG_DIR/daily-clamscan.log" -nt "$LOG_DIR/weekly-clamscan.log" ]]; then
            log_file="$LOG_DIR/daily-clamscan.log"
        else
            log_file="$LOG_DIR/weekly-clamscan.log"
        fi
    elif [[ -f "$LOG_DIR/weekly-clamscan.log" ]]; then
        log_file="$LOG_DIR/weekly-clamscan.log"
    elif [[ -f "$LOG_DIR/daily-clamscan.log" ]]; then
        log_file="$LOG_DIR/daily-clamscan.log"
    else
        error "No log files found in $LOG_DIR"
        echo "Usage: $SCRIPT_NAME logs [log_file]" >&2
        return 1
    fi

    ui_header "ClamAV Scan Report"

    info "Log file: $log_file"
    echo ""

    # Check if log exists
    if [[ ! -f "$log_file" ]]; then
        error "Log file not found: $log_file"
        return 1
    fi

    # Count infected files
    local infected_count
    infected_count=$(grep -c "FOUND" "$log_file" 2>/dev/null || echo "0")

    if [[ "$infected_count" -eq 0 ]]; then
        success "No infections found in log file"
    else
        echo -e "${C_RED}⚠️  Infections found: $infected_count${C_NC}"
        echo ""
        echo -e "${C_BOLD}--- Infected files: ---${C_NC}"
        grep "FOUND" "$log_file" | sed 's/: .* FOUND//' | nl
        echo ""
    fi

    # Check quarantine status
    echo -e "${C_BOLD}--- Quarantine status ---${C_NC}"
    local pending_count confirmed_count total_count
    pending_count=$(quarantine_state_list "pending" | grep -c '.' || true)
    confirmed_count=$(quarantine_state_list "confirmed" | grep -c '.' || true)
    total_count=$(find "$QUARANTINE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
    echo -e "  Pending:   ${C_YELLOW}$pending_count${C_NC} files"
    echo -e "  Confirmed: ${C_RED}$confirmed_count${C_NC} files"
    echo -e "  Total:     $total_count files in $QUARANTINE_DIR"
    echo ""

    # Scan summary
    echo -e "${C_BOLD}--- Scan summary ---${C_NC}"
    grep -E "(Infected files:|Known viruses:|Scanned files:|Scan Complete)" "$log_file" 2>/dev/null | tail -5 || echo "  No summary found"
    echo ""

    # Latest scan
    echo -e "${C_BOLD}--- Latest scan ---${C_NC}"
    grep -E "(ClamAV.*Scan -|Quick Scan Complete|Scan Complete)" "$log_file" 2>/dev/null | tail -1 || echo "  No scan info found"
    echo ""

    # Available logs
    echo -e "${C_BOLD}--- Available logs ---${C_NC}"
    if ls "$LOG_DIR"/*.log &>/dev/null; then
        ls -lh "$LOG_DIR"/*.log 2>/dev/null
    else
        echo "  No logs found in $LOG_DIR"
    fi
}

show_help() {
    cat << EOF
${C_BOLD}Quarantine Manager v$VERSION${C_NC}

Universal quarantine manager for all sources (torrents, downloads, etc.)
${C_RED}REQUIRES ROOT${C_NC}: Handles potentially infected files (except --help/--version)

${C_BOLD}USAGE${C_NC}
    sudo $SCRIPT_NAME                # Interactive mode (recommended)
    sudo $SCRIPT_NAME [command] [options]  # Direct command mode

${C_BOLD}INTERACTIVE MODE${C_NC}
    Run without arguments for a step-by-step interactive workflow
    with Gum-powered menus (falls back to bash if Gum not installed).

${C_BOLD}DIRECT COMMANDS${C_NC}
    ${C_GREEN}list${C_NC} [--pending|--confirmed]
        List quarantined files with status, date, source, and detection.

    ${C_GREEN}inspect${C_NC} <number>
        Show detailed information about a file (original path, threat, etc.)

    ${C_GREEN}vt${C_NC} <number>
        Check file against VirusTotal (requires API key).

    ${C_GREEN}accept${C_NC} <number> [destination]
        Restore file to a destination. Default: original path from state.

    ${C_GREEN}restore${C_NC} <number>
        Restore file directly to its original location.

    ${C_GREEN}delete${C_NC} <number>
        Permanently delete a quarantined file.

    ${C_GREEN}confirm${C_NC} <number>
        Mark a pending file as confirmed quarantine.

    ${C_GREEN}purge${C_NC}
        Delete ALL confirmed quarantine files.

    ${C_GREEN}logs${C_NC} [log_file]
        Show ClamAV scan reports, infections, and quarantine status.

${C_BOLD}EXAMPLES${C_NC}
    ${C_CYAN}# Interactive mode (step-by-step)${C_NC}
    sudo $SCRIPT_NAME

    ${C_CYAN}# Direct commands${C_NC}
    sudo $SCRIPT_NAME list               # List all with numbers
    sudo $SCRIPT_NAME inspect 1          # Show details of file #1
    sudo $SCRIPT_NAME vt 1               # VirusTotal check
    sudo $SCRIPT_NAME accept 1           # Restore to original location
    sudo $SCRIPT_NAME accept 1 ~/ISOs    # Restore to custom location
    sudo $SCRIPT_NAME restore 1          # Restore to original path
    sudo $SCRIPT_NAME delete 1           # Delete file
    sudo $SCRIPT_NAME purge              # Delete all confirmed files

${C_BOLD}DIRECTORIES${C_NC}
    Quarantine: $QUARANTINE_DIR
    State:      $QUARANTINE_STATE_FILE

${C_BOLD}VIRUSTOTAL${C_NC}
    To enable VirusTotal checks:
    1. Get free API key at https://www.virustotal.com/
    2. echo 'YOUR_KEY' > ~/.config/virustotal_api_key
    3. chmod 600 ~/.config/virustotal_api_key

EOF
}

# ===================
# Interactive Mode
# ===================
interactive_mode() {
    ui_header "Quarantine Manager v$VERSION"
    build_file_list "all"

    if [[ ${#FILE_LIST[@]} -eq 0 ]]; then
        info "No quarantined files."
        echo ""
        echo "Files are placed in quarantine when:"
        echo "  - ClamAV detects threats in downloads"
        echo "  - ISO files have suspicious detections (pending review)"
        echo ""
        return 0
    fi

    # Build display items for file chooser
    local display_items=()
    local pending_count=0
    local confirmed_count=0

    local i=1
    for entry in "${FILE_LIST[@]}"; do
        local type="${entry%%:*}"
        local filepath="${entry#*:}"
        local filename
        filename=$(basename "$filepath")
        local size
        size=$(stat -c%s "$filepath" 2>/dev/null || echo "0")
        local size_fmt
        size_fmt=$(format_size "$size")

        local status_label
        case "$type" in
            P) status_label="⚠️  PENDING"; ((pending_count++)) ;;
            C) status_label="🔒 CONFIRMED"; ((confirmed_count++)) ;;
            *) status_label="❓ UNTRACKED" ;;
        esac

        display_items+=("$i. $status_label  $size_fmt  $filename")
        ((i++))
    done

    echo -e "Files: ${C_BOLD}${#FILE_LIST[@]}${C_NC} (${C_YELLOW}$pending_count pending${C_NC}, ${C_RED}$confirmed_count confirmed${C_NC})"
    echo ""

    # Select a file via ui_choose
    local selected
    selected=$(ui_choose --header "Select a file:" "${display_items[@]}" "← Quit")

    # Handle quit
    [[ -z "$selected" || "$selected" == "← Quit" ]] && return 0

    # Extract file number from selection (first token before the dot)
    local file_num
    file_num=$(echo "$selected" | grep -o '^[0-9]*')

    if [[ -z "$file_num" ]] || [[ $file_num -lt 1 ]] || [[ $file_num -gt ${#FILE_LIST[@]} ]]; then
        error "Invalid selection"
        return 1
    fi

    # Get selected file info
    local entry="${FILE_LIST[$((file_num-1))]}"
    local type="${entry%%:*}"
    local filepath="${entry#*:}"
    local filename
    filename=$(basename "$filepath")

    echo ""
    echo -e "${C_BOLD}Selected: ${C_CYAN}$filename${C_NC}"
    echo ""

    # Show file details
    if [[ -f "$filepath" ]]; then
        local size
        size=$(stat -c%s "$filepath")
        echo -e "Size:     $(format_size "$size")"
        echo -e "Modified: $(stat -c%y "$filepath" | cut -d. -f1)"

        local filetype
        filetype=$(file -b "$filepath" 2>/dev/null || echo "Unknown")
        echo -e "Type:     $filetype"
    fi

    # Show state info (original path, detection)
    local state_line
    if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
        local original_path q_detection
        original_path=$(echo "$state_line" | cut -d'|' -f2)
        q_detection=$(echo "$state_line" | cut -d'|' -f6)
        echo -e "Original: ${C_BOLD}$original_path${C_NC}"
        [[ "$q_detection" != "unknown" ]] && echo -e "Threat:   ${C_RED}$q_detection${C_NC}"
    fi

    echo ""

    # Build action menu
    local actions=("🔍 Inspect" "🌐 VirusTotal" "✅ Accept (restore)" "🔄 Restore to original" "🗑️  Delete")
    [[ "$type" == "P" ]] && actions+=("🔒 Confirm quarantine")
    actions+=("← Cancel")

    local action
    action=$(ui_choose --header "Action for $filename:" "${actions[@]}")

    echo ""

    case "$action" in
        "🔍 Inspect")
            cmd_inspect "$file_num"
            ;;
        "🌐 VirusTotal")
            cmd_vt "$file_num"
            ;;
        "✅ Accept (restore)")
            local dest default_dest="$DEFAULT_RESTORE_DIR"
            if state_line=$(quarantine_state_get "$filename" 2>/dev/null); then
                default_dest=$(dirname "$(echo "$state_line" | cut -d'|' -f2)")
            fi
            dest=$(ui_input "Restore destination" "$default_dest")
            dest="${dest:-$default_dest}"
            cmd_accept "$file_num" "$dest"
            ;;
        "🔄 Restore to original")
            cmd_restore "$file_num"
            ;;
        "🗑️  Delete")
            cmd_delete "$file_num"
            ;;
        "🔒 Confirm quarantine")
            cmd_confirm "$file_num"
            ;;
        *)
            info "Cancelled."
            ;;
    esac
}

# ===================
# Main
# ===================
main() {
    # Commands that don't need root: help and version
    if [[ $# -gt 0 ]]; then
        case "${1}" in
            --help|-h|help)
                show_help
                exit 0
                ;;
            --version|-v)
                echo "Quarantine Manager v$VERSION"
                exit 0
                ;;
        esac
    fi

    # All other commands require root (handling sensitive infected files)
    check_root

    # Ensure quarantine directories exist
    ensure_directories

    # No arguments => interactive mode
    if [[ $# -eq 0 ]]; then
        interactive_mode
        return $?
    fi

    local cmd="${1}"

    case "$cmd" in
        list|ls)
            shift
            cmd_list "$@"
            ;;
        inspect|info|show)
            shift
            cmd_inspect "$@"
            ;;
        vt|virustotal)
            shift
            cmd_vt "$@"
            ;;
        accept|release)
            shift
            cmd_accept "$@"
            ;;
        restore)
            shift
            cmd_restore "$@"
            ;;
        delete|rm|remove)
            shift
            cmd_delete "$@"
            ;;
        confirm|quarantine)
            shift
            cmd_confirm "$@"
            ;;
        purge|clean)
            shift
            cmd_purge "$@"
            ;;
        logs|log|report|reports)
            shift
            cmd_logs "$@"
            ;;
        *)
            error "Unknown command: $cmd. Use '$SCRIPT_NAME --help' for usage." "exit"
            ;;
    esac
}

main "$@"
