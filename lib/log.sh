#!/bin/bash
# =============================================================================
# LOG.SH - Structured logging (stdout + file)
# =============================================================================
# Timestamped logging to stdout and optional log file.
# Each message is prefixed with a timestamp and colored by level.
#
# For desktop notifications, scripts should use logger directly:
#   logger -t "my-tag" -p user.PRIORITY "[ICON:icon-name] message"
# The notify-daemon handles the rest (see system/logs/).
#
# Configuration (define BEFORE or AFTER sourcing):
#   LOG_FILE="/var/log/myscript.log"    # Enable file logging (optional)
#   LOG_TIMESTAMP_FMT="%H:%M:%S"       # Timestamp format (default: %H:%M:%S)
#
# File descriptor mode (optional, for high-frequency logging):
#   LOG_FILE="/var/log/myscript.log"
#   log_open_fd                          # Opens FD3 on LOG_FILE (once)
#   log "message"                        # Writes to FD3 + console
#   log_close_fd                         # Closes FD3
#
# Usage:
#   source "$LIB_DIR/log.sh"
#   LOG_FILE="/var/log/myscript.log"
#   log "Standard message"
#   log_success "Operation completed"
#   log_error "Something failed"
#   log_warn "Watch out"
#   log_section "SECTION TITLE"
#   log_step "Doing something..."
# =============================================================================

[[ -n "${_LIB_LOG_LOADED:-}" ]] && return 0
readonly _LIB_LOG_LOADED=1

# Load core.sh if not already loaded
source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# Defaults (calling script can override after sourcing)
LOG_FILE="${LOG_FILE:-}"
LOG_TIMESTAMP_FMT="${LOG_TIMESTAMP_FMT:-%H:%M:%S}"

# FD mode state
_LOG_FD_OPENED=false

# =============================================================================
# File descriptor management (optional performance mode)
# =============================================================================

# Open FD3 on LOG_FILE for high-frequency logging.
# If LOG_FILE is empty or FD3 is already open, this is a no-op.
log_open_fd() {
    if [[ "$_LOG_FD_OPENED" == "false" ]] && [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null || true
        exec 3>>"$LOG_FILE"
        _LOG_FD_OPENED=true
    fi
}

# Close FD3 if open.
log_close_fd() {
    if [[ "$_LOG_FD_OPENED" == "true" ]]; then
        exec 3>&-
        _LOG_FD_OPENED=false
    fi
}

# Internal: write plain text to log file (FD3 or append)
_log_to_file() {
    if [[ "$_LOG_FD_OPENED" == "true" ]]; then
        printf '%s\n' "$1" >&3
    elif [[ -n "$LOG_FILE" ]]; then
        echo "$1" >> "$LOG_FILE"
    fi
}

# =============================================================================
# Log functions
# =============================================================================

log() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo -e "[${ts}] $*"
    _log_to_file "[${ts}] $*"
}

log_error() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo -e "[${ts}] ${C_RED}[ERROR] $*${C_NC}" >&2
    _log_to_file "[${ts}] [ERROR] $*"
}

log_success() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo -e "[${ts}] ${C_GREEN}✓ $*${C_NC}"
    _log_to_file "[${ts}] [OK] $*"
}

log_warn() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo -e "[${ts}] ${C_YELLOW}[WARN] $*${C_NC}" >&2
    _log_to_file "[${ts}] [WARN] $*"
}

log_section() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo ""
    echo -e "${C_BLUE}═══ $* ═══${C_NC}"
    echo ""
    _log_to_file ""
    _log_to_file "[${ts}] ═══ $* ═══"
    _log_to_file ""
}

log_step() {
    local ts
    ts=$(date "+$LOG_TIMESTAMP_FMT")
    echo -e "${C_CYAN}→${C_NC} $*"
    _log_to_file "[${ts}] → $*"
}
