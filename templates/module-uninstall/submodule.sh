#!/bin/bash
# =============================================================================
# <MODULE> UNINSTALL - <Module name> uninstall orchestrator
# =============================================================================
# Uninstalls <module> submodules selectively or entirely.
#
# Supports CLI flags:
#   --all         Uninstall all submodules (non-interactive)
#   --only <name> Uninstall specific submodule(s) (comma-separated)
#
# Delegates orchestration to submodule_run_uninstall() in lib/submodule.sh.
# Example: modules/clamav/uninstall.sh, modules/backup/uninstall.sh
#
# Module: <module-name>
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/<module>/uninstall.sh              # Interactive
#   sudo ./modules/<module>/uninstall.sh --all         # All submodules
#   sudo ./modules/<module>/uninstall.sh --only sub1
# =============================================================================

set -euo pipefail

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

# Optional: pre-uninstall cleanup
# _module_pre_uninstall() {
#     # Custom cleanup before submodule uninstall loop
# }

# Optional: post-uninstall messages
# _module_post_uninstall() {
#     local module_name="$1"
#     local remaining
#     remaining=$(registry_count_submodules "$module_name")
#     if [[ "$remaining" -eq 0 ]]; then
#         warn "Config files were NOT removed."
#     fi
# }

submodule_run_uninstall "$SCRIPT_DIR" "$@"
