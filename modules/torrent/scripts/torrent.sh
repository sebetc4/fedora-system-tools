#!/bin/bash
# =============================================================================
# TORRENT - Manage gluetun VPN + qBittorrent stack + downloads
# =============================================================================
# Main CLI for the torrent stack: VPN management, container lifecycle,
# download management, and security verification.
#
# Module: torrent
# Requires: core, log, config, ui
# Version: 0.1.0
#
# Usage:
#   torrent <command> [options]
#
# Debug: TORRENT_DEBUG=1 torrent <command>
# =============================================================================

set -euo pipefail

# ===================
# Load shared library
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/ui.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
ACTION="${1:-}"
readonly TIMEOUT=60
readonly WATCH_INTERVAL=30
readonly RETRY_ATTEMPTS=15
# shellcheck disable=SC2034  # DEBUG used by debug() from core.sh
readonly DEBUG="${TORRENT_DEBUG:-false}"

load_config
TORRENT_DIR="$DOWNLOAD_DIR/torrents"

# Load container config for FREE_ONLY setting
readonly CONTAINER_CONF="$HOME/.config/torrent/container.conf"
CONTAINER_FREE_ONLY="off"
# shellcheck disable=SC2034  # GLUETUN_API_KEY used in curl -H headers
GLUETUN_API_KEY=""
if [[ -f "$CONTAINER_CONF" ]]; then
    CONTAINER_FREE_ONLY=$(grep '^FREE_ONLY=' "$CONTAINER_CONF" | cut -d= -f2 || echo "off")
    GLUETUN_API_KEY=$(grep '^GLUETUN_API_KEY=' "$CONTAINER_CONF" | cut -d= -f2 || echo "")
fi

show_help() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}torrent${C_NC} - Manage gluetun VPN + qBittorrent stack + downloads"
    echo ""
    echo -e "${C_BOLD}USAGE:${C_NC}"
    echo -e "    ${C_CYAN}torrent${C_NC} ${C_YELLOW}<command>${C_NC} [options]"
    echo ""
    echo -e "${C_BOLD}VPN & CONTAINERS:${C_NC}"
    echo -e "    ${C_GREEN}start${C_NC}           Start VPN and qBittorrent containers"
    echo -e "    ${C_GREEN}stop${C_NC}            Stop all containers gracefully"
    echo -e "    ${C_GREEN}restart${C_NC}         Restart stack (reconnects to a different VPN server)"
    echo -e "    ${C_GREEN}status${C_NC}          Show current status of containers and VPN"
    echo -e "    ${C_GREEN}update${C_NC}          Pull latest images and recreate containers"
    echo -e "    ${C_GREEN}ip${C_NC}              Show current VPN IP (quick check)"
    echo -e "    ${C_GREEN}logs${C_NC} [name]     Follow logs (default: gluetun, or: qbittorrent)"
    echo -e "    ${C_GREEN}watch${C_NC}           Monitor VPN and notify if connection drops"
    echo ""
    echo -e "${C_BOLD}DOWNLOAD MANAGEMENT:${C_NC}"
    echo -e "    ${C_GREEN}list${C_NC} [opts]     List downloaded files with scan status"
    echo -e "    ${C_GREEN}move${C_NC} <#> [dest] Move file to export dir (fix permissions)"
    echo -e "    ${C_GREEN}export${C_NC}          Move all clean files to export dir"
    echo ""
    echo -e "${C_BOLD}HELP:${C_NC}"
    echo -e "    ${C_GREEN}help${C_NC}, --help    Show this help message"
    echo ""
    echo -e "${C_BOLD}EXAMPLES:${C_NC}"
    echo -e "    ${C_CYAN}torrent start${C_NC}              # Start VPN + qBittorrent"
    echo -e "    ${C_CYAN}torrent status${C_NC}             # Check if running and show VPN IP"
    echo -e "    ${C_CYAN}torrent list${C_NC}               # List downloaded files"
    echo -e "    ${C_CYAN}torrent move 1${C_NC}             # Move file #1 to export dir"
    echo -e "    ${C_CYAN}torrent move 2 /data/ISO${C_NC}   # Move file #2 to custom location"
    echo -e "    ${C_CYAN}torrent export${C_NC}             # Move all clean files"
    echo -e "    ${C_CYAN}torrent logs${C_NC}               # Follow gluetun logs"
    echo -e "    ${C_CYAN}torrent stop${C_NC}               # Stop everything"
    echo ""
    echo -e "${C_BOLD}DIRECTORIES (auto-detected):${C_NC}"
    echo -e "    ${C_YELLOW}Torrent downloads:${C_NC}   $TORRENT_DIR"
    echo -e "    ${C_YELLOW}Export destination:${C_NC}  $EXPORT_DIR"
    echo -e "    ${C_YELLOW}Container config:${C_NC}    $CONTAINER_CONF"
    echo -e "    ${C_YELLOW}Gluetun data:${C_NC}        ~/.config/podman/containers/gluetun"
    echo -e "    ${C_YELLOW}qBittorrent config:${C_NC}  ~/.config/podman/containers/qbittorrent"
    echo ""
    echo -e "${C_BOLD}SEE ALSO:${C_NC}"
    echo -e "    ${C_CYAN}torrent-container${C_NC}  Setup, configure, and manage containers"
    if command -v quarantine &>/dev/null; then
        echo -e "    ${C_CYAN}quarantine${C_NC}          Manage quarantined files (pending review & confirmed)"
    fi
    echo ""
    echo -e "${C_BOLD}ENVIRONMENT:${C_NC}"
    echo -e "    ${C_YELLOW}TORRENT_DEBUG=1${C_NC}  Enable debug output (e.g., TORRENT_DEBUG=1 torrent start)"
    echo ""
}

# ===================
# VPN Functions
# ===================

# Check VPN via Gluetun internal API (more reliable than ipinfo.io)
check_vpn_internal() {
    local response
    response=$(curl -s --max-time 5 \
        -H "X-API-Key: ${GLUETUN_API_KEY:-}" \
        "http://localhost:18001/v1/publicip/ip" 2>/dev/null) || return 1
    echo "$response" | grep -q '"public_ip":\s*"[0-9.]' 2>/dev/null
}

# Get VPN info via Gluetun internal API
get_vpn_info_internal() {
    local json
    json=$(curl -s --max-time 5 \
        -H "X-API-Key: ${GLUETUN_API_KEY:-}" \
        "http://localhost:18001/v1/publicip/ip" 2>/dev/null) || {
        echo "? ? ?"
        return 1
    }

    local ip country city
    ip=$(echo "$json" | grep -oP '"public_ip":\s*"\K[^"]+' 2>/dev/null)
    country=$(echo "$json" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null)
    city=$(echo "$json" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null)

    if [[ -z "$ip" || ! "$ip" =~ ^[0-9.]+$ ]]; then
        echo "? ? ?"
        return 1
    fi

    [[ -z "$country" ]] && country="?"
    [[ -z "$city" ]] && city="?"

    echo "$ip $country $city"
}

# Get VPN info with fallback strategy
get_vpn_info() {
    debug "Trying Gluetun internal API..."
    local result
    if result=$(get_vpn_info_internal 2>/dev/null) && [[ "$result" != "? ? ?" ]]; then
        debug "Got VPN info from internal API: $result"
        echo "$result"
        return 0
    fi

    debug "Falling back to ipinfo.io..."
    local json
    json=$(podman exec gluetun wget -qO- --timeout=8 https://ipinfo.io/json 2>/dev/null) || {
        echo "? ? ?"
        return 1
    }

    local ip country city
    ip=$(echo "$json" | grep -oP '"ip":\s*"\K[^"]+' 2>/dev/null || echo "?")
    country=$(echo "$json" | grep -oP '"country":\s*"\K[^"]+' 2>/dev/null || echo "?")
    city=$(echo "$json" | grep -oP '"city":\s*"\K[^"]+' 2>/dev/null || echo "?")

    debug "Got VPN info from ipinfo.io: $ip $country $city"
    echo "$ip $country $city"
}

get_vpn_info_formatted() {
    local info ip country city
    info=$(get_vpn_info)
    read -r ip country city <<< "$info"
    echo "$ip ($city, $country)"
}

check_vpn() {
    check_vpn_internal && return 0
    podman exec gluetun wget -qO- --timeout=5 https://ipinfo.io/ip &>/dev/null
}

# Check with retries and progressive backoff (for unstable free VPN servers)
check_vpn_with_retry() {
    local container="${1:-gluetun}"
    local attempts="${2:-$RETRY_ATTEMPTS}"

    debug "Checking VPN for $container with $attempts attempts..."

    for ((i=1; i<=attempts; i++)); do
        # Progressive timeout: 5s for first tries, 10s for later ones
        local timeout=5
        if [[ $i -gt 8 ]]; then timeout=10; fi

        local ip
        ip=$(podman exec "$container" wget -qO- --timeout=$timeout https://ipinfo.io/ip 2>/dev/null || echo "")
        if [[ -n "$ip" && "$ip" =~ ^[0-9.]+$ ]]; then
            debug "Got IP on attempt $i: $ip"
            echo "$ip"
            return 0
        fi

        debug "Attempt $i/$attempts failed, waiting..."
        echo -ne "\r  ${C_DIM}DNS check attempt $i/$attempts...${C_NC}  " >&2

        # Progressive backoff: 2s → 3s → 5s
        if [[ $i -lt $attempts ]]; then
            if [[ $i -le 5 ]]; then
                sleep 2
            elif [[ $i -le 10 ]]; then
                sleep 3
            else
                sleep 5
            fi
        fi
    done
    echo "" >&2
    debug "All $attempts attempts failed"
    return 1
}

notify() {
    local urgency="$1"
    local title="$2"
    local message="$3"

    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" "$title" "$message" 2>/dev/null || true
    fi

    case "$urgency" in
        critical) log "${C_RED}⚠️  $title: $message${C_NC}" ;;
        normal)   log "${C_GREEN}✅ $title: $message${C_NC}" ;;
        *)        log "$title: $message" ;;
    esac
}

wait_vpn_ready() {
    log "Waiting for VPN connection..."
    local count=0
    while [[ $count -lt $TIMEOUT ]]; do
        local vpn_check
        vpn_check=$(get_vpn_info 2>/dev/null)
        if [[ -n "$vpn_check" && "$vpn_check" != "? ? ?" ]]; then
            local test_ip
            test_ip=$(echo "$vpn_check" | awk '{print $1}')
            if [[ -n "$test_ip" && "$test_ip" != "?" && "$test_ip" =~ ^[0-9.]+$ ]]; then
                echo ""
                return 0
            fi
        fi
        echo -n "."
        sleep 3
        ((count+=3))
    done
    echo ""
    return 1
}

# ===================
# Container Functions
# ===================
check_container_exists() {
    podman ps -a --format "{{.Names}}" 2>/dev/null | grep -q "^${1}$" || return 1
}

check_container_running() {
    podman ps --format "{{.Names}}" 2>/dev/null | grep -q "^${1}$" || return 1
}

wait_container_healthy() {
    local name="$1"
    local max_wait="$2"
    local count=0

    while [[ $count -lt $max_wait ]]; do
        if check_container_running "$name"; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

# ===================
# Image Update Functions
# ===================

# Compare local vs remote image digests (requires skopeo)
update_images() {
    torrent-container update
}

# ===================
# Main Actions
# ===================
start_torrents() {
    echo ""

    # ===== STEP 1: Check containers exist =====
    for container in gluetun qbittorrent; do
        if ! check_container_exists "$container"; then
            ui_error_banner "ERROR" "Container '$container' not found" "Create it with: torrent-container install"
            exit 1
        fi
    done

    # ===== STEP 2: Start Gluetun =====
    if check_container_running "gluetun"; then
        log_success "Gluetun already running"
    else
        log "Starting Gluetun..."
        if ! podman start gluetun 2>/dev/null; then
            ui_error_banner "ERROR" "Failed to start gluetun" "Check: podman logs gluetun"
            exit 1
        fi

        if ! wait_container_healthy "gluetun" 10; then
            ui_error_banner "ERROR" "Gluetun failed to start" "Check: podman logs gluetun"
            exit 1
        fi
        log_success "Gluetun container started"
    fi

    # ===== STEP 3: Wait for VPN connection =====
    if ! wait_vpn_ready; then
        ui_error_banner "VPN TIMEOUT" \
            "VPN not connected after ${TIMEOUT}s" \
            "Possible causes:" \
            "  - VPN credentials invalid" \
            "  - VPN servers overloaded" \
            "  - Network issue" \
            "" \
            "Check logs: torrent logs" \
            "Check config: torrent-container info"
        exit 1
    fi

    # ===== STEP 4: Get VPN info =====
    local vpn_info ip country city
    vpn_info=$(get_vpn_info)
    if [[ "$vpn_info" == "? ? ?" ]]; then
        ui_error_banner "ERROR" "VPN connected but cannot get IP"
        exit 1
    fi
    read -r ip country city <<< "$vpn_info"
    log_success "VPN connected: $ip ($city, $country)"

    # ===== STEP 5: Start qBittorrent =====
    if check_container_running "qbittorrent"; then
        log_success "qBittorrent already running"
    else
        log "Starting qBittorrent..."
        if ! podman start qbittorrent 2>/dev/null; then
            ui_error_banner "ERROR" "Failed to start qbittorrent" "Check: podman logs qbittorrent"
            exit 1
        fi

        if ! wait_container_healthy "qbittorrent" 10; then
            ui_error_banner "ERROR" "qBittorrent failed to start" "Check: podman logs qbittorrent"
            exit 1
        fi
        log_success "qBittorrent started"
    fi

    # ===== STEP 6: Verify qBittorrent uses VPN (with retries) =====
    # Brief wait for DNS propagation through the VPN tunnel
    sleep 2
    if [[ "$CONTAINER_FREE_ONLY" == "on" ]]; then
        log "Verifying qBittorrent routing (free servers can be slow)..."
    else
        log "Verifying qBittorrent routing..."
    fi

    local qbt_ip
    qbt_ip=$(check_vpn_with_retry "qbittorrent") || {
        ui_error_banner "ERROR" \
            "qBittorrent cannot reach internet" \
            "" \
            "DNS not available through VPN tunnel." \
            "" \
            "Try: torrent restart  (connects to a different server)"
        exit 1
    }

    if [[ "$qbt_ip" != "$ip" ]]; then
        ui_error_banner "SECURITY ALERT" \
            "qBittorrent not using VPN!" \
            "qBittorrent IP: $qbt_ip" \
            "VPN IP: $ip" \
            "Stopping qBittorrent for safety..."
        podman stop qbittorrent 2>/dev/null || true
        exit 1
    fi

    log_success "qBittorrent routing through VPN verified"

    # ===== SUCCESS =====
    ui_banner "🌊 TORRENT STACK READY 🌊" \
        "🔒 VPN IP      : ${ip}" \
        "🌍 Location    : ${city}, ${country}" \
        "💻 Web UI      : http://localhost:18002"
}

stop_torrents() {
    echo ""
    for container in qbittorrent gluetun; do
        log "Stopping $container..."
        if podman stop -t 10 "$container" 2>/dev/null; then
            log_success "$container stopped"
        else
            log_warn "$container was not running"
        fi
    done
    echo ""
    log "All containers stopped"
}

show_status() {
    echo ""
    echo -e "${C_BOLD}=== Torrent Stack Status ===${C_NC}"
    echo ""

    # Gluetun status
    if check_container_running "gluetun"; then
        echo -e "  Gluetun:     ${C_GREEN}● Running${C_NC}"
        local vpn_info ip country city
        if vpn_info=$(get_vpn_info 2>/dev/null) && [[ "$vpn_info" != "? ? ?" ]]; then
            read -r ip country city <<< "$vpn_info"
            echo -e "               VPN: $ip ($city, $country)"
        else
            echo -e "               VPN: ${C_YELLOW}checking...${C_NC}"
        fi
    elif check_container_exists "gluetun"; then
        echo -e "  Gluetun:     ${C_YELLOW}○ Stopped${C_NC}"
    else
        echo -e "  Gluetun:     ${C_RED}✗ Not created${C_NC}"
    fi

    # qBittorrent status
    if check_container_running "qbittorrent"; then
        echo -e "  qBittorrent: ${C_GREEN}● Running${C_NC}"
        echo -e "               WebUI: http://localhost:18002"
    elif check_container_exists "qbittorrent"; then
        echo -e "  qBittorrent: ${C_YELLOW}○ Stopped${C_NC}"
    else
        echo -e "  qBittorrent: ${C_RED}✗ Not created${C_NC}"
    fi
    echo ""
}

show_ip() {
    if check_container_running "gluetun"; then
        get_vpn_info_formatted
    else
        error "Gluetun not running" "exit"
    fi
}

show_logs() {
    local container="${1:-gluetun}"
    if [[ "$container" != "gluetun" && "$container" != "qbittorrent" ]]; then
        error "Unknown container '$container'. Use: gluetun or qbittorrent" "exit"
    fi

    if ! check_container_exists "$container"; then
        error "Container '$container' does not exist" "exit"
    fi

    podman logs -f --tail 50 "$container"
}

watch_vpn() {
    log "Starting VPN monitor (checking every ${WATCH_INTERVAL}s)..."
    log "Press Ctrl+C to stop, or run with '&' for background"
    echo ""

    local vpn_was_up=false
    local consecutive_failures=0
    local max_failures=3

    if ! check_container_running "gluetun"; then
        error "Gluetun is not running. Start it first: torrent start" "exit"
    fi

    while true; do
        if check_vpn; then
            if [[ "$vpn_was_up" == false ]]; then
                notify "normal" "VPN Connected" "$(get_vpn_info_formatted)"
                vpn_was_up=true
            fi
            consecutive_failures=0
        else
            ((consecutive_failures++)) || true

            if [[ $consecutive_failures -ge $max_failures ]]; then
                if [[ "$vpn_was_up" == true ]]; then
                    notify "critical" "VPN Disconnected" "Connection lost! Attempting restart..."
                    vpn_was_up=false
                fi

                log_warn "Attempting to restart gluetun..."
                podman restart gluetun 2>/dev/null || true
                # Poll for VPN reconnection instead of fixed sleep
                log "Waiting for gluetun to reconnect..."
                local reconnect_wait=0
                while [[ $reconnect_wait -lt 90 ]]; do
                    local poll_status
                    poll_status=$(curl -s --max-time 3 \
                        -H "X-API-Key: ${GLUETUN_API_KEY:-}" \
                        "http://localhost:18001/v1/publicip/ip" 2>/dev/null) || true
                    if echo "$poll_status" | grep -q '"public_ip"' 2>/dev/null; then
                        break
                    fi
                    sleep 3
                    ((reconnect_wait += 3))
                done
                consecutive_failures=0
            else
                log_warn "VPN check failed ($consecutive_failures/$max_failures)..."
            fi
        fi

        sleep "$WATCH_INTERVAL"
    done
}

# ===================
# Download Management
# ===================

run_list() {
    local script="$SCRIPT_DIR/torrent-list.sh"
    if [[ -x "$script" ]]; then
        sudo "$script" "$@"
    elif [[ -x "/usr/local/bin/torrent-list" ]]; then
        sudo /usr/local/bin/torrent-list "$@"
    else
        error "torrent-list not found. Install with: sudo install -m 755 $SCRIPT_DIR/torrent-list.sh /usr/local/bin/torrent-list" "exit"
    fi
}

run_move() {
    local script="$SCRIPT_DIR/torrent-move.sh"
    if [[ -x "$script" ]]; then
        sudo "$script" "$@"
    elif [[ -x "/usr/local/bin/torrent-move" ]]; then
        sudo /usr/local/bin/torrent-move "$@"
    else
        error "torrent-move not found. Install with: sudo install -m 755 $SCRIPT_DIR/torrent-move.sh /usr/local/bin/torrent-move" "exit"
    fi
}

run_export() {
    run_move --clean "$@"
}

# ===== INTERACTIVE MODE =====
if [[ -z "$ACTION" ]]; then
    ACTION=$(ui_choose \
        --header "Torrent - choose an action" \
        "status" "start" "stop" "restart" "update" \
        "list" "move" "export" \
        "ip" "logs" "watch" "help")
fi

# ===== MAIN =====
case "$ACTION" in
    start)   start_torrents ;;
    stop)    stop_torrents ;;
    status)  show_status ;;
    ip)      show_ip ;;
    logs)    show_logs "${2:-gluetun}" ;;
    restart)
        stop_torrents
        sleep 2
        start_torrents
        ;;
    watch)   watch_vpn ;;
    update)  update_images ;;
    # Download management
    list)    shift || true; run_list "$@" ;;
    move)    shift || true; run_move "$@" ;;
    export)  shift || true; run_export "$@" ;;
    help|--help|-h) show_help ;;
    *)
        error "Unknown command: $ACTION"
        echo "Run 'torrent --help' for usage"
        exit 1
        ;;
esac
