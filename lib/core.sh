#!/bin/bash
# =============================================================================
# CORE.SH - Shared base for all system scripts
# =============================================================================
# Colors, typed messages, common checks, base utilities.
#
# Usage: source "$LIB_DIR/core.sh"
#
# Includes double-sourcing protection.
# =============================================================================

# Double-sourcing guard
[[ -n "${_LIB_CORE_LOADED:-}" ]] && return 0
readonly _LIB_CORE_LOADED=1
# shellcheck disable=SC2034  # used by scripts sourcing this lib
readonly LIB_VERSION="0.1.0"

# ===================
# Colors
# ===================
# C_ prefix to avoid conflicts with local script variables
#
# Semantic convention:
#   C_RED     → errors
#   C_GREEN   → success
#   C_YELLOW  → warnings
#   C_BLUE    → informational messages
#   C_CYAN    → section headers / borders (use with C_BOLD)
#   C_MAGENTA → special/highlight contexts
#   C_BOLD    → emphasis, prompts
#   C_DIM     → debug output
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_NC='\033[0m'

# Disable colors when not in an interactive terminal
if [[ ! -t 1 ]]; then
    # shellcheck disable=SC2034  # color vars used by scripts sourcing this lib
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BLUE=''
    # shellcheck disable=SC2034
    C_MAGENTA='' C_BOLD='' C_DIM='' C_NC=''
fi

# ===================
# Typed messages
# ===================
error() {
    echo -e "${C_RED}Error: $1${C_NC}" >&2
    if [[ "${2:-}" == "exit" ]]; then exit 1; fi
}

warn() {
    echo -e "${C_YELLOW}Warning: $1${C_NC}" >&2
}

success() {
    echo -e "${C_GREEN}✓ $1${C_NC}"
}

info() {
    echo -e "${C_BLUE}$1${C_NC}"
}

# Conditional debug — enable with DEBUG=1 or DEBUG=true
debug() {
    if [[ "${DEBUG:-false}" == "true" || "${DEBUG:-0}" == "1" ]]; then
        echo -e "${C_DIM}[DEBUG] $*${C_NC}"
    fi
}

# ===================
# Checks
# ===================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        if [[ -t 0 ]]; then
            warn "This script must be run as root"
            info "Re-running with sudo..."
            exec sudo "$0" "$@"
        else
            error "This script must be run as root (sudo)" "exit"
        fi
    fi
}

check_deps() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${C_RED}Error: Missing commands: ${missing[*]}${C_NC}" >&2
        exit 1
    fi
}

# ===================
# Gum detection
# ===================
has_gum() {
    command -v gum &>/dev/null
}
