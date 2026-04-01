#!/bin/bash
# =============================================================================
# BUILD-KERNEL INSTALL - Submodule orchestrator
# =============================================================================
# Installs build-kernel submodules: core, build-kernel, hook-aw88399.
#
# Module: build-kernel
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/build-kernel/install.sh              # Interactive
#   sudo ./modules/build-kernel/install.sh --all        # All submodules
#   sudo ./modules/build-kernel/install.sh --only core,build-kernel
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

submodule_run_install "$SCRIPT_DIR" "$@"
ui_press_enter
