#!/bin/bash
# =============================================================================
# UNINSTALL - Complete removal of Fedora System Tools
# =============================================================================
# Uninstalls every installed module through its own uninstaller, then removes
# the shared library, /etc/system-scripts, the user registry and the
# /opt/fedora-system-tools installation directory. The user's own files in
# the home (module configs, bookmarks.conf, color.conf) stay, as each
# module's uninstall keeps them.
#
# This is the reverse of install.sh (the curl one-liner bootstrap), and runs
# from a checkout or from /opt/fedora-system-tools alike.
#
# Usage:
#   sudo ./uninstall.sh          # Interactive confirmation
#   sudo ./uninstall.sh --yes    # Skip confirmation
#
# Module: setup
# Requires: core, registry
# Version: 0.2.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/registry.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly INSTALL_DIR="/opt/fedora-system-tools"
readonly LIB_INSTALL_DIR="/usr/local/lib/system-scripts"
readonly CONFIG_DIR="/etc/system-scripts"
readonly SYMLINK_PATH="/usr/local/bin/system-tools"

# The user the uninstall acts for, and the user registry (set by main)
REAL_USER=""
REAL_REGISTRY=""

# =============================================================================
# UNINSTALL MODULES
# =============================================================================

# Succeed when a module has an entry in the system registry or the user's
# Args: module
module_installed() {
    REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" registry_is_installed "$1" \
        || REGISTRY_PATH_OVERRIDE="$REAL_REGISTRY" registry_is_installed "$1"
}

# Run each installed module's uninstaller: as root for a system module, as the
# user for a user module, which refuses root
uninstall_all_modules() {
    local yml name type dir args found=false
    for yml in "$SCRIPT_DIR"/modules/*/module.yml; do
        [[ -f "$yml" ]] || continue
        name=$(yq -r '.name' "$yml")
        module_installed "$name" || continue
        found=true
        type=$(yq -r '.type // "system"' "$yml")
        dir=$(dirname "$yml")
        args=()
        if [[ "$(yq -r '.standalone // false' "$yml")" != "true" ]]; then
            args=(--all)
        fi

        info "Uninstalling module: $name..."
        if [[ "$type" == "user" && "$REAL_USER" != "root" ]]; then
            runuser -u "$REAL_USER" -- env NONINTERACTIVE=1 \
                XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")" \
                bash "$dir/uninstall.sh" "${args[@]}" \
                || warn "Module '$name' uninstall had errors"
        else
            NONINTERACTIVE=1 bash "$dir/uninstall.sh" "${args[@]}" \
                || warn "Module '$name' uninstall had errors"
        fi
    done
    if [[ "$found" == "false" ]]; then
        info "No modules installed"
    fi
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local arg skip_confirm=false
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) skip_confirm=true ;;
            --help|-h)
                echo "Usage: sudo ./uninstall.sh [--yes]"
                echo "  --yes, -y    Skip confirmation prompt"
                exit 0
                ;;
            *)
                error "Unknown option: $arg"
                exit 1
                ;;
        esac
    done

    check_root
    check_deps yq

    REAL_USER="${SUDO_USER:-root}"
    local real_home
    real_home=$(getent passwd "$REAL_USER" | cut -d: -f6) || true
    [[ -n "$real_home" ]] || error "No home found for user '$REAL_USER'" "exit"
    REAL_REGISTRY="$real_home/.config/system-scripts/registry"

    echo ""
    echo -e "${C_BOLD}${C_CYAN}Fedora System Tools — Complete Uninstall${C_NC}"
    echo ""

    if [[ ! -d "$INSTALL_DIR" && ! -d "$LIB_INSTALL_DIR" && ! -d "$CONFIG_DIR" && ! -f "$REAL_REGISTRY" ]]; then
        info "Fedora System Tools does not appear to be installed."
        exit 0
    fi

    # --- Show what will be removed ---
    info "The following will be removed:"
    echo "  - every installed module, through its own uninstaller"
    [[ -d "$LIB_INSTALL_DIR" ]] && echo "  - $LIB_INSTALL_DIR"
    [[ -d "$CONFIG_DIR" ]]      && echo "  - $CONFIG_DIR (registry, configs)"
    [[ -L "$SYMLINK_PATH" ]]    && echo "  - $SYMLINK_PATH (symlink)"
    [[ -f "$REAL_REGISTRY" ]]   && echo "  - $REAL_REGISTRY (user registry)"
    [[ -d "$INSTALL_DIR" ]]     && echo "  - $INSTALL_DIR"
    echo ""

    # --- Confirmation ---
    if [[ "$skip_confirm" != true ]]; then
        local confirm
        read -r -p "Proceed with complete uninstall? [y/N] " confirm
        if [[ "${confirm,,}" != "y" ]]; then
            info "Cancelled."
            exit 0
        fi
        echo ""
    fi

    # --- 1. Uninstall all modules ---
    uninstall_all_modules

    # --- 2. Remove shared library ---
    if [[ -d "$LIB_INSTALL_DIR" ]]; then
        rm -rf "$LIB_INSTALL_DIR"
        success "Removed $LIB_INSTALL_DIR"
    fi

    # --- 3. Remove symlink ---
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH"
        success "Removed $SYMLINK_PATH"
    fi

    # --- 4. Remove config directory (registry, paths.conf, color.conf) ---
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
        success "Removed $CONFIG_DIR"
    fi

    # --- 5. Remove the user registry, and its folder once empty ---
    if [[ -f "$REAL_REGISTRY" ]]; then
        rm -f "$REAL_REGISTRY"
        rmdir --ignore-fail-on-non-empty "$(dirname "$REAL_REGISTRY")"
        success "Removed $REAL_REGISTRY"
    fi

    # --- 6. Remove installation directory ---
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        success "Removed $INSTALL_DIR"
    fi

    echo ""
    success "Fedora System Tools completely uninstalled."
    echo ""
    echo -e "${C_BOLD}Note:${C_NC} yq and gum, installed from Fedora's repositories, stay."
    echo "  To remove them: sudo dnf remove yq gum"
    echo ""
}

# Sourced by the tests, which call its functions alone
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
