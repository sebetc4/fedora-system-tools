#!/bin/bash
# =============================================================================
# SETUP-CLAMAV.SH - Shared ClamAV setup (packages, config, SELinux)
# =============================================================================
# Runs once when the first clamav submodule is installed.
# Installs ClamAV packages, configures the daemon, sets up SELinux,
# updates virus definitions.
#
# Module: clamav (shared)
# Requires: core.sh
# Version: 0.1.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: ClamAV shared setup failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
MODULE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly MODULE_DIR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"

# ===================
# ClamAV packages
# ===================
info "Installing ClamAV packages..."
"$MODULE_DIR/scripts/core/install-packages.sh"

# ===================
# Install ClamAV config with profile selection
# ===================
readonly CLAMAV_CONF="/etc/system-scripts/clamav.conf"
if [[ ! -f "$CLAMAV_CONF" ]]; then
    echo ""
    echo -e "${C_BOLD}${C_CYAN}Detection profile:${C_NC}"
    echo -e "  ${C_BOLD}standard${C_NC} — Balanced detection, low false positives (recommended)"
    echo -e "  ${C_BOLD}paranoid${C_NC} — Maximum detection, more false positives"
    echo -e "  ${C_BOLD}minimal${C_NC}  — Signatures only, near-zero false positives"
    echo ""

    SCAN_PROFILE=$(ui_choose --header "Select scan profile" \
        "standard (recommended)" "paranoid" "minimal")

    # Strip the "(recommended)" suffix
    SCAN_PROFILE="${SCAN_PROFILE%% *}"

    install -m 644 "$MODULE_DIR/templates/clamav.conf.default" "$CLAMAV_CONF"
    sed -i "s/^SCAN_PROFILE=\"standard\"/SCAN_PROFILE=\"$SCAN_PROFILE\"/" "$CLAMAV_CONF"
    info "ClamAV config installed: $CLAMAV_CONF (profile: $SCAN_PROFILE)"
else
    info "ClamAV config already exists: $CLAMAV_CONF (preserved)"
fi

# ===================
# Configure ClamAV
# ===================
info "Configuring ClamAV..."
"$MODULE_DIR/scripts/core/configure-clamav.sh"

# Install management tool (diagnose + configure)
install -m 755 "$MODULE_DIR/scripts/tools/clamav-manage.sh" /usr/local/bin/clamav-manage

# Install quarantine state library (used by scan scripts)
install -m 644 "$MODULE_DIR/scripts/core/quarantine-state.sh" "$LIB_DIR/quarantine-state.sh"
systemctl enable clamd@scan
if command -v setsebool &>/dev/null; then
    info "Configuring SELinux for ClamAV..."
    setsebool -P antivirus_can_scan_system on
fi

# ===================
# Update virus definitions
# ===================
info "Updating virus definitions..."
"$MODULE_DIR/scripts/core/update-definitions.sh"
freshclam || true
systemctl enable --now clamav-freshclam

# ===================
# Notifications
# ===================
# Note: Notification tags are now registered by individual submodules
# (daily-clamscan, weekly-clamscan) in their module.yml declarations.
# This ensures proper versioning and dependency tracking.

success "ClamAV shared setup complete"
