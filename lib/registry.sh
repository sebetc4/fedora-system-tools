#!/bin/bash
# =============================================================================
# REGISTRY.SH - Module installation registry management
# =============================================================================
# Tracks installed modules and their versions in a persistent INI-style
# registry file. Provides functions to read, write, and compare versions.
#
# Registry locations:
#   System: /etc/system-scripts/registry              (root modules)
#   User:   ~/.config/system-scripts/registry        (user modules)
#
# Usage: source "$LIB_DIR/registry.sh"
#
# Includes double-sourcing protection.
# =============================================================================

# Double-sourcing guard
[[ -n "${_LIB_REGISTRY_LOADED:-}" ]] && return 0
readonly _LIB_REGISTRY_LOADED=1

# =============================================================================
# CONSTANTS
# =============================================================================

readonly SYSTEM_REGISTRY="/etc/system-scripts/registry"
readonly USER_REGISTRY="${HOME}/.config/system-scripts/registry"

# =============================================================================
# REGISTRY PATH
# =============================================================================

# Get registry path based on effective user ID
# Returns: system registry if root, user registry otherwise
# Override: set REGISTRY_PATH_OVERRIDE to force a specific path
#           (used by submodule engine for user-type submodules running under sudo)
registry_get_path() {
    if [[ -n "${REGISTRY_PATH_OVERRIDE:-}" ]]; then
        echo "$REGISTRY_PATH_OVERRIDE"
    elif [[ $EUID -eq 0 ]]; then
        echo "$SYSTEM_REGISTRY"
    else
        echo "$USER_REGISTRY"
    fi
}

# =============================================================================
# INIT
# =============================================================================

# Ensure registry file exists, create with header if not
# When running under sudo with REGISTRY_PATH_OVERRIDE (user-type submodules),
# ensures the registry dir and file are owned by the real user.
registry_init() {
    local registry_path
    registry_path="$(registry_get_path)"
    local registry_dir
    registry_dir="$(dirname "$registry_path")"

    local created=false
    if [[ ! -d "$registry_dir" ]]; then
        mkdir -p "$registry_dir"
        created=true
    fi
    if [[ ! -f "$registry_path" ]]; then
        echo "# Fedora System Tools - Installation Registry" > "$registry_path"
        created=true
    fi

    # Fix ownership when writing to user registry under sudo
    if [[ "$created" == "true" && -n "${REGISTRY_PATH_OVERRIDE:-}" && -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER:$SUDO_USER" "$registry_dir" "$registry_path"
    fi
}

# =============================================================================
# WRITE OPERATIONS
# =============================================================================

# Register or update a module in the registry
# Args: module_name version
registry_set() {
    local module="$1"
    local version="$2"

    registry_init

    local registry_path
    registry_path="$(registry_get_path)"

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    # Remove existing entry if present
    registry_remove "$module" 2>/dev/null || true

    # Append new entry
    {
        echo ""
        echo "[$module]"
        echo "version=$version"
        echo "installed=$timestamp"
    } >> "$registry_path"
}

# Remove a module entry from the registry
# Args: module_name
registry_remove() {
    local module="$1"
    local registry_path
    registry_path="$(registry_get_path)"

    [[ ! -f "$registry_path" ]] && return 0

    # Use awk to remove the section (header + key=value lines until next section or EOF)
    awk -v mod="[$module]" '
        BEGIN { skip = 0 }
        /^\[/ { skip = ($0 == mod) ? 1 : 0 }
        !skip { print }
    ' "$registry_path" > "${registry_path}.tmp"

    mv "${registry_path}.tmp" "$registry_path"
}

# =============================================================================
# READ OPERATIONS
# =============================================================================

# Get the installed version of a module
# Args: module_name
# Returns: version string on stdout, return 1 if not found
registry_get_version() {
    local module="$1"
    local registry_path
    registry_path="$(registry_get_path)"

    [[ ! -f "$registry_path" ]] && return 1

    awk -v mod="[$module]" '
        BEGIN { found = 0 }
        /^\[/ { found = ($0 == mod) ? 1 : 0; next }
        found && /^version=/ { sub(/^version=/, ""); print; exit }
    ' "$registry_path"
}

# Check if a module is installed in the registry
# Args: module_name
# Returns: 0 if installed, 1 otherwise
registry_is_installed() {
    local module="$1"
    local version
    version="$(registry_get_version "$module" 2>/dev/null)" || return 1
    [[ -n "$version" ]]
}

# =============================================================================
# SUBMODULE OPERATIONS
# =============================================================================

# Register or update a submodule in the registry
# Also creates the parent module entry if it doesn't exist
# Args: module_name submodule_name version [module_version]
registry_set_submodule() {
    local module="$1"
    local submodule="$2"
    local version="$3"
    local module_version="${4:-}"

    # Create parent module entry if not present
    if [[ -n "$module_version" ]] && ! registry_is_installed "$module"; then
        registry_set "$module" "$module_version"
    fi

    # Register the submodule as module/submodule
    registry_set "${module}/${submodule}" "$version"
}

# Remove a submodule entry from the registry
# If no submodules remain, removes the parent module entry too
# Args: module_name submodule_name
registry_remove_submodule() {
    local module="$1"
    local submodule="$2"

    registry_remove "${module}/${submodule}"

    # If no submodules remain, remove parent module entry
    local remaining
    remaining=$(registry_count_submodules "$module")
    if [[ "$remaining" -eq 0 ]]; then
        registry_remove "$module"
    fi
}

# Get the installed version of a submodule
# Args: module_name submodule_name
# Returns: version string on stdout, return 1 if not found
registry_get_submodule_version() {
    local module="$1"
    local submodule="$2"

    registry_get_version "${module}/${submodule}"
}

# Check if a submodule is installed
# Args: module_name submodule_name
# Returns: 0 if installed, 1 otherwise
registry_is_submodule_installed() {
    local module="$1"
    local submodule="$2"

    registry_is_installed "${module}/${submodule}"
}

# List all installed submodule names for a module (one per line)
# Args: module_name
# Output: submodule names (without module prefix)
registry_list_submodules() {
    local module="$1"
    local registry_path
    registry_path="$(registry_get_path)"

    [[ ! -f "$registry_path" ]] && return 0

    grep -oP "^\[${module}/\K[^\]]+" "$registry_path"
}

# Count installed submodules for a module
# Args: module_name
# Output: count (integer)
registry_count_submodules() {
    local module="$1"
    local count
    count=$(registry_list_submodules "$module" 2>/dev/null | wc -l)
    echo "$count"
}

# =============================================================================
# VERSION COMPARISON
# =============================================================================

# Compare two semantic versions
# Args: version_a version_b
# Prints: "lt" if a < b, "eq" if a == b, "gt" if a > b
version_compare() {
    local v1="$1"
    local v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        echo "eq"
        return
    fi

    local IFS='.'
    read -ra V1 <<< "$v1"
    read -ra V2 <<< "$v2"

    local i
    for i in 0 1 2; do
        local n1="${V1[$i]:-0}"
        local n2="${V2[$i]:-0}"

        if (( n1 < n2 )); then
            echo "lt"
            return
        elif (( n1 > n2 )); then
            echo "gt"
            return
        fi
    done

    echo "eq"
}
