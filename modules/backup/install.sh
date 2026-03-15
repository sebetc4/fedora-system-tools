#!/bin/bash
# =============================================================================
# BACKUP INSTALL - Backup module orchestrator
# =============================================================================
# Installs backup submodules: system, hdd, hdd-both, bitwarden, vps.
#
# Supports interactive multi-select and CLI flags:
#   --all         Install all submodules (non-interactive)
#   --only <name> Install specific submodule(s) (comma-separated)
#
# Module: backup
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/backup/install.sh
#   sudo ./modules/backup/install.sh --all
#   sudo ./modules/backup/install.sh --only hdd,vps
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed. Run: sudo ./lib/install.sh" >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/submodule.sh"
source "$LIB_DIR/ui.sh"

check_root
check_deps yq

# ===================
# Post-install: show config directory and next steps
# ===================
_module_post_install() {
    local _module_name="$1"
    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(getent passwd "$real_user" | cut -d: -f6)
    local real_config_dir="$real_home/.config/backup"

    ui_banner "$_module_name installation complete" \
        "" \
        "Configuration:" \
        "  $real_config_dir/" \
        "" \
        "Next steps:" \
        "  1. Edit configs: nano $real_config_dir/<config>.yml" \
        "  2. Test backup:  sudo <command> --dry-run"
}

submodule_run_install "$SCRIPT_DIR" "$@"
ui_press_enter
