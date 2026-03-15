#!/bin/bash
# =============================================================================
# CONFIG.SH - Centralized configuration loading
# =============================================================================
# Loads the paths.conf config file used by torrent, clamav,
# and download-clamscan scripts.
#
# Usage:
#   source "$LIB_DIR/config.sh"
#   load_config                         # Loads /etc/system-scripts/paths.conf
#   load_config "/etc/custom.conf"      # Loads a specific file
# =============================================================================

[[ -n "${_LIB_CONFIG_LOADED:-}" ]] && return 0
readonly _LIB_CONFIG_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

readonly DEFAULT_CONFIG="/etc/system-scripts/paths.conf"

load_config() {
    local config="${1:-$DEFAULT_CONFIG}"
    if [[ -f "$config" ]]; then
        # shellcheck source=/dev/null
        source "$config"
    else
        error "Configuration file not found: $config" "exit"
    fi
}
