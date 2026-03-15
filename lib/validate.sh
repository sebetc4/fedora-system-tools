#!/bin/bash
# =============================================================================
# VALIDATE.SH - Configuration validation helpers
# =============================================================================
# Reusable validators for configuration values with error accumulation.
# Validates booleans, integers, paths, and accumulates errors for display.
#
# Usage:
#   source "$LIB_DIR/validate.sh"
#
#   validation_reset
#   validate_required "backup.mount" "$MOUNT"
#   validate_boolean "snapshots.enabled" "$ENABLE_SNAPSHOTS"
#   validate_integer "snapshots.retention" "$RETENTION"
#   validate_path "backup.destination" "$DEST"
#   validation_check   # exits with error banner if any failures
# =============================================================================

[[ -n "${_LIB_VALIDATE_LOADED:-}" ]] && return 0
readonly _LIB_VALIDATE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# Internal error accumulator
_VALIDATION_ERRORS=()

# Reset accumulated errors (call before a new validation pass)
validation_reset() {
    _VALIDATION_ERRORS=()
}

# Add an error to the accumulator
validation_add_error() {
    _VALIDATION_ERRORS+=("$1")
}

# Check if any errors accumulated; if so, display and exit
# Optional: pass a label for the config file being validated
validation_check() {
    local config_label="${1:-}"

    if [[ ${#_VALIDATION_ERRORS[@]} -eq 0 ]]; then
        return 0
    fi

    echo "" >&2
    echo -e "${C_RED}${C_BOLD}Configuration errors:${C_NC}" >&2
    for err in "${_VALIDATION_ERRORS[@]}"; do
        echo -e "  ${C_RED}✗ $err${C_NC}" >&2
    done
    if [[ -n "$config_label" ]]; then
        echo "" >&2
        echo -e "${C_YELLOW}Config: $config_label${C_NC}" >&2
    fi
    echo "" >&2
    exit 1
}

# --- Individual validators ---------------------------------------------------

# Value must not be empty
validate_required() {
    local key="$1"
    local value="$2"
    if [[ -z "$value" ]]; then
        validation_add_error "$key is required"
    fi
}

# Value must be "true" or "false"
validate_boolean() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]] && [[ "$value" != "true" ]] && [[ "$value" != "false" ]]; then
        validation_add_error "$key must be 'true' or 'false' (got: '$value')"
    fi
}

# Value must be a positive integer
validate_integer() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]] && ! [[ "$value" =~ ^[0-9]+$ ]]; then
        validation_add_error "$key must be a number (got: '$value')"
    fi
}

# Value must be an absolute path starting with /
validate_path() {
    local key="$1"
    local value="$2"
    if [[ -n "$value" ]] && [[ ! "$value" =~ ^/ ]]; then
        validation_add_error "$key must be an absolute path starting with / (got: '$value')"
    fi
}

# Value must match a regex pattern
validate_pattern() {
    local key="$1"
    local value="$2"
    local pattern="$3"
    local hint="${4:-must match pattern: $pattern}"
    if [[ -n "$value" ]] && ! [[ "$value" =~ $pattern ]]; then
        validation_add_error "$key $hint (got: '$value')"
    fi
}
