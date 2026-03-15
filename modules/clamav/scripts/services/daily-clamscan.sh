#!/bin/bash
# =============================================================================
# DAILY-CLAMSCAN - Daily quick ClamAV scan
# =============================================================================
# Uses clamd daemon (multi-threaded) for fast daily scanning of
# high-risk directories (Downloads, /tmp, /var/tmp).
#
# Module: clamav
# Requires: none (self-contained service)
# Version: 0.1.0
#
# Configuration: /etc/system-scripts/paths.conf
# =============================================================================

# Note: -e (errexit) intentionally omitted — daemon script handles clamscan
# exit codes explicitly (infected files return non-zero)
set -uo pipefail

# ===================
# Configuration
# ===================
readonly CONFIG_FILE="${PATHS_CONF:-/etc/system-scripts/paths.conf}"
readonly LOG_DIR="/var/log/clamav"
readonly LOG_FILE="$LOG_DIR/daily-clamscan.log"
readonly QUARANTINE="/var/quarantine"
readonly LOG_TAG="notify-daily-scan"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
readonly DATE
readonly LOCK_FILE="/run/lock/daily-clamscan.lock"
readonly CLAMD_CONF="/etc/clamd.d/scan.conf"
readonly QUARANTINE_STATE_LIB="/usr/local/lib/system-scripts/quarantine-state.sh"

# System directories to always scan
readonly SYSTEM_DIRS=("/tmp" "/var/tmp")

# Tracking
TOTAL_INFECTED=0
CLAMD_WAS_RUNNING=false

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
        logger -t "$LOG_TAG" -p user.err "[ICON:dialog-error] clamd@scan failed to start for daily scan"
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

scan_directory() {
    local dir="$1"
    local name="${2:-$1}"

    if [[ ! -d "$dir" ]]; then
        log "SKIP: $dir does not exist"
        return 0
    fi

    if [[ ! -r "$dir" ]]; then
        log "SKIP: $dir not readable"
        return 0
    fi

    log "Scanning: $name ($dir)"

    local exit_code=0
    clamdscan --config-file="$CLAMD_CONF" --multiscan --infected --move="$QUARANTINE" --fdpass "$dir" >> "$LOG_FILE" 2>&1 || exit_code=$?

    # clamdscan exit codes: 0=clean, 1=infected, 2=some files not scanned
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
log "=== ClamAV Daily Quick Scan - $DATE ==="
log "==========================================="

start_clamd

# Mark scan start line for accurate FOUND count
SCAN_START_LINE=$(wc -l < "$LOG_FILE")

# Scan system high-risk directories
for dir in "${SYSTEM_DIRS[@]}"; do
    scan_directory "$dir" "$(basename "$dir")" || ((TOTAL_INFECTED++)) || true
done

# Load configuration for user directories
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"

    log "Config: $CONFIG_FILE (user: ${TARGET_USER:-unknown})"

    # Scan configured watch directories
    if [[ -n "${WATCH_DIRS[*]:-}" ]]; then
        for dir in "${WATCH_DIRS[@]}"; do
            scan_directory "$dir" "$dir" || ((TOTAL_INFECTED++)) || true
        done
    fi
else
    log "WARNING: Config not found: $CONFIG_FILE"
    log "Falling back to scanning all /home/*/Downloads directories"

    # Fallback: scan common locations for all users
    for user_home in /home/*; do
        [[ -d "$user_home" ]] || continue
        username=$(basename "$user_home")

        scan_directory "$user_home/Downloads" "$username/Downloads" || ((TOTAL_INFECTED++)) || true
        scan_directory "$user_home/Téléchargements" "$username/Téléchargements" || ((TOTAL_INFECTED++)) || true
        scan_directory "$user_home/Downloads/torrents" "$username/Downloads/torrents" || ((TOTAL_INFECTED++)) || true
    done
fi

# Summary (count FOUND only from this scan, not previous runs)
INFECTED_FILES=$(tail -n +"$SCAN_START_LINE" "$LOG_FILE" | grep -c "FOUND" || true)
SCAN_END=$(date +%Y-%m-%d_%H-%M-%S)

# Register quarantined files in state tracker
if [[ "$INFECTED_FILES" -gt 0 ]] && [[ -f "$QUARANTINE_STATE_LIB" ]]; then
    # shellcheck source=/dev/null
    source "$QUARANTINE_STATE_LIB"
    quarantine_state_register_found "$LOG_FILE" "$SCAN_START_LINE" "daily"
fi

log "==========================================="
log "=== Quick Scan Complete ==="
log "Directories with infections: $TOTAL_INFECTED"
log "Total infected files: $INFECTED_FILES"
log "Ended: $SCAN_END"
log "==========================================="

# Notifications via logger
if [[ "$INFECTED_FILES" -gt 0 ]]; then
    logger -t "$LOG_TAG" -p user.crit "[ICON:security-low] ❌ Daily scan: $INFECTED_FILES virus(es) quarantined in $QUARANTINE - Check: $LOG_FILE"
    exit 1
else
    logger -t "$LOG_TAG" -p user.notice "[ICON:security-high] ✅ Daily scan: completed - No threats found"
fi

exit 0
