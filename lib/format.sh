#!/bin/bash
# =============================================================================
# FORMAT.SH - Shared formatting functions
# =============================================================================
# Size, date, and filename formatting utilities.
# Used by torrent-list, torrent-move, quarantine, etc.
#
# Usage:
#   source "$LIB_DIR/format.sh"
#   format_size 1073741824    # -> "1.0 GB"
#   format_date 1700000000    # -> "2023-11-14"
#   truncate_name "very long name..." 20
# =============================================================================

[[ -n "${_LIB_FORMAT_LOADED:-}" ]] && return 0
readonly _LIB_FORMAT_LOADED=1

format_size() {
    local size="$1"
    if [[ $size -gt 1073741824 ]]; then
        echo "$(echo "scale=1; $size/1073741824" | bc) GB"
    elif [[ $size -gt 1048576 ]]; then
        echo "$(echo "scale=1; $size/1048576" | bc) MB"
    elif [[ $size -gt 1024 ]]; then
        echo "$(echo "scale=1; $size/1024" | bc) KB"
    else
        echo "$size B"
    fi
}

format_date() {
    local timestamp="$1"
    date -d "@$timestamp" '+%Y-%m-%d' 2>/dev/null || echo "?"
}

truncate_name() {
    local name="$1" max="${2:-38}"
    if [[ ${#name} -gt $max ]]; then
        echo "${name:0:$((max-3))}..."
    else
        echo "$name"
    fi
}
