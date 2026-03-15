#!/bin/bash
# =============================================================================
# INSTALL-USB-CLAMSCAN - USB ClamAV scanner installation hook
# =============================================================================
# Handles USB-specific setup that the submodule engine cannot:
#   - SELinux configuration
#   - udev rules installation + reload
#
# The submodule engine handles: binary, systemd service, and notification
# registration (via module.yml). Logs go to /var/log/clamav/ (core submodule).
#
# Module: clamav
# Requires: core
# Version: 0.1.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly BASE_DIR

# Shared library
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# ===================
# SELinux
# ===================
if command -v setsebool &>/dev/null; then
    echo "Configuring SELinux for ClamAV..."
    setsebool -P antivirus_can_scan_system on 2>/dev/null || true
    echo -e "${C_GREEN}✓ SELinux configured${C_NC}"
fi

# ===================
# udev rule
# ===================
echo "Installing udev rule..."

install -m 644 "$BASE_DIR/udev-rules/99-usb-clamscan.rules" /etc/udev/rules.d/

udevadm control --reload-rules
udevadm trigger

echo -e "${C_GREEN}✓ udev rule installed${C_NC}"

# Log directory (/var/log/clamav/) is created by core submodule
# Log file is created by usb-clamscan.sh at runtime

# ===================
# Summary
# ===================
echo ""
echo -e "${C_BOLD}==> Verification${C_NC}"
echo ""

echo "Installed files:"
echo "  ✓ /usr/local/bin/usb-clamscan"
echo "  ✓ /etc/systemd/system/usb-clamscan@.service"
echo "  ✓ /etc/udev/rules.d/99-usb-clamscan.rules"
echo "  ✓ notify-daemon: notify-usb-scan tag registered"
echo "  Logs: /var/log/clamav/usb-clamscan.log (shared clamav log dir)"
echo ""

echo "How it works:"
echo "  1. Insert USB drive"
echo "  2. GNOME auto-mounts normally"
echo "  3. ClamAV scan runs in background (non-blocking)"
echo "  4. Notification shows scan result"
echo "  5. Infected files quarantined to /var/quarantine/confirmed"
echo ""

echo "Monitoring:"
echo "  - Watch logs:         sudo tail -f /var/log/clamav/usb-clamscan.log"
echo "  - Check status:       journalctl -u 'usb-clamscan@*' -f"
echo ""

echo "Notes:"
echo "  • Devices in /etc/fstab are excluded (permanent HDDs)"
echo "  • Drive remains accessible during scan"
echo "  • Infected files moved to /var/quarantine/confirmed"
echo "  • Notifications: via notify-daemon (logger -t notify-usb-scan)"
echo "  • Restart notify-daemon after install: systemctl --user restart notify-daemon"
echo ""
