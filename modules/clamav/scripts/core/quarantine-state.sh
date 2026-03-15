#!/bin/bash
# =============================================================================
# QUARANTINE-STATE - State tracking library for quarantined files
# =============================================================================
# Shared library sourced by scan scripts and the quarantine manager tool.
# Tracks quarantined files with original path, date, source, detection name,
# and pending/confirmed status in a pipe-delimited state file.
#
# State file: /etc/system-scripts/quarantine.state
# Format: filename|original_path|date|source|status|detection
#
# Module: clamav
# Requires: none (self-contained, sourced by service scripts)
# Version: 0.1.0
# =============================================================================

[[ -n "${_LIB_QUARANTINE_STATE_LOADED:-}" ]] && return 0
readonly _LIB_QUARANTINE_STATE_LOADED=1

readonly QUARANTINE_STATE_FILE="${QUARANTINE_STATE_FILE:-/etc/system-scripts/quarantine.state}"
readonly QUARANTINE_STATE_LOCK="/run/lock/quarantine-state.lock"

# ===================
# Internal helpers
# ===================

# Run a callback with exclusive lock on the state file.
# Usage: _quarantine_state_locked <callback_function> [args...]
_quarantine_state_locked() {
    local callback="$1"
    shift

    # Ensure state directory exists
    mkdir -p "$(dirname "$QUARANTINE_STATE_FILE")"

    local lock_fd
    exec {lock_fd}>"$QUARANTINE_STATE_LOCK"
    flock "$lock_fd"
    "$callback" "$@"
    local rc=$?
    flock -u "$lock_fd"
    exec {lock_fd}>&-
    return $rc
}

# ===================
# Public API
# ===================

# Add a quarantined file entry to the state.
# Usage: quarantine_state_add <filename> <original_path> <source> [detection]
#   filename      — basename of the file in /var/quarantine/
#   original_path — full path where the file was before quarantine
#   source        — scanner that detected it (daily, weekly, download, usb)
#   detection     — virus/threat name (optional, default: "unknown")
quarantine_state_add() {
    local filename="$1"
    local original_path="$2"
    local source="$3"
    local detection="${4:-unknown}"
    local date
    date=$(date '+%Y-%m-%d %H:%M:%S')

    _quarantine_state_locked _quarantine_state_add_impl \
        "$filename" "$original_path" "$date" "$source" "$detection"
}

_quarantine_state_add_impl() {
    local filename="$1"
    local original_path="$2"
    local date="$3"
    local source="$4"
    local detection="$5"

    # Remove existing entry for same filename (replace on re-quarantine)
    if [[ -f "$QUARANTINE_STATE_FILE" ]]; then
        local tmp
        tmp=$(grep -v "^${filename}|" "$QUARANTINE_STATE_FILE" 2>/dev/null || true)
        echo "$tmp" > "$QUARANTINE_STATE_FILE"
    fi

    echo "${filename}|${original_path}|${date}|${source}|pending|${detection}" \
        >> "$QUARANTINE_STATE_FILE"
}

# Remove a quarantined file entry from the state.
# Usage: quarantine_state_remove <filename>
quarantine_state_remove() {
    local filename="$1"
    _quarantine_state_locked _quarantine_state_remove_impl "$filename"
}

_quarantine_state_remove_impl() {
    local filename="$1"
    [[ -f "$QUARANTINE_STATE_FILE" ]] || return 0

    local tmp
    tmp=$(grep -v "^${filename}|" "$QUARANTINE_STATE_FILE" 2>/dev/null || true)
    echo "$tmp" > "$QUARANTINE_STATE_FILE"
    # Remove trailing empty lines
    sed -i '/^$/d' "$QUARANTINE_STATE_FILE"
}

# Get state entry for a quarantined file.
# Usage: quarantine_state_get <filename>
# Output: filename|original_path|date|source|status|detection
# Returns 1 if not found.
quarantine_state_get() {
    local filename="$1"
    [[ -f "$QUARANTINE_STATE_FILE" ]] || return 1
    grep "^${filename}|" "$QUARANTINE_STATE_FILE" 2>/dev/null || return 1
}

# Confirm a pending file (change status from pending to confirmed).
# Usage: quarantine_state_confirm <filename>
# Returns 1 if not found.
quarantine_state_confirm() {
    local filename="$1"
    _quarantine_state_locked _quarantine_state_confirm_impl "$filename"
}

_quarantine_state_confirm_impl() {
    local filename="$1"
    [[ -f "$QUARANTINE_STATE_FILE" ]] || return 1

    if ! grep -q "^${filename}|" "$QUARANTINE_STATE_FILE" 2>/dev/null; then
        return 1
    fi

    sed -i "s/^\(${filename}|.*|.*|.*|\)pending\(|.*\)$/\1confirmed\2/" \
        "$QUARANTINE_STATE_FILE"
}

# List state entries, optionally filtered by status.
# Usage: quarantine_state_list [pending|confirmed]
# Output: one line per entry (pipe-delimited)
quarantine_state_list() {
    local status_filter="${1:-}"
    [[ -f "$QUARANTINE_STATE_FILE" ]] || return 0

    if [[ -z "$status_filter" ]]; then
        grep -v '^$' "$QUARANTINE_STATE_FILE" 2>/dev/null || true
    else
        grep "|${status_filter}|" "$QUARANTINE_STATE_FILE" 2>/dev/null || true
    fi
}

# Clear all entries matching a status from the state file.
# Usage: quarantine_state_clear <pending|confirmed>
quarantine_state_clear() {
    local status="$1"
    _quarantine_state_locked _quarantine_state_clear_impl "$status"
}

_quarantine_state_clear_impl() {
    local status="$1"
    [[ -f "$QUARANTINE_STATE_FILE" ]] || return 0

    local tmp
    tmp=$(grep -v "|${status}|" "$QUARANTINE_STATE_FILE" 2>/dev/null || true)
    echo "$tmp" > "$QUARANTINE_STATE_FILE"
    sed -i '/^$/d' "$QUARANTINE_STATE_FILE"
}

# Parse FOUND lines from a clamdscan/clamscan log and register each
# quarantined file in the state.
# Usage: quarantine_state_register_found <log_file> <start_line> <source>
#   log_file   — path to the scan log
#   start_line — line number to start parsing from (skip previous scans)
#   source     — scanner name (daily, weekly, usb)
#
# clamdscan output format: /path/to/file: VirusName FOUND
quarantine_state_register_found() {
    local log_file="$1"
    local start_line="$2"
    local source="$3"

    tail -n +"$start_line" "$log_file" 2>/dev/null | grep "FOUND$" | while IFS= read -r line; do
        # Format: /original/path/to/file: Virus.Name FOUND
        local original_path detection filename

        # Extract original path (everything before ": ")
        original_path="${line%%: *}"
        # Extract detection name (between ": " and " FOUND")
        detection="${line#*: }"
        detection="${detection% FOUND}"
        # Filename is the basename of the original path
        filename=$(basename "$original_path")

        quarantine_state_add "$filename" "$original_path" "$source" "$detection"
    done
}
