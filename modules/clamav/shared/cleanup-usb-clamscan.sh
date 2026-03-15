#!/bin/bash
# =============================================================================
# CLEANUP-USB-CLAMSCAN - USB ClamAV scanner cleanup (udev, services)
# =============================================================================
# Runs when the usb-clamscan submodule is uninstalled. Stops all active
# template instances and removes udev rules.
#
# Note: SELinux boolean (antivirus_can_scan_system) is NOT reset here —
# it is managed by the ClamAV core submodule (cleanup-clamav.sh).
#
# Module: clamav (usb-clamscan uninstall hook)
# Requires: core
# Version: 0.1.0
# =============================================================================

set -euo pipefail

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# ===================
# Stop active usb-clamscan@ instances
# ===================
active_services=()
mapfile -t active_services < <(systemctl list-units --type=service --state=active 'usb-clamscan@*' --no-legend 2>/dev/null | awk '{print $1}')
if [[ ${#active_services[@]} -gt 0 ]]; then
    info "Stopping active USB security services..."
    for service in "${active_services[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
    done
fi

# ===================
# Remove udev rules
# ===================
info "Removing udev rules..."
rm -f /etc/udev/rules.d/99-usb-clamscan.rules
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

success "USB ClamAV scanner cleanup complete"
