#!/bin/bash
# =============================================================================
# USB-CLAMSCAN - Automatic USB ClamAV scanning (post-mount)
# =============================================================================
# Scans USB drives after GNOME auto-mount completes.
# Non-blocking: user can use the drive during scan.
#
# Workflow:
#   1. USB inserted → udev ADD → starts this service
#   2. Wait for GNOME auto-mount (poll findmnt, 30s timeout)
#   3. Run ClamAV scan (clamdscan, fallback clamscan)
#   4. Quarantine infected files to /var/quarantine/confirmed
#   5. Send notification with results
#
# Module: clamav
# Requires: none (self-contained service)
# Version: 0.1.0
#
# Usage:
#   usb-clamscan <device>     (e.g., usb-clamscan /dev/sdb1)
# =============================================================================

set -euo pipefail

# ===================
# Configuration
# ===================
readonly LOG_DIR="/var/log/clamav"
readonly LOG_FILE="$LOG_DIR/usb-clamscan.log"
readonly QUARANTINE="/var/quarantine"
readonly FSTAB="/etc/fstab"
readonly LOCK_DIR="/run/lock"
readonly LOG_TAG="notify-usb-scan"

# ClamAV daemon config
readonly CLAMD_SERVICE="clamd@scan"
readonly CLAMD_CONF="/etc/clamd.d/scan.conf"
readonly QUARANTINE_STATE_LIB="/usr/local/lib/system-scripts/quarantine-state.sh"
CLAMD_WAS_RUNNING=false

# ===================
# Detect logged-in user (works from systemd service)
# ===================
detect_user() {
    local user=""

    # Method 1: SUDO_USER if available (manual run)
    if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
        user="$SUDO_USER"
    fi

    # Method 2: Find user with active graphical session (systemd run)
    if [[ -z "$user" ]]; then
        user=$(loginctl list-sessions --no-legend 2>/dev/null | \
               awk '$3 != "root" && $5 != "" {print $3; exit}' || echo "")
    fi

    # Method 3: Who owns the display
    if [[ -z "$user" ]]; then
        user=$(who 2>/dev/null | grep -E '\(:0\)|\(tty' | head -1 | awk '{print $1}' || echo "")
    fi

    # Method 4: First non-root user with UID >= 1000
    if [[ -z "$user" ]]; then
        user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
    fi

    echo "${user:-root}"
}

TARGET_USER=$(detect_user)
readonly TARGET_USER

# ===================
# Logging
# ===================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >> "$LOG_FILE"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# ===================
# Notifications
# ===================
notify() {
    local title="$1"
    local message="$2"
    local urgency="${3:-normal}"
    local icon="${4:-drive-removable-media}"

    local priority="user.notice"
    case "$urgency" in
        critical) priority="user.crit" ;;
        low)      priority="user.info" ;;
    esac

    logger -t "$LOG_TAG" -p "$priority" "[ICON:$icon] $title: $message" 2>/dev/null || true
    log "Notification sent: [$urgency] $title - $message"
}

# ===================
# fstab Check
# ===================
is_in_fstab() {
    local device="$1"

    if grep -qE "^${device}\s|UUID=.*${device}" "$FSTAB" 2>/dev/null; then
        return 0
    fi

    local uuid
    uuid=$(lsblk -no UUID "$device" 2>/dev/null || echo "")
    if [[ -n "$uuid" ]] && grep -qE "UUID=${uuid}" "$FSTAB" 2>/dev/null; then
        return 0
    fi

    return 1
}

# ===================
# Device Info
# ===================
get_device_label() {
    local label
    label=$(lsblk -no LABEL "$1" 2>/dev/null || echo "")
    echo "${label:-USB_DRIVE}"
}

get_device_size() {
    lsblk -no SIZE "$1" 2>/dev/null || echo "unknown"
}

# ===================
# Wait for GNOME auto-mount
# ===================
wait_for_mount() {
    local device="$1"
    local timeout=30
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local mount_point
        mount_point=$(findmnt -n -o TARGET "$device" 2>/dev/null || echo "")
        if [[ -n "$mount_point" ]]; then
            echo "$mount_point"
            return 0
        fi
        sleep 1
        ((elapsed++))
    done

    return 1
}

# ===================
# ClamAV Daemon Management
# ===================
start_clamd() {
    if systemctl is-active --quiet "$CLAMD_SERVICE"; then
        CLAMD_WAS_RUNNING=true
        log "ClamAV daemon already running"
        return 0
    fi

    log "Starting ClamAV daemon..."
    if ! systemctl start "$CLAMD_SERVICE" 2>&1; then
        log_error "Failed to start $CLAMD_SERVICE"
        return 1
    fi

    local retries=30
    while ! clamdscan --config-file="$CLAMD_CONF" --ping 1 2>/dev/null && [[ $retries -gt 0 ]]; do
        sleep 2
        ((retries--))
    done

    if [[ $retries -eq 0 ]]; then
        log_error "clamd@scan failed to start (timeout)"
        return 1
    fi

    log "ClamAV daemon ready"
    return 0
}

# shellcheck disable=SC2329
stop_clamd() {
    if [[ "$CLAMD_WAS_RUNNING" == "false" ]] && systemctl is-active --quiet "$CLAMD_SERVICE"; then
        log "Stopping ClamAV daemon..."
        systemctl stop "$CLAMD_SERVICE" || true
    fi
}

# ===================
# Scanning
# ===================
scan_usb() {
    local mount_point="$1"
    local label="$2"

    log "Starting ClamAV scan of $mount_point"

    # Try clamdscan (multi-threaded, faster)
    if start_clamd; then
        log "Using clamdscan (multi-threaded)"
        scan_with_clamdscan "$mount_point" "$label"
        return $?
    fi

    # Fallback to clamscan (single-threaded)
    log "clamd unavailable, using clamscan fallback (slower)"
    scan_with_clamscan "$mount_point" "$label"
    return $?
}

scan_with_clamdscan() {
    local mount_point="$1"
    local label="$2"

    # Build directory list, filtering out Windows system directories
    # (clamdscan does not support --exclude-dir)
    local dirs_to_scan=()
    while IFS= read -r -d '' entry; do
        local name
        name=$(basename "$entry")
        # shellcheck disable=SC2016
        if [[ "$name" != '$RECYCLE.BIN' && "$name" != 'System Volume Information' ]]; then
            dirs_to_scan+=("$entry")
        fi
    done < <(find "$mount_point" -maxdepth 1 -mindepth 1 \( -type f -o -type d \) -print0)

    if [[ ${#dirs_to_scan[@]} -eq 0 ]]; then
        log "USB drive is empty or contains only system directories"
        return 0
    fi

    local exit_code=0
    clamdscan --config-file="$CLAMD_CONF" --multiscan --infected \
        --fdpass --move="$QUARANTINE" \
        "${dirs_to_scan[@]}" >> "$LOG_FILE" 2>&1 || exit_code=$?

    return "$exit_code"
}

scan_with_clamscan() {
    local mount_point="$1"
    local label="$2"

    local exit_code=0
    clamscan -r -i --max-filesize=500M --max-scansize=500M \
        --move="$QUARANTINE" \
        --exclude-dir="^\$RECYCLE\.BIN" \
        --exclude-dir="^System Volume Information" \
        "$mount_point" >> "$LOG_FILE" 2>&1 || exit_code=$?

    return "$exit_code"
}

# ===================
# Main Handler
# ===================
handle_usb_device() {
    local device="$1"

    log "=== USB Device Detected: $device ==="

    local label size
    label=$(get_device_label "$device")
    size=$(get_device_size "$device")
    log "Device: $device | Label: $label | Size: $size"

    # Skip devices in fstab
    if is_in_fstab "$device"; then
        log "Device is in fstab — skipping"
        return 0
    fi

    # Wait for GNOME to auto-mount
    log "Waiting for auto-mount..."
    local mount_point
    if ! mount_point=$(wait_for_mount "$device"); then
        log_error "Device $device was not auto-mounted within 30s"
        notify "USB Scan Skipped" \
            "Drive not mounted. Mount manually to scan.\n$label ($size)" \
            "low" "drive-removable-media"
        return 0
    fi

    log "Device mounted at $mount_point"
    notify "Scanning USB Drive" "ClamAV scan in progress...\n$label ($size)" "normal" "security-medium"

    # Scan
    local scan_start
    scan_start=$(wc -l < "$LOG_FILE")
    local scan_result=0
    scan_usb "$mount_point" "$label" || scan_result=$?

    # ClamAV exit codes: 0=clean, 1=infected, 2=error
    if [[ $scan_result -eq 0 ]]; then
        log "Scan complete: No threats detected"
        notify "USB Drive Clean" \
            "No threats found.\n$label ($size)" \
            "normal" "security-high"

    elif [[ $scan_result -eq 1 ]]; then
        local infected_count
        infected_count=$(tail -n +"$scan_start" "$LOG_FILE" | grep -c "FOUND" || true)
        log_error "Scan complete: $infected_count infected file(s) quarantined"

        # Register quarantined files in state tracker
        if [[ -f "$QUARANTINE_STATE_LIB" ]]; then
            # shellcheck source=/dev/null
            source "$QUARANTINE_STATE_LIB"
            quarantine_state_register_found "$LOG_FILE" "$scan_start" "usb"
        fi

        notify "USB INFECTED" \
            "$infected_count virus(es) quarantined.\nCheck: $QUARANTINE\n$label" \
            "critical" "security-low"

    else
        log_error "Scan failed with exit code $scan_result"
        notify "USB Scan Error" \
            "ClamAV scan error. Check logs.\n$label" \
            "critical" "dialog-warning"
    fi
}

# ===================
# Main
# ===================
main() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (via udev or sudo)"
        exit 1
    fi

    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <device>"
        echo "Example: $0 /dev/sdb1"
        exit 1
    fi

    local device="$1"
    local dev_name
    dev_name=$(basename "$device")

    # Ensure directories exist
    mkdir -p "$LOG_DIR" "$QUARANTINE"
    chmod 700 "$QUARANTINE"
    touch "$LOG_FILE"

    # Per-device lock (prevent concurrent scans of same device)
    exec 9>"$LOCK_DIR/usb-clamscan-${dev_name}.lock"
    if ! flock -n 9; then
        echo "Scan already running for $device" >> "$LOG_FILE"
        exit 0
    fi

    trap 'stop_clamd' EXIT
    trap 'log_error "Script failed at line $LINENO"; exit 1' ERR

    log "USB ClamAV scan started - Target user: $TARGET_USER"

    # Validate device
    if [[ ! -b "$device" ]]; then
        log_error "Invalid block device: $device"
        exit 1
    fi

    # Wait for udev to finish processing
    sleep 2

    handle_usb_device "$device"
}

main "$@"
