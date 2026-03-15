#!/bin/bash
# =============================================================================
# WEEKLY-CLAMSCAN - Weekly full ClamAV scan
# =============================================================================
# Uses clamd daemon (multi-threaded) for comprehensive weekly scanning
# of /home, /tmp, /var/tmp, /root, /data, and /code directories.
#
# Module: clamav
# Requires: none (self-contained service)
# Version: 0.1.0
# =============================================================================

# Note: -e (errexit) intentionally omitted — daemon script handles clamscan
# exit codes explicitly (infected files return non-zero)
set -uo pipefail

# ===================
# Configuration
# ===================
readonly LOG_DIR="/var/log/clamav"
readonly LOG_FILE="$LOG_DIR/weekly-clamscan.log"
readonly QUARANTINE="/var/quarantine"
readonly LOG_TAG="notify-weekly-scan"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
readonly DATE
readonly LOCK_FILE="/run/lock/weekly-clamscan.lock"
readonly CLAMD_CONF="/etc/clamd.d/scan.conf"
readonly QUARANTINE_STATE_LIB="/usr/local/lib/system-scripts/quarantine-state.sh"

# Tracking
TOTAL_INFECTED=0
CLAMD_WAS_RUNNING=false

# ===================
# Exclusions
# ===================
# shellcheck disable=SC2034  # kept for documentation; clamdscan doesn't support --exclude
MEDIA_EXCLUDES=(
    --exclude='*.mp4' --exclude='*.mkv' --exclude='*.avi'
    --exclude='*.mov' --exclude='*.webm' --exclude='*.flv'
    --exclude='*.wmv' --exclude='*.m4v' --exclude='*.mp3'
    --exclude='*.flac' --exclude='*.wav' --exclude='*.ogg'
    --exclude='*.m4a' --exclude='*.aac' --exclude='*.wma'
    --exclude='*.jpg' --exclude='*.jpeg' --exclude='*.png'
    --exclude='*.gif' --exclude='*.bmp' --exclude='*.webp'
    --exclude='*.svg' --exclude='*.tiff' --exclude='*.ico'
    --exclude='*.iso' --exclude='*.img' --exclude='*.gguf'
)

SNAPSHOT_EXCLUDES=(
    --exclude-dir=.snapshots
)

HOME_EXCLUDES=(
    --exclude-dir=.cache
    --exclude-dir=.vscode/extensions
    --exclude-dir=.vscode-insiders/extensions
    --exclude-dir=.cargo/registry
    --exclude-dir=.rustup
    --exclude-dir=.nvm
    --exclude-dir=.var/app
    --exclude-dir=.local/share/containers/storage
    --exclude-dir=.local/share/Trash
)

CODE_EXCLUDES=(
    --exclude-dir=node_modules --exclude-dir=target
    --exclude-dir=.venv --exclude-dir=venv
    --exclude-dir=__pycache__ --exclude-dir=.git
    --exclude-dir=dist --exclude-dir=build
    --exclude-dir=.next --exclude-dir=.nuxt
    --exclude-dir=.cargo --exclude-dir=vendor
)

# ===================
# Functions
# ===================
log() {
    local message
    message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
    echo "$message"
}

start_clamd() {
    if systemctl is-active --quiet clamd@scan; then
        CLAMD_WAS_RUNNING=true
        log "clamd@scan already running"
        return 0
    fi

    log "Starting clamd@scan daemon..."
    systemctl start clamd@scan

    local retries=30
    while ! clamdscan --config-file="$CLAMD_CONF" --ping 1 2>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done

    if [[ $retries -eq 0 ]]; then
        log "ERROR: clamd@scan failed to start"
        logger -t "$LOG_TAG" -p user.err "[ICON:dialog-error] clamd@scan failed to start for weekly scan"
        exit 2
    fi
    log "clamd@scan ready"
}

# shellcheck disable=SC2329,SC2317  # invoked via trap EXIT
stop_clamd() {
    if [[ "$CLAMD_WAS_RUNNING" == "false" ]] && systemctl is-active --quiet clamd@scan; then
        log "Stopping clamd@scan daemon..."
        systemctl stop clamd@scan
    fi
}

check_signatures() {
    local cvd_file="/var/lib/clamav/daily.cvd"
    [[ -f "$cvd_file" ]] || cvd_file="/var/lib/clamav/daily.cld"

    if [[ -f "$cvd_file" ]]; then
        local last_update
        last_update=$(stat -c %Y "$cvd_file")
        local current_time
        current_time=$(date +%s)
        local days_old=$(( (current_time - last_update) / 86400 ))

        if [[ "$days_old" -gt 7 ]]; then
            log "⚠ WARNING: Signatures are $days_old days old"
            logger -t "$LOG_TAG" -p user.warning "[ICON:security-medium] Virus signatures are $days_old days old"
        fi
    else
        log "⚠ WARNING: No signature database found"
        logger -t "$LOG_TAG" -p user.warning "[ICON:security-low] No signature database found"
    fi

    if ! systemctl is-active --quiet clamav-freshclam 2>/dev/null; then
        log "⚠ WARNING: clamav-freshclam is not running"
    fi
}

scan_directory() {
    local base_dir="$1"
    shift
    local exclude_patterns=("$@")

    if [[ ! -d "$base_dir" ]]; then
        log "SKIP: $base_dir does not exist"
        return 0
    fi

    if [[ ! -r "$base_dir" ]]; then
        log "SKIP: $base_dir not readable"
        return 0
    fi

    # If no exclusions, scan directly (simple case)
    if [[ ${#exclude_patterns[@]} -eq 0 ]]; then
        log "Scanning: $base_dir"
        local exit_code=0
        clamdscan --config-file="$CLAMD_CONF" --multiscan --infected --move="$QUARANTINE" --fdpass "$base_dir" >> "$LOG_FILE" 2>&1 || exit_code=$?

        case $exit_code in
            0) log "  ✓ Clean" ;;
            1) log "  ⚠ Infections found" ; return 1 ;;
            2) log "  ✓ Clean (warnings on unscannable files: sockets, pipes)" ;;
        esac
        return 0
    fi

    # With exclusions: scan subdirectories individually, skipping excluded ones
    log "Scanning: $base_dir (filtering exclusions)"

    # Extract directory names from --exclude-dir=name patterns
    local exclude_names=()
    for pattern in "${exclude_patterns[@]}"; do
        local name="${pattern#--exclude-dir=}"
        exclude_names+=("$name")
    done

    # Build list of directories to scan (top-level entries, filtering exclusions)
    local dirs_to_scan=()
    while IFS= read -r -d '' entry; do
        local basename
        basename=$(basename "$entry")
        local excluded=false

        # Check if this directory is in exclusion list
        for exclude_name in "${exclude_names[@]}"; do
            if [[ "$basename" == "$exclude_name" ]]; then
                excluded=true
                break
            fi
        done

        if [[ "$excluded" == "false" ]]; then
            dirs_to_scan+=("$entry")
        fi
    done < <(find "$base_dir" -maxdepth 1 -mindepth 1 -type d -print0)

    # Scan filtered directories
    if [[ ${#dirs_to_scan[@]} -eq 0 ]]; then
        log "  No directories to scan after exclusions"
        return 0
    fi

    local exit_code=0
    clamdscan --config-file="$CLAMD_CONF" --multiscan --infected --move="$QUARANTINE" --fdpass "${dirs_to_scan[@]}" >> "$LOG_FILE" 2>&1 || exit_code=$?

    case $exit_code in
        0) log "  ✓ Clean" ;;
        1) log "  ⚠ Infections found" ; return 1 ;;
        2) log "  ✓ Clean (warnings on unscannable files: sockets, pipes)" ;;
    esac

    return 0
}

# ===================
# Main
# ===================

# Ensure quarantine exists with correct permissions
mkdir -p "$QUARANTINE"
chmod 700 "$QUARANTINE"
# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Prevent concurrent runs
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    log "Another scan is already running. Exiting."
    exit 0
fi

# Stop clamd on exit (only if we started it)
trap 'stop_clamd' EXIT

log "==========================================="
log "=== ClamAV Weekly Scan - $DATE ==="
log "==========================================="

check_signatures
start_clamd

# Mark scan start line for accurate FOUND count
SCAN_START_LINE=$(wc -l < "$LOG_FILE")

# Scans
scan_directory "/home" "${HOME_EXCLUDES[@]}" "${SNAPSHOT_EXCLUDES[@]}" || ((TOTAL_INFECTED++)) || true
scan_directory "/tmp" || ((TOTAL_INFECTED++)) || true
scan_directory "/var/tmp" || ((TOTAL_INFECTED++)) || true
scan_directory "/root" || ((TOTAL_INFECTED++)) || true

# Note: MEDIA_EXCLUDES (--exclude patterns) not used because clamdscan doesn't support them.
# Media files are scanned but mostly harmless (ClamAV skips unscannable formats).
[[ -d /data ]] && { scan_directory "/data" "${SNAPSHOT_EXCLUDES[@]}" || ((TOTAL_INFECTED++)) || true; }
[[ -d /code ]] && { scan_directory "/code" "${CODE_EXCLUDES[@]}" "${SNAPSHOT_EXCLUDES[@]}" || ((TOTAL_INFECTED++)) || true; }

# Summary (count FOUND only from this scan, not previous runs)
INFECTED_FILES=$(tail -n +"$SCAN_START_LINE" "$LOG_FILE" | grep -c "FOUND" || true)
SCAN_END=$(date +%Y-%m-%d_%H-%M-%S)

# Register quarantined files in state tracker
if [[ "$INFECTED_FILES" -gt 0 ]] && [[ -f "$QUARANTINE_STATE_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$QUARANTINE_STATE_LIB"
    quarantine_state_register_found "$LOG_FILE" "$SCAN_START_LINE" "weekly"
fi

log "==========================================="
log "=== Scan Complete ==="
log "Directories with infections: $TOTAL_INFECTED"
log "Total infected files: $INFECTED_FILES"
log "Quarantine: $QUARANTINE"
log "Ended: $SCAN_END"
log "==========================================="

# Notifications via logger (interceptées par notify-daemon)
if [[ "$INFECTED_FILES" -gt 0 ]]; then
    logger -t "$LOG_TAG" -p user.crit "[ICON:security-low] ❌ Weekly scan: $INFECTED_FILES virus(es) quarantined in $QUARANTINE - Check: $LOG_FILE"
    exit 1
else
    logger -t "$LOG_TAG" -p user.notice "[ICON:security-high] ✅ Weekly scan: completed - No threats found"
fi

exit 0
