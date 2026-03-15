#!/bin/bash
# =============================================================================
# DOWNLOAD-CLAMSCAN - Monitor download directories and scan new files
# =============================================================================
# System service that monitors download directories for new files and
# automatically scans them with ClamAV via clamd daemon (multi-threaded).
#
# Module: clamav
# Requires: none (self-contained service)
# Version: 0.1.0
#
# Configuration: /etc/system-scripts/paths.conf
# Depends: clamd@scan.service (systemd dependency)
#
# Runs as system service (root) to access quarantine.
# Uses logger for notifications (captured by notify-daemon).
# =============================================================================

set -euo pipefail

# ===================
# Configuration
# ===================
# shellcheck disable=SC2034  # SCRIPT_NAME used for consistency across module scripts
SCRIPT_NAME="$(basename "$0")"
# shellcheck disable=SC2034
readonly SCRIPT_NAME
readonly CONFIG_FILE="${PATHS_CONF:-/etc/system-scripts/paths.conf}"
readonly QUARANTINE="/var/quarantine"
readonly LOG_DIR="/var/log/clamav"
readonly LOG_FILE="$LOG_DIR/download-clamscan.log"
readonly LOG_TAG="notify-download-scan"
readonly CLAMD_CONF="/etc/clamd.d/scan.conf"
readonly QUARANTINE_STATE_LIB="/usr/local/lib/system-scripts/quarantine-state.sh"

# Deduplication: track recently scanned files to avoid duplicates
declare -A SCANNED_FILES
readonly DEDUP_TIMEOUT=30  # seconds before allowing rescan of same file

# ===================
# Functions
# ===================
log() {
    local message="$1"
    local priority="${2:-info}"
    local notify="${3:-true}"  # Send notification by default
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Always write to log file
    echo "[$timestamp] $message" >> "$LOG_FILE"

    # Only send notification if requested
    if [[ "$notify" == "true" ]]; then
        logger -t "$LOG_TAG" -p "user.$priority" "$message"
    fi
}

error_exit() {
    log "ERROR: $1" "err"
    echo "ERROR: $1" >&2
    exit 1
}

check_dependencies() {
    local missing=()

    if ! command -v inotifywait &>/dev/null; then
        missing+=("inotify-tools")
    fi

    if ! command -v clamdscan &>/dev/null; then
        missing+=("clamav")
    fi

    if ! command -v fuser &>/dev/null; then
        missing+=("psmisc")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error_exit "Missing dependencies: ${missing[*]}. Install with: sudo dnf install ${missing[*]}"
    fi

    # Verify clamd daemon is running (systemd dependency should ensure this)
    if ! clamdscan --config-file="$CLAMD_CONF" --ping 1 &>/dev/null; then
        error_exit "clamd@scan is not running. Enable with: sudo systemctl start clamd@scan"
    fi
}

load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error_exit "Configuration file not found: $CONFIG_FILE
Run the security setup script to generate it."
    fi

    # Source the config file
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    # Validate required variables
    if [[ -z "${TARGET_USER:-}" ]]; then
        error_exit "TARGET_USER not set in $CONFIG_FILE"
    fi

    if [[ -z "${TARGET_HOME:-}" ]]; then
        error_exit "TARGET_HOME not set in $CONFIG_FILE"
    fi

    if [[ -z "${WATCH_DIRS[*]:-}" ]]; then
        error_exit "WATCH_DIRS not set in $CONFIG_FILE"
    fi

    # Validate user exists
    if ! id "$TARGET_USER" &>/dev/null; then
        error_exit "User '$TARGET_USER' does not exist"
    fi

    # Validate home directory
    if [[ ! -d "$TARGET_HOME" ]]; then
        error_exit "Home directory does not exist: $TARGET_HOME"
    fi
}

wait_download_complete() {
    local filepath="$1"
    local max_wait=120
    local elapsed=0

    # Phase 1: Wait until no process has the file open (fuser check)
    while (( elapsed < max_wait )); do
        if ! fuser "$filepath" &>/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((elapsed += 2))
    done

    # Bail out if file disappeared or timeout
    [[ -f "$filepath" ]] || return 1
    if (( elapsed >= max_wait )); then
        log "Timeout waiting for download: $(basename "$filepath")" "warn" "false"
        return 1
    fi

    # Phase 2: Confirm with file size stability (2 consecutive checks)
    local prev_size=-1
    local stable_count=0
    while (( stable_count < 2 )); do
        local size
        size=$(stat -c%s "$filepath" 2>/dev/null) || return 1
        if (( size == prev_size )); then
            ((stable_count++))
        else
            stable_count=0
            prev_size=$size
        fi

        # If fuser shows activity again, reset and go back to waiting
        if fuser "$filepath" &>/dev/null 2>&1; then
            stable_count=0
            prev_size=-1
            while fuser "$filepath" &>/dev/null 2>&1 && (( elapsed < max_wait )); do
                sleep 2
                ((elapsed += 2))
            done
            [[ -f "$filepath" ]] || return 1
        fi

        (( stable_count < 2 )) && sleep 2
        ((elapsed += 2))
        if (( elapsed >= max_wait )); then
            log "Timeout waiting for stable size: $(basename "$filepath")" "warn" "false"
            return 1
        fi
    done

    return 0
}

scan_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    log "Scanning: $filepath" "info" "false"  # Log only, no notification

    scan_regular_file "$filepath"
}

scan_regular_file() {
    local filepath="$1"
    local filename
    filename=$(basename "$filepath")

    local exit_code=0
    clamdscan --config-file="$CLAMD_CONF" --no-summary --move="$QUARANTINE" --fdpass "$filepath" >> "$LOG_FILE" 2>&1 || exit_code=$?

    case $exit_code in
        0) log "[ICON:security-high] ✅ Clean: $filename" "info" ;;
        1)
            log "[ICON:security-low] VIRUS DETECTED: $filepath - Moved to quarantine" "crit"
            # Register in quarantine state tracker
            if [[ -f "$QUARANTINE_STATE_LIB" ]]; then
                # shellcheck source=/dev/null
                source "$QUARANTINE_STATE_LIB"
                quarantine_state_add "$filename" "$filepath" "download"
            fi
            ;;
        2) log "[ICON:dialog-error] ❌ Scan error: $filename" "err" ;;
    esac
}

# ===================
# Main
# ===================
main() {
    # Check dependencies
    check_dependencies

    # Load configuration
    load_config

    # Ensure directories exist
    mkdir -p "$QUARANTINE"
    chmod 700 "$QUARANTINE"
    mkdir -p "$LOG_DIR"

    # Filter WATCH_DIRS to existing directories only
    local existing_dirs=()
    for dir in "${WATCH_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            existing_dirs+=("$dir")
        else
            log "Warning: Watch directory does not exist: $dir" "warn" "false"
        fi
    done

    if [[ ${#existing_dirs[@]} -eq 0 ]]; then
        error_exit "No directories to monitor exist. Check WATCH_DIRS in $CONFIG_FILE"
    fi

    log "Starting monitoring for user $TARGET_USER: ${existing_dirs[*]}"

    # Monitor completed files (close_write = end of write, moved_to = moved into dir)
    # shellcheck disable=SC2034  # action is part of inotifywait output format
    inotifywait -m -r -e close_write -e moved_to "${existing_dirs[@]}" |
    while read -r path action file; do
        local filepath="$path$file"

        # Ignore temporary and partial files
        if [[ "$file" == *.part ]] || \
           [[ "$file" == *.crdownload ]] || \
           [[ "$file" == *.tmp ]] || \
           [[ "$file" == .* ]] || \
           [[ -d "$filepath" ]]; then
            continue
        fi

        # Wait for download to complete (fuser + size stability)
        wait_download_complete "$filepath" || continue

        # Deduplication: skip if recently scanned
        local now
        now=$(date +%s)
        local file_key="${filepath}"
        if [[ -n "${SCANNED_FILES[$file_key]:-}" ]]; then
            local last_scan="${SCANNED_FILES[$file_key]}"
            if (( now - last_scan < DEDUP_TIMEOUT )); then
                continue  # Skip duplicate event
            fi
        fi
        SCANNED_FILES[$file_key]=$now

        # Scan the file
        scan_file "$filepath"
    done
}

main "$@"
