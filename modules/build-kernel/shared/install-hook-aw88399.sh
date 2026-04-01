#!/bin/bash
# =============================================================================
# INSTALL-HOOK-AW88399.SH - hook-aw88399 submodule install hook
# =============================================================================
# Installs the AW88399 hook script and its internal libs to the module's
# share directory so build-kernel can invoke it at build time.
#
# Module: build-kernel (submodule: hook-aw88399)
# Requires: core, log
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: install-hook-aw88399 failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULE_DIR
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"

readonly HOOK_SHARE="/usr/local/share/build-kernel/hooks/aw88399"
readonly HOOK_SRC="${MODULE_DIR}/hooks/aw88399"

info "Installing AW88399 hook..."

install -d "${HOOK_SHARE}/lib"

install -m 755 "${HOOK_SRC}/aw88399.sh"          "${HOOK_SHARE}/aw88399.sh"
install -m 644 "${HOOK_SRC}/lib/resources.sh"    "${HOOK_SHARE}/lib/resources.sh"
install -m 644 "${HOOK_SRC}/lib/patch-manager.sh" "${HOOK_SHARE}/lib/patch-manager.sh"

success "AW88399 hook installed: ${HOOK_SHARE}/"
info "Hook path to use in build.conf:"
info "  /usr/local/share/build-kernel/hooks/aw88399/aw88399.sh"
