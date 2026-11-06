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

# Each unit starts at its exact size (1024 -> "1.0 KB"); one decimal, rounded
format_size() {
    local size="$1"
    if [[ $size -ge 1073741824 ]]; then
        awk -v s="$size" 'BEGIN { printf "%.1f GB\n", s / 1073741824 }'
    elif [[ $size -ge 1048576 ]]; then
        awk -v s="$size" 'BEGIN { printf "%.1f MB\n", s / 1048576 }'
    elif [[ $size -ge 1024 ]]; then
        awk -v s="$size" 'BEGIN { printf "%.1f KB\n", s / 1024 }'
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
