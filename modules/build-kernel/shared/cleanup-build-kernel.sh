#!/bin/bash
# =============================================================================
# CLEANUP-BUILD-KERNEL.SH - Core submodule uninstall hook
# =============================================================================
# Removes module-specific libs installed by setup-build-kernel.sh.
# Does NOT remove user config files (~/.config/build-kernel/).
#
# Module: build-kernel (submodule: build-kernel)
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: cleanup-build-kernel failed at line $LINENO" >&2; exit 1' ERR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/notify.sh"

info "Removing build-kernel module libs..."
rm -rf /usr/local/lib/build-kernel
success "Module libs removed: /usr/local/lib/build-kernel/"

info "Removing hook share directory..."
rm -rf /usr/local/share/build-kernel
success "Hook share directory removed"

info "Unregistering notification tag..."
notify_unregister "build-kernel"
success "Notification tag unregistered"

info "Note: user config files (~/.config/build-kernel/) were NOT removed."
