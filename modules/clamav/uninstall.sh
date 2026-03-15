#!/bin/bash
# =============================================================================
# CLAMAV UNINSTALL - ClamAV module uninstall orchestrator
# =============================================================================
# Uninstalls ClamAV submodules selectively or entirely.
# Does NOT remove ClamAV packages or quarantine data.
#
# Supports CLI flags:
#   --all         Uninstall all submodules (non-interactive)
#   --only <name> Uninstall specific submodule(s) (comma-separated)
#
# Module: clamav
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/clamav/uninstall.sh              # Interactive
#   sudo ./modules/clamav/uninstall.sh --all         # All submodules
#   sudo ./modules/clamav/uninstall.sh --only quarantine
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
# Post-uninstall: ClamAV cleanup reminder
# ===================
_module_post_uninstall() {
    local module_name="$1"
    local remaining
    remaining=$(registry_count_submodules "$module_name")
    if [[ "$remaining" -eq 0 ]]; then
        ui_banner "$module_name fully uninstalled" \
            "" \
            "ClamAV packages were NOT removed." \
            "  To remove: sudo dnf remove clamav clamav-update clamd"
    fi
}

submodule_run_uninstall "$SCRIPT_DIR" "$@"
ui_press_enter
