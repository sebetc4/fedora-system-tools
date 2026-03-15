#!/bin/bash
# =============================================================================
# BACKUP UNINSTALL - Backup module uninstall orchestrator
# =============================================================================
# Uninstalls backup submodules selectively or entirely.
# Config files in ~/.config/backup/ are NOT removed (user data).
#
# Supports CLI flags:
#   --all         Uninstall all submodules (non-interactive)
#   --only <name> Uninstall specific submodule(s) (comma-separated)
#
# Module: backup
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/backup/uninstall.sh
#   sudo ./modules/backup/uninstall.sh --all
#   sudo ./modules/backup/uninstall.sh --only hdd,vps
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed." >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/submodule.sh"
source "$LIB_DIR/ui.sh"

check_root

# ===================
# Post-uninstall: config/logs reminder
# ===================
_module_post_uninstall() {
    local module_name="$1"
    local remaining
    remaining=$(registry_count_submodules "$module_name")
    if [[ "$remaining" -eq 0 ]]; then
        ui_banner "$module_name fully uninstalled" \
            "" \
            "Config files in ~/.config/backup/ were NOT removed (includes hooks/)."
    fi
}

submodule_run_uninstall "$SCRIPT_DIR" "$@"
ui_press_enter
