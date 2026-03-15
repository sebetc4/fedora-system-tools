#!/bin/bash
# =============================================================================
# <MODULE> INSTALL - <Module name> installation
# =============================================================================
# Installs the <module> module: scripts, services, and configs.
#
# Example: modules/torrent/install.sh, modules/nautilus/install.sh
#
# Module: <module-name>
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/<module>/install.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MODULE_YML="$SCRIPT_DIR/module.yml"
readonly MODULE_NAME="<module>"
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    MODULE_VERSION="$(yq -r '.version' "$MODULE_YML")"
else
    MODULE_VERSION="0.1.0"
fi
readonly MODULE_VERSION

# ===================
# Check lib is installed
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: system-scripts library not found in $LIB_DIR" >&2
    echo "Install it first: make install-lib" >&2
    exit 1
fi
source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"

check_root

# ===================
# Detect calling user
# ===================
# CURRENT_USER="${SUDO_USER:-$USER}"
# readonly CURRENT_USER

# ===================
# Check module dependencies (if any)
# ===================
# if ! registry_is_installed "other-module"; then
#     error "Module 'other-module' is required. Install it first: make install-other-module"
#     exit 1
# fi

# ===================
# Check system dependencies (if any)
# ===================
# info "Checking system dependencies..."
# missing_deps=()
# for dep in curl jq; do
#     command -v "$dep" &>/dev/null || missing_deps+=("$dep")
# done
# if [[ ${#missing_deps[@]} -gt 0 ]]; then
#     info "Installing missing dependencies: ${missing_deps[*]}"
#     dnf install -y "${missing_deps[@]}"
# fi

# ===================
# Install binaries
# ===================
info "Installing $MODULE_NAME v$MODULE_VERSION..."

# install -m 755 "$SCRIPT_DIR/scripts/example.sh" /usr/local/bin/example

# ===================
# Install services & timers (if any)
# ===================
# install -m 644 "$SCRIPT_DIR/services/example.service" /etc/systemd/system/
# install -m 644 "$SCRIPT_DIR/timers/example.timer" /etc/systemd/system/
# systemctl daemon-reload
# systemctl enable --now example.timer

# ===================
# Register & done
# ===================
registry_set "$MODULE_NAME" "$MODULE_VERSION"

echo ""
success "$MODULE_NAME v$MODULE_VERSION installed"
echo ""
# echo "Commands available:"
# echo "  example       — Do something"
# echo ""
