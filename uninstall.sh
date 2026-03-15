#!/bin/bash
# =============================================================================
# UNINSTALL - Complete removal of Fedora System Tools
# =============================================================================
# Removes all installed modules, the shared library, configuration files,
# registries, and the /opt/fedora-system-tools installation directory.
#
# This is the reverse of install.sh (the curl one-liner bootstrap).
#
# Usage:
#   sudo ./uninstall.sh          # Interactive confirmation
#   sudo ./uninstall.sh --yes    # Skip confirmation
#
# Requires: bash 4+, sudo
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly INSTALL_DIR="/opt/fedora-system-tools"
readonly LIB_INSTALL_DIR="/usr/local/lib/system-scripts"
readonly CONFIG_DIR="/etc/system-scripts"
readonly SYMLINK_PATH="/usr/local/bin/system-tools"

# Colors (disabled if not a terminal)
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_NC='\033[0m'

if [[ ! -t 1 ]]; then
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BOLD='' C_NC=''
fi

error()   { echo -e "${C_RED}Error: $1${C_NC}" >&2; }
success() { echo -e "${C_GREEN}✓ $1${C_NC}"; }
info()    { echo -e "${C_CYAN}$1${C_NC}"; }
warn()    { echo -e "${C_YELLOW}Warning: $1${C_NC}" >&2; }

# =============================================================================
# PARSE ARGUMENTS
# =============================================================================

SKIP_CONFIRM=false
for arg in "$@"; do
    case "$arg" in
        --yes|-y) SKIP_CONFIRM=true ;;
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

# =============================================================================
# ROOT CHECK
# =============================================================================

if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (sudo ./uninstall.sh)"
    exit 1
fi

# =============================================================================
# PRE-FLIGHT CHECK
# =============================================================================

if [[ ! -d "$INSTALL_DIR" ]] && [[ ! -d "$LIB_INSTALL_DIR" ]] && [[ ! -d "$CONFIG_DIR" ]]; then
    info "Fedora System Tools does not appear to be installed."
    exit 0
fi

# =============================================================================
# UNINSTALL MODULES
# =============================================================================

uninstall_all_modules() {
    local registry="$CONFIG_DIR/registry"
    [[ ! -f "$registry" ]] && return 0

    # Collect installed modules (exclude lib)
    local modules=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^\[([a-z]+)\]$ ]]; then
            local module="${BASH_REMATCH[1]}"
            [[ "$module" != "lib" ]] && modules+=("$module")
        fi
    done < "$registry"

    # Deduplicate (submodule entries share the module prefix)
    local unique_modules=()
    local seen=""
    for m in "${modules[@]}"; do
        if [[ ! " $seen " =~ \ $m\  ]]; then
            unique_modules+=("$m")
            seen="$seen $m"
        fi
    done

    if [[ ${#unique_modules[@]} -eq 0 ]]; then
        info "No modules installed"
        return 0
    fi

    for module in "${unique_modules[@]}"; do
        local uninstaller="$INSTALL_DIR/modules/$module/uninstall.sh"
        if [[ -f "$uninstaller" ]]; then
            info "Uninstalling module: $module..."
            NONINTERACTIVE=1 bash "$uninstaller" --all 2>/dev/null || warn "Module '$module' uninstall had errors"
        else
            warn "No uninstaller found for module '$module' — skipping"
        fi
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}Fedora System Tools — Complete Uninstall${C_NC}"
    echo ""

    # --- Show what will be removed ---
    info "The following will be removed:"
    [[ -d "$INSTALL_DIR" ]]     && echo "  - $INSTALL_DIR"
    [[ -d "$LIB_INSTALL_DIR" ]] && echo "  - $LIB_INSTALL_DIR"
    [[ -d "$CONFIG_DIR" ]]      && echo "  - $CONFIG_DIR (registry, configs)"
    [[ -L "$SYMLINK_PATH" ]]    && echo "  - $SYMLINK_PATH (symlink)"

    local user_registry
    user_registry="$(eval echo ~"${SUDO_USER:-$USER}")/.config/system-scripts"
    if [[ -d "$user_registry" ]]; then
        echo "  - $user_registry (user registry)"
    fi
    echo ""

    # --- Confirmation ---
    if [[ "$SKIP_CONFIRM" != true ]]; then
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

    # --- 5. Remove user registry ---
    if [[ -d "$user_registry" ]]; then
        rm -rf "$user_registry"
        success "Removed $user_registry"
    fi

    # --- 6. Remove installation directory ---
    if [[ -d "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        success "Removed $INSTALL_DIR"
    fi

    echo ""
    success "Fedora System Tools completely uninstalled."
    echo ""
    echo -e "${C_BOLD}Note:${C_NC} Gum (if installed) was not removed."
    echo "  To remove it: sudo dnf remove gum"
    echo ""
}

main
