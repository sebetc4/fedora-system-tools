#!/bin/bash
# =============================================================================
# YAML.SH - YAML configuration parsing via yq
# =============================================================================
# Read values and arrays from YAML configuration files.
# Requires: yq (https://github.com/mikefarah/yq)
#
# Configuration:
#   YAML_FILE="/path/to/config.yml"     # Set before calling functions
#
# Usage:
#   source "$LIB_DIR/yaml.sh"
#   YAML_FILE="$HOME/.config/backup/config.yml"
#   value=$(parse_yaml "backup.hdd_mount")
#   parse_yaml_array "exclusions.home" | while read -r item; do ... done
#
# List/object access:
#   count=$(parse_yaml_count "paths")
#   name=$(parse_yaml_index "paths" 0 "name")
#   parse_yaml_index_array "paths" 0 "exclusions" | while read -r excl; do ... done
# =============================================================================

[[ -n "${_LIB_YAML_LOADED:-}" ]] && return 0
readonly _LIB_YAML_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# Config file path — must be set by the calling script
YAML_FILE="${YAML_FILE:-}"

# Parse a single value from the YAML file
# Returns empty string for null/missing values
parse_yaml() {
    local key="$1"
    local file="${2:-$YAML_FILE}"

    if [[ -z "$file" ]]; then
        error "YAML_FILE not set" "exit"
    fi

    if [[ ! -f "$file" ]]; then
        error "YAML file not found: $file" "exit"
    fi

    local value
    value=$(yq e ".${key}" "$file" 2>/dev/null)

    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# Parse an array from the YAML file
# Outputs one item per line, skipping nulls
parse_yaml_array() {
    local key="$1"
    local file="${2:-$YAML_FILE}"

    if [[ -z "$file" ]]; then
        error "YAML_FILE not set" "exit"
    fi

    if [[ ! -f "$file" ]]; then
        error "YAML file not found: $file" "exit"
    fi

    yq e ".${key}[]" "$file" 2>/dev/null | grep -v '^null$'
}

# =============================================================================
# LIST/OBJECT ACCESS
# =============================================================================
# Functions for accessing YAML lists of objects (e.g., paths[], hooks[]).

# Count elements in a YAML list
# Returns 0 for null/missing lists
#   count=$(parse_yaml_count "paths")
parse_yaml_count() {
    local key="$1"
    local file="${2:-$YAML_FILE}"

    if [[ -z "$file" ]]; then
        error "YAML_FILE not set" "exit"
    fi

    local count
    count=$(yq e ".${key} | length" "$file" 2>/dev/null)

    if [[ "$count" == "null" ]] || [[ -z "$count" ]]; then
        echo "0"
    else
        echo "$count"
    fi
}

# Read a field from a list element by index
# Returns empty string for null/missing values
#   name=$(parse_yaml_index "paths" 0 "name")
parse_yaml_index() {
    local key="$1"
    local index="$2"
    local field="$3"
    local file="${4:-$YAML_FILE}"

    if [[ -z "$file" ]]; then
        error "YAML_FILE not set" "exit"
    fi

    local value
    value=$(yq e ".${key}[${index}].${field}" "$file" 2>/dev/null)

    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# Read an array field from a list element by index
# Outputs one item per line, skipping nulls
#   parse_yaml_index_array "paths" 0 "exclusions" | while read -r excl; do ... done
parse_yaml_index_array() {
    local key="$1"
    local index="$2"
    local field="$3"
    local file="${4:-$YAML_FILE}"

    if [[ -z "$file" ]]; then
        error "YAML_FILE not set" "exit"
    fi

    yq e ".${key}[${index}].${field}[]" "$file" 2>/dev/null | grep -v '^null$'
}
