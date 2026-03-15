#!/bin/bash
# =============================================================================
# <MODULE> INSTALL - <Module name> orchestrator
# =============================================================================
# Installs <module> submodules: <list submodules here>.
#
# Supports interactive multi-select and CLI flags:
#   --all         Install all submodules (non-interactive)
#   --only <name> Install specific submodule(s) (comma-separated)
#
# Delegates orchestration to submodule_run_install() in lib/submodule.sh.
# Example: modules/clamav/install.sh, modules/backup/install.sh
#
# Module: <module-name>
# Requires: core, registry, submodule, ui
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/<module>/install.sh              # Interactive
#   sudo ./modules/<module>/install.sh --all         # All submodules
#   sudo ./modules/<module>/install.sh --only sub1,sub2
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

# Optional: inter-module dependency check
# if ! registry_is_installed "other-module"; then
#     error "Module 'other-module' is required." "exit"
# fi

# Optional: custom post-install summary
# _module_post_install() {
#     local module_name="$1"
#     echo "Custom summary for $module_name"
# }

submodule_run_install "$SCRIPT_DIR" "$@"
