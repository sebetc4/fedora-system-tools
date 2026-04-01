#!/bin/bash
# =============================================================================
# BUILD-KERNEL UNINSTALL - Submodule orchestrator
# =============================================================================
# Uninstalls build-kernel submodules selectively or entirely.
#
# Module: build-kernel
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/build-kernel/uninstall.sh              # Interactive
#   sudo ./modules/build-kernel/uninstall.sh --all        # All submodules
#   sudo ./modules/build-kernel/uninstall.sh --only hook-aw88399
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

submodule_run_uninstall "$SCRIPT_DIR" "$@"
ui_press_enter
