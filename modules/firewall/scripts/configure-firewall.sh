#!/bin/bash
# =============================================================================
# CONFIGURE-FIREWALL - Config-driven firewall hardening engine
# =============================================================================
# Reads /etc/system-scripts/firewall.conf and applies the desired firewall
# state via firewalld. All operations are idempotent (query before change).
#
# Before first apply, snapshots the current firewall state into
# /etc/system-scripts/firewall.state for later restoration.
#
# Module: firewall
# Requires: core
# Version: 0.1.0
#
# Usage:
#   ./configure-firewall.sh              Apply config
#   ./configure-firewall.sh --dry-run    Show changes without applying
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: configure-firewall failed at line $LINENO" >&2; exit 1' ERR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly FIREWALL_CONF="${FIREWALL_CONF:-/etc/system-scripts/firewall.conf}"
readonly FIREWALL_STATE="${FIREWALL_STATE:-/etc/system-scripts/firewall.state}"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# =============================================================================
# HELPERS
# =============================================================================

# Print action (or just display in dry-run mode)
run_cmd() {
    if $DRY_RUN; then
        info "[dry-run] $*"
    else
        "$@"
    fi
}

remove_service() {
    local service="$1"
    if firewall-cmd --permanent --query-service="$service" &>/dev/null; then
        echo -e "  ${C_YELLOW}→${C_NC} Removing service: ${C_BOLD}$service${C_NC}"
        run_cmd firewall-cmd --permanent --remove-service="$service"
    else
        echo -e "  ${C_DIM}$service already absent${C_NC}"
    fi
}

add_service() {
    local service="$1"
    if ! firewall-cmd --permanent --query-service="$service" &>/dev/null; then
        echo -e "  ${C_GREEN}→${C_NC} Adding service: ${C_BOLD}$service${C_NC}"
        run_cmd firewall-cmd --permanent --add-service="$service"
    else
        echo -e "  ${C_DIM}$service already present${C_NC}"
    fi
}

remove_port() {
    local port="$1"
    if firewall-cmd --permanent --query-port="$port" &>/dev/null; then
        echo -e "  ${C_YELLOW}→${C_NC} Closing port: ${C_BOLD}$port${C_NC}"
        run_cmd firewall-cmd --permanent --remove-port="$port"
    else
        echo -e "  ${C_DIM}$port already closed${C_NC}"
    fi
}

add_port() {
    local port="$1"
    if ! firewall-cmd --permanent --query-port="$port" &>/dev/null; then
        echo -e "  ${C_GREEN}→${C_NC} Opening port: ${C_BOLD}$port${C_NC}"
        run_cmd firewall-cmd --permanent --add-port="$port"
    else
        echo -e "  ${C_DIM}$port already open${C_NC}"
    fi
}

# Snapshot current firewall state for later restoration
snapshot_state() {
    if [[ -f "$FIREWALL_STATE" ]]; then
        debug "State file already exists, skipping snapshot"
        return 0
    fi

    local zone services ports log_denied
    zone="$(firewall-cmd --get-default-zone)"
    services="$(firewall-cmd --permanent --list-services 2>/dev/null || echo "")"
    ports="$(firewall-cmd --permanent --list-ports 2>/dev/null || echo "")"
    log_denied="$(firewall-cmd --get-log-denied 2>/dev/null || echo "off")"

    # Convert space-separated to bash array syntax
    local svc_array="" port_array=""
    for s in $services; do
        svc_array+="$s "
    done
    for p in $ports; do
        port_array+="$p "
    done

    cat > "$FIREWALL_STATE" << STATEEOF
# /etc/system-scripts/firewall.state — auto-generated, do not edit
# Snapshot of firewall state before hardening was applied.
# Used by uninstall.sh to restore the original configuration.
STATE_ZONE="$zone"
STATE_SERVICES=($svc_array)
STATE_PORTS=($port_array)
STATE_LOG_DENIED="$log_denied"
STATE_DATE="$(date '+%Y-%m-%d %H:%M:%S')"
STATEEOF
    chmod 600 "$FIREWALL_STATE"
    info "State snapshot saved to $FIREWALL_STATE"
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

if ! systemctl is-active --quiet firewalld; then
    error "firewalld is not running" "exit"
fi

if [[ -n "${SSH_CONNECTION:-}" ]]; then
    error "SSH session detected. Aborting to prevent lockout." "exit"
fi

if [[ ! -f "$FIREWALL_CONF" ]]; then
    error "Config file not found: $FIREWALL_CONF" "exit"
fi

# =============================================================================
# LOAD CONFIG
# =============================================================================

# Declare arrays with defaults before sourcing (allows empty arrays in config)
FIREWALL_ZONE=""
REMOVE_SERVICES=()
ALLOW_SERVICES=()
ALLOW_PORTS=()
CLOSE_PORTS=()
LOG_DENIED="off"

# shellcheck source=/dev/null
source "$FIREWALL_CONF"

# =============================================================================
# SNAPSHOT STATE (before first apply)
# =============================================================================

if ! $DRY_RUN; then
    snapshot_state
fi

# =============================================================================
# APPLY CONFIGURATION
# =============================================================================

echo ""
echo -e "${C_BOLD}${C_CYAN}=== Firewall hardening ===${C_NC}"
echo ""

# --- Zone ---
if [[ -n "$FIREWALL_ZONE" ]]; then
    current_zone="$(firewall-cmd --get-default-zone)"
    if [[ "$current_zone" != "$FIREWALL_ZONE" ]]; then
        echo -e "${C_BOLD}Zone${C_NC}"
        echo -e "  ${C_YELLOW}→${C_NC} Switching zone: $current_zone → ${C_BOLD}$FIREWALL_ZONE${C_NC}"
        run_cmd firewall-cmd --set-default-zone="$FIREWALL_ZONE"
    else
        echo -e "${C_BOLD}Zone${C_NC}"
        echo -e "  ${C_DIM}Already on $FIREWALL_ZONE${C_NC}"
    fi
    echo ""
fi

# --- Remove services ---
if [[ ${#REMOVE_SERVICES[@]} -gt 0 ]]; then
    echo -e "${C_BOLD}Remove services${C_NC}"
    for svc in "${REMOVE_SERVICES[@]}"; do
        remove_service "$svc"
    done
    echo ""
fi

# --- Allow services ---
if [[ ${#ALLOW_SERVICES[@]} -gt 0 ]]; then
    echo -e "${C_BOLD}Allow services${C_NC}"
    for svc in "${ALLOW_SERVICES[@]}"; do
        add_service "$svc"
    done
    echo ""
fi

# --- Close ports ---
if [[ ${#CLOSE_PORTS[@]} -gt 0 ]]; then
    echo -e "${C_BOLD}Close ports${C_NC}"
    for port in "${CLOSE_PORTS[@]}"; do
        remove_port "$port"
    done
    echo ""
fi

# --- Open ports ---
if [[ ${#ALLOW_PORTS[@]} -gt 0 ]]; then
    echo -e "${C_BOLD}Open ports${C_NC}"
    for port in "${ALLOW_PORTS[@]}"; do
        add_port "$port"
    done
    echo ""
fi

# --- Log denied ---
current_log="$(firewall-cmd --get-log-denied 2>/dev/null || echo "off")"
if [[ "$LOG_DENIED" != "$current_log" ]]; then
    echo -e "${C_BOLD}Logging${C_NC}"
    echo -e "  ${C_YELLOW}→${C_NC} Log denied: $current_log → ${C_BOLD}$LOG_DENIED${C_NC}"
    run_cmd firewall-cmd --set-log-denied="$LOG_DENIED"
    echo ""
fi

# --- Reload ---
if ! $DRY_RUN; then
    echo -e "${C_BOLD}Reload${C_NC}"
    echo -e "  ${C_GREEN}→${C_NC} Reloading firewall"
    firewall-cmd --reload
    echo ""
fi

echo -e "${C_BOLD}${C_CYAN}=== Firewall hardening completed ===${C_NC}"
echo ""
