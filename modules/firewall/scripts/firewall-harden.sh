#!/bin/bash
# =============================================================================
# FIREWALL-HARDEN - Interactive firewall hardening CLI
# =============================================================================
# Manage firewall configuration dynamically. Provides an interactive wizard
# to build the config, and commands to apply, inspect, or restore state.
#
# Config:  /etc/system-scripts/firewall.conf   (source of truth)
# State:   /etc/system-scripts/firewall.state   (pre-hardening snapshot)
#
# Module: firewall
# Requires: core, ui
# Version: 0.1.0
#
# Usage:
#   firewall-harden                     Interactive wizard
#   firewall-harden status              Show current firewall state
#   firewall-harden show-config         Show saved configuration
#   firewall-harden apply               Apply config to firewall
#   firewall-harden apply --dry-run     Preview changes without applying
#   firewall-harden restore             Restore pre-hardening state
#   firewall-harden -h, --help          Show help
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: firewall-harden failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# LIBRARY
# =============================================================================

readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: system-scripts library not found in $LIB_DIR" >&2
    exit 1
fi
source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly FIREWALL_CONF="${FIREWALL_CONF:-/etc/system-scripts/firewall.conf}"
readonly FIREWALL_STATE="${FIREWALL_STATE:-/etc/system-scripts/firewall.state}"
readonly CONFIGURE_SCRIPT="$SCRIPT_DIR/configure-firewall.sh"

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << 'HELPEOF'
Usage: firewall-harden [COMMAND] [OPTIONS]

Commands:
  (none)          Interactive wizard — build config and apply
  status          Show current firewall state (zone, services, ports)
  show-config     Display saved configuration file
  apply           Apply configuration to firewall
  restore         Restore pre-hardening firewall state

Options:
  --dry-run       Preview changes without applying (with apply)
  -h, --help      Show this help

Examples:
  sudo firewall-harden                  # Interactive wizard
  sudo firewall-harden status           # Check current state
  sudo firewall-harden apply --dry-run  # Preview changes
  sudo firewall-harden apply            # Apply saved config
  sudo firewall-harden restore          # Undo all hardening
HELPEOF
}

# =============================================================================
# STATUS — Show current firewall state
# =============================================================================

cmd_status() {
    echo ""
    ui_header "FIREWALL STATUS"

    local zone services ports log_denied
    zone="$(firewall-cmd --get-default-zone)"
    services="$(firewall-cmd --list-services 2>/dev/null || echo "(none)")"
    ports="$(firewall-cmd --list-ports 2>/dev/null || echo "(none)")"
    log_denied="$(firewall-cmd --get-log-denied 2>/dev/null || echo "off")"

    echo -e "  ${C_BOLD}Default zone:${C_NC}  $zone"
    echo -e "  ${C_BOLD}Services:${C_NC}      $services"
    echo -e "  ${C_BOLD}Open ports:${C_NC}    ${ports:-(none)}"
    echo -e "  ${C_BOLD}Log denied:${C_NC}    $log_denied"
    echo ""

    # Config file status
    if [[ -f "$FIREWALL_CONF" ]]; then
        local mod_date
        mod_date="$(stat -c '%y' "$FIREWALL_CONF" 2>/dev/null | cut -d. -f1)"
        echo -e "  ${C_BOLD}Config:${C_NC}        ${C_GREEN}$FIREWALL_CONF${C_NC}"
        echo -e "  ${C_BOLD}Last modified:${C_NC} $mod_date"
    else
        echo -e "  ${C_BOLD}Config:${C_NC}        ${C_DIM}not found${C_NC}"
    fi

    # State file status
    if [[ -f "$FIREWALL_STATE" ]]; then
        echo -e "  ${C_BOLD}State backup:${C_NC}  ${C_GREEN}$FIREWALL_STATE${C_NC}"
    else
        echo -e "  ${C_BOLD}State backup:${C_NC}  ${C_DIM}none (created on first apply)${C_NC}"
    fi
    echo ""
}

# =============================================================================
# SHOW-CONFIG — Display saved configuration
# =============================================================================

cmd_show_config() {
    if [[ ! -f "$FIREWALL_CONF" ]]; then
        error "Config file not found: $FIREWALL_CONF"
        info "Run 'sudo firewall-harden' to create one interactively."
        return 1
    fi

    echo ""
    ui_header "FIREWALL CONFIGURATION"
    echo -e "${C_DIM}$FIREWALL_CONF${C_NC}"
    echo ""

    # Source and display parsed values
    local FIREWALL_ZONE="" REMOVE_SERVICES=() ALLOW_SERVICES=()
    local ALLOW_PORTS=() CLOSE_PORTS=() LOG_DENIED="off"
    # shellcheck source=/dev/null
    source "$FIREWALL_CONF"

    echo -e "  ${C_BOLD}Zone:${C_NC}             ${FIREWALL_ZONE:-(keep current)}"
    echo -e "  ${C_BOLD}Remove services:${C_NC}  ${REMOVE_SERVICES[*]:-(none)}"
    echo -e "  ${C_BOLD}Allow services:${C_NC}   ${ALLOW_SERVICES[*]:-(none)}"
    echo -e "  ${C_BOLD}Open ports:${C_NC}       ${ALLOW_PORTS[*]:-(none)}"
    echo -e "  ${C_BOLD}Close ports:${C_NC}      ${CLOSE_PORTS[*]:-(none)}"
    echo -e "  ${C_BOLD}Log denied:${C_NC}       $LOG_DENIED"
    echo ""
}

# =============================================================================
# APPLY — Apply config to firewall
# =============================================================================

cmd_apply() {
    local dry_run_flag=""
    if [[ "${1:-}" == "--dry-run" ]]; then
        dry_run_flag="--dry-run"
    fi

    if [[ ! -f "$FIREWALL_CONF" ]]; then
        error "Config file not found: $FIREWALL_CONF"
        info "Run 'sudo firewall-harden' to create one interactively."
        return 1
    fi

    bash "$CONFIGURE_SCRIPT" $dry_run_flag
}

# =============================================================================
# RESTORE — Restore pre-hardening state
# =============================================================================

cmd_restore() {
    if [[ ! -f "$FIREWALL_STATE" ]]; then
        error "No state file found: $FIREWALL_STATE"
        info "Nothing to restore — hardening was never applied."
        return 1
    fi

    # shellcheck source=/dev/null
    local STATE_ZONE="" STATE_SERVICES=() STATE_PORTS=() STATE_LOG_DENIED="off"
    # shellcheck source=/dev/null
    source "$FIREWALL_STATE"

    echo ""
    ui_header "RESTORE FIREWALL STATE"

    echo -e "  Restoring to snapshot from: ${C_BOLD}${STATE_DATE:-unknown}${C_NC}"
    echo -e "  Zone: ${C_BOLD}$STATE_ZONE${C_NC}"
    echo -e "  Services: ${C_BOLD}${STATE_SERVICES[*]}${C_NC}"
    echo -e "  Ports: ${C_BOLD}${STATE_PORTS[*]:-(none)}${C_NC}"
    echo ""

    if ! ui_confirm "Restore this firewall state?"; then
        warn "Restore cancelled."
        return 0
    fi

    echo ""

    # Restore zone
    local current_zone
    current_zone="$(firewall-cmd --get-default-zone)"
    if [[ "$current_zone" != "$STATE_ZONE" ]]; then
        info "Restoring zone: $STATE_ZONE"
        firewall-cmd --set-default-zone="$STATE_ZONE"
    fi

    # Remove all current services, then re-add the saved ones
    local current_services
    current_services="$(firewall-cmd --permanent --list-services 2>/dev/null || echo "")"
    for svc in $current_services; do
        firewall-cmd --permanent --remove-service="$svc" 2>/dev/null || true
    done
    for svc in "${STATE_SERVICES[@]}"; do
        firewall-cmd --permanent --add-service="$svc" 2>/dev/null || true
    done

    # Remove all current ports, then re-add the saved ones
    local current_ports
    current_ports="$(firewall-cmd --permanent --list-ports 2>/dev/null || echo "")"
    for port in $current_ports; do
        firewall-cmd --permanent --remove-port="$port" 2>/dev/null || true
    done
    for port in "${STATE_PORTS[@]}"; do
        firewall-cmd --permanent --add-port="$port" 2>/dev/null || true
    done

    # Restore log-denied
    firewall-cmd --set-log-denied="$STATE_LOG_DENIED" 2>/dev/null || true

    # Reload
    firewall-cmd --reload

    # Remove state file
    rm -f "$FIREWALL_STATE"

    echo ""
    success "Firewall state restored"
    echo ""
}

# =============================================================================
# INTERACTIVE WIZARD
# =============================================================================

cmd_interactive() {
    echo ""
    ui_header "FIREWALL HARDENING WIZARD"

    # --- Show current state ---
    local current_zone current_services current_ports current_log
    current_zone="$(firewall-cmd --get-default-zone)"
    current_services="$(firewall-cmd --list-services 2>/dev/null || echo "")"
    current_ports="$(firewall-cmd --list-ports 2>/dev/null || echo "")"
    current_log="$(firewall-cmd --get-log-denied 2>/dev/null || echo "off")"

    echo -e "  ${C_BOLD}Current state:${C_NC}"
    echo -e "  Zone:      ${C_BOLD}$current_zone${C_NC}"
    echo -e "  Services:  ${current_services:-(none)}"
    echo -e "  Ports:     ${current_ports:-(none)}"
    echo -e "  Log:       $current_log"
    echo ""

    # --- Collect desired config ---
    local new_zone="" remove_svcs=() allow_svcs=() allow_ports=() close_ports=()
    local new_log="off"

    # 1. Zone selection
    echo -e "${C_BOLD}${C_CYAN}1. Default zone${C_NC}"
    echo ""
    local zone_choice
    zone_choice=$(ui_choose --header "Select default zone" \
        "$current_zone (keep current)" "public" "FedoraWorkstation" "home" "drop")
    if [[ "$zone_choice" != "$current_zone (keep current)" ]]; then
        new_zone="$zone_choice"
        echo -e "  → Zone: ${C_BOLD}$new_zone${C_NC}"
    else
        echo -e "  → Keep current zone: ${C_BOLD}$current_zone${C_NC}"
    fi
    echo ""

    # 2. Services to remove
    echo -e "${C_BOLD}${C_CYAN}2. Services to remove${C_NC}"
    echo ""
    if [[ -n "$current_services" ]]; then
        local svc_list=()
        for svc in $current_services; do
            svc_list+=("$svc")
        done

        if [[ ${#svc_list[@]} -gt 0 ]]; then
            echo -e "  Active services: ${C_BOLD}${svc_list[*]}${C_NC}"
            echo ""
            for svc in "${svc_list[@]}"; do
                if ui_confirm "  Remove '$svc' service?"; then
                    remove_svcs+=("$svc")
                else
                    allow_svcs+=("$svc")
                fi
            done
        fi
    else
        echo -e "  ${C_DIM}No active services to remove${C_NC}"
    fi
    echo ""

    # 3. Close FedoraWorkstation port range
    local effective_zone="${new_zone:-$current_zone}"
    if [[ "$effective_zone" == "FedoraWorkstation" ]]; then
        echo -e "${C_BOLD}${C_CYAN}3. FedoraWorkstation port range${C_NC}"
        echo ""
        echo -e "  The FedoraWorkstation zone opens ports ${C_BOLD}1025-65535${C_NC} by default."
        echo -e "  This defeats most firewall hardening."
        echo ""
        if ui_confirm "  Close the permissive port range (1025-65535)?"; then
            close_ports+=(1025-65535/tcp 1025-65535/udp)
            echo -e "  → Will close 1025-65535/tcp + udp"
        fi
        echo ""
    fi

    # 4. Custom ports to open
    echo -e "${C_BOLD}${C_CYAN}4. Ports to open${C_NC}"
    echo ""
    echo -e "  ${C_DIM}Common ports: KDE Connect=1714-1764/tcp, Syncthing=22000/tcp${C_NC}"
    echo ""
    while true; do
        if ! ui_confirm "  Add a port to open?"; then
            break
        fi
        local port_input
        port_input=$(ui_input "  Port (e.g. 8080/tcp, 1714-1764/tcp)" "")
        if [[ -n "$port_input" ]]; then
            allow_ports+=("$port_input")
            echo -e "  → Added: ${C_BOLD}$port_input${C_NC}"
        fi
    done
    echo ""

    # 5. Log denied
    echo -e "${C_BOLD}${C_CYAN}5. Denied packet logging${C_NC}"
    echo ""
    if ui_confirm "  Enable logging of denied packets?"; then
        new_log=$(ui_choose --header "Log level" "all" "unicast" "broadcast" "multicast")
        echo -e "  → Log denied: ${C_BOLD}$new_log${C_NC}"
    fi
    echo ""

    # --- Summary ---
    echo -e "${C_BOLD}${C_CYAN}=== Summary ===${C_NC}"
    echo ""
    echo -e "  ${C_BOLD}Zone:${C_NC}             ${new_zone:-(keep current)}"
    echo -e "  ${C_BOLD}Remove services:${C_NC}  ${remove_svcs[*]:-(none)}"
    echo -e "  ${C_BOLD}Allow services:${C_NC}   ${allow_svcs[*]:-(none)}"
    echo -e "  ${C_BOLD}Open ports:${C_NC}       ${allow_ports[*]:-(none)}"
    echo -e "  ${C_BOLD}Close ports:${C_NC}      ${close_ports[*]:-(none)}"
    echo -e "  ${C_BOLD}Log denied:${C_NC}       $new_log"
    echo ""

    if ! ui_confirm "Save configuration and apply?"; then
        warn "Cancelled. No changes applied."
        return 0
    fi

    # --- Write config ---
    write_config "$new_zone" remove_svcs allow_svcs allow_ports close_ports "$new_log"
    success "Configuration saved to $FIREWALL_CONF"
    echo ""

    # --- Apply ---
    bash "$CONFIGURE_SCRIPT"
}

# =============================================================================
# WRITE CONFIG FILE
# =============================================================================

write_config() {
    local zone="$1"
    local -n _remove_svcs="$2"
    local -n _allow_svcs="$3"
    local -n _allow_ports="$4"
    local -n _close_ports="$5"
    local log_denied="$6"

    mkdir -p "$(dirname "$FIREWALL_CONF")"

    cat > "$FIREWALL_CONF" << CONFEOF
# =============================================================================
# FIREWALL.CONF - Firewall hardening configuration
# =============================================================================
# Source of truth for firewall-harden. Edit with: sudo firewall-harden
# Applied with: sudo firewall-harden apply
#
# Format: shell-sourceable (bash arrays + variables)
# Location: $FIREWALL_CONF
# =============================================================================

# Zone — set to change the default zone (leave empty to keep current)
FIREWALL_ZONE="$zone"

# Services to REMOVE from the active zone
REMOVE_SERVICES=(${_remove_svcs[*]})

# Services to explicitly ALLOW in the active zone
ALLOW_SERVICES=(${_allow_svcs[*]})

# Ports to OPEN (format: port/proto or port-range/proto)
ALLOW_PORTS=(${_allow_ports[*]})

# Ports to CLOSE
CLOSE_PORTS=(${_close_ports[*]})

# Log denied packets: all | unicast | broadcast | multicast | off
LOG_DENIED="$log_denied"
CONFEOF
    chmod 644 "$FIREWALL_CONF"
}

# =============================================================================
# PRE-FLIGHT
# =============================================================================

check_root

if ! systemctl is-active --quiet firewalld; then
    error "firewalld is not running" "exit"
fi

if [[ -n "${SSH_CONNECTION:-}" ]]; then
    error "SSH session detected. Aborting to prevent lockout." "exit"
fi

# =============================================================================
# MAIN
# =============================================================================

main() {
    case "${1:-}" in
        -h|--help)    show_help ;;
        status)       cmd_status ;;
        show-config)  cmd_show_config ;;
        apply)        shift; cmd_apply "$@" ;;
        restore)      cmd_restore ;;
        "")           cmd_interactive ;;
        *)            error "Unknown command: $1"; show_help; exit 1 ;;
    esac
}

main "$@"
