#!/bin/bash
# =============================================================================
# FIREWALL INSTALL - Firewall module installation
# =============================================================================
# Installs the firewall-harden CLI, generates default config if absent,
# and applies firewall hardening rules.
#
# Module: firewall
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/firewall/install.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MODULE_YML="$SCRIPT_DIR/module.yml"
readonly MODULE_NAME="firewall"
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
    echo "ERROR: system-scripts library not found in $LIB_DIR"
    echo "Install it first: make install-lib"
    exit 1
fi
source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/ui.sh"

# Check minimum lib version
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    _min_lib=$(yq -r '.min_lib_version // ""' "$MODULE_YML")
    if [[ -n "$_min_lib" ]]; then
        _lib_cmp=$(version_compare "$LIB_VERSION" "$_min_lib" 2>/dev/null || echo "ok")
        if [[ "$_lib_cmp" == "lt" ]]; then
            echo "ERROR: Module $MODULE_NAME requires lib >= $_min_lib (installed: $LIB_VERSION). Run: make install-lib" >&2
            exit 1
        fi
    fi
fi

check_root

# ===================
# Install CLI binary
# ===================
info "Installing $MODULE_NAME v$MODULE_VERSION..."

install -m 755 "$SCRIPT_DIR/scripts/firewall-harden.sh" /usr/local/bin/firewall-harden

# ===================
# Install default config
# ===================
readonly CONF_DIR="/etc/system-scripts"
readonly CONF_FILE="$CONF_DIR/firewall.conf"

mkdir -p "$CONF_DIR"

if [[ ! -f "$CONF_FILE" ]]; then
    install -m 644 "$SCRIPT_DIR/templates/firewall.conf.default" "$CONF_FILE"
    info "Default config installed: $CONF_FILE"
else
    info "Config already exists: $CONF_FILE (preserved)"
fi

# ===================
# Apply firewall rules
# ===================
bash "$SCRIPT_DIR/scripts/configure-firewall.sh"

# ===================
# Register & done
# ===================
registry_set "$MODULE_NAME" "$MODULE_VERSION"

ui_banner "$MODULE_NAME v$MODULE_VERSION installed" \
    "" \
    "Usage:" \
    "  sudo firewall-harden         — Apply hardening rules" \
    "  sudo firewall-harden --help  — Show options" \
    "" \
    "Config: /etc/system-scripts/firewall.conf"

ui_press_enter
