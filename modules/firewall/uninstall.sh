#!/bin/bash
# =============================================================================
# FIREWALL UNINSTALL - Firewall module removal
# =============================================================================
# Restores the pre-hardening firewall state from the state file, removes the
# CLI binary, and unregisters from the module registry.
#
# Module: firewall
# Requires: core, registry
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/firewall/uninstall.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Uninstall failed at line $LINENO" >&2; exit 1' ERR

readonly MODULE_NAME="firewall"
readonly FIREWALL_STATE="/etc/system-scripts/firewall.state"
readonly FIREWALL_CONF="/etc/system-scripts/firewall.conf"

# ===================
# Check lib is installed
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed." >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/ui.sh"

check_root

# ===================
# Check module is installed
# ===================
if ! registry_is_installed "$MODULE_NAME"; then
    warn "$MODULE_NAME is not registered in the registry"
fi

info "Uninstalling $MODULE_NAME..."

# ===================
# Restore firewall state
# ===================
if command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
    if [[ -f "$FIREWALL_STATE" ]]; then
        info "Restoring firewall state from snapshot..."

        STATE_ZONE=""
        STATE_SERVICES=()
        STATE_PORTS=()
        STATE_LOG_DENIED="off"
        # shellcheck source=/dev/null
        source "$FIREWALL_STATE"

        # Restore zone
        current_zone="$(firewall-cmd --get-default-zone 2>/dev/null || echo "")"
        if [[ -n "$STATE_ZONE" && "$current_zone" != "$STATE_ZONE" ]]; then
            firewall-cmd --set-default-zone="$STATE_ZONE" 2>/dev/null || true
        fi

        # Clear current services, restore saved ones
        current_services="$(firewall-cmd --permanent --list-services 2>/dev/null || echo "")"
        for svc in $current_services; do
            firewall-cmd --permanent --remove-service="$svc" 2>/dev/null || true
        done
        for svc in "${STATE_SERVICES[@]}"; do
            firewall-cmd --permanent --add-service="$svc" 2>/dev/null || true
        done

        # Clear current ports, restore saved ones
        current_ports="$(firewall-cmd --permanent --list-ports 2>/dev/null || echo "")"
        for port in $current_ports; do
            firewall-cmd --permanent --remove-port="$port" 2>/dev/null || true
        done
        for port in "${STATE_PORTS[@]}"; do
            firewall-cmd --permanent --add-port="$port" 2>/dev/null || true
        done

        # Restore log-denied
        firewall-cmd --set-log-denied="$STATE_LOG_DENIED" 2>/dev/null || true

        firewall-cmd --reload 2>/dev/null || true
        success "Firewall state restored from snapshot"

    elif [[ -f "$FIREWALL_CONF" ]]; then
        # Fallback: undo config rules without a state snapshot
        warn "No state file found — reverting config rules as best effort"

        REMOVE_SERVICES=()
        ALLOW_PORTS=()
        CLOSE_PORTS=()
        # shellcheck source=/dev/null
        source "$FIREWALL_CONF"

        # Re-add services that were removed by hardening
        for svc in "${REMOVE_SERVICES[@]}"; do
            firewall-cmd --permanent --add-service="$svc" 2>/dev/null || true
        done

        # Re-open ports that were closed by hardening
        for port in "${CLOSE_PORTS[@]}"; do
            firewall-cmd --permanent --add-port="$port" 2>/dev/null || true
        done

        # Remove ports that were opened by hardening
        for port in "${ALLOW_PORTS[@]}"; do
            firewall-cmd --permanent --remove-port="$port" 2>/dev/null || true
        done

        # Reset log-denied
        firewall-cmd --set-log-denied="off" 2>/dev/null || true

        firewall-cmd --reload 2>/dev/null || true
        success "Firewall rules reverted from config (best effort)"
    else
        warn "No state file or config found — firewall rules unchanged"
    fi

    # Show restored state for verification
    echo ""
    info "Current firewall state:"
    echo "  Zone:     $(firewall-cmd --get-default-zone 2>/dev/null)"
    echo "  Services: $(firewall-cmd --permanent --list-services 2>/dev/null)"
    echo "  Ports:    $(firewall-cmd --permanent --list-ports 2>/dev/null || echo '(none)')"
else
    warn "firewalld not available — skipping firewall restore"
fi

# ===================
# Remove CLI binary
# ===================
rm -f /usr/local/bin/firewall-harden

# ===================
# Remove config files
# ===================
rm -f "$FIREWALL_CONF"
rm -f "$FIREWALL_STATE"

# ===================
# Unregister & done
# ===================
registry_remove "$MODULE_NAME"

ui_banner "$MODULE_NAME uninstalled" \
    "" \
    "Firewall rules have been restored to their pre-hardening state."

ui_press_enter
