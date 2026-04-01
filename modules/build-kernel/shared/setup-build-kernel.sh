#!/bin/bash
# =============================================================================
# SETUP-BUILD-KERNEL.SH - Core submodule install hook
# =============================================================================
# Installs build dependencies, module-specific libs, and creates the default
# config for the build-kernel module.
#
# Module: build-kernel (submodule: build-kernel)
# Requires: core, log
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: setup-build-kernel failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
MODULE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly MODULE_DIR
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/notify.sh"

# Detect real user when run via sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# =============================================================================
# INSTALL MODULE LIBS
# =============================================================================
info "Installing build-kernel module libs..."

install -d /usr/local/lib/build-kernel
for lib_file in "${MODULE_DIR}/scripts/lib/"*.sh; do
    install -m 644 "$lib_file" /usr/local/lib/build-kernel/
    debug "  + $(basename "$lib_file")"
done

success "Module libs installed: /usr/local/lib/build-kernel/"

# =============================================================================
# CREATE DEFAULT CONFIG
# =============================================================================
info "Creating default config for user: $REAL_USER"

sudo -u "$REAL_USER" mkdir -p "${REAL_HOME}/.config/build-kernel/hooks"

if [[ ! -f "${REAL_HOME}/.config/build-kernel/build.conf" ]]; then
    install -m 644 -o "$REAL_USER" \
        "${MODULE_DIR}/config/build.conf" \
        "${REAL_HOME}/.config/build-kernel/build.conf"
    success "Config created: ${REAL_HOME}/.config/build-kernel/build.conf"
else
    info "Config already exists — skipping: ${REAL_HOME}/.config/build-kernel/build.conf"
fi

if [[ ! -f "${REAL_HOME}/.config/build-kernel/hooks/aw88399.conf" ]]; then
    install -m 644 -o "$REAL_USER" \
        "${MODULE_DIR}/config/hooks/aw88399.conf" \
        "${REAL_HOME}/.config/build-kernel/hooks/aw88399.conf"
    success "Hook config created: ${REAL_HOME}/.config/build-kernel/hooks/aw88399.conf"
else
    info "Hook config already exists — skipping"
fi

# =============================================================================
# REGISTER NOTIFICATION TAG
# =============================================================================
info "Registering notification tag..."
notify_register "build-kernel" "applications-development" "important"
success "Notification tag registered: build-kernel"
