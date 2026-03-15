#!/bin/bash
# =============================================================================
# CLAMAV-MANAGE - ClamAV management tool (diagnostics & configuration)
# =============================================================================
# Interactive tool for managing the ClamAV installation:
#   - Diagnostics: check daemon, socket, config, signatures, resources
#   - Configuration: switch detection profile (standard/paranoid/minimal)
#
# Installed by the core submodule (setup-clamav.sh).
#
# Module: clamav (core utility)
# Requires: core, ui
# Version: 0.1.0
#
# Usage:
#   clamav-manage                  # Interactive menu
#   clamav-manage diagnose         # Run diagnostics
#   clamav-manage configure        # Change detection profile
# =============================================================================

set -euo pipefail

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"

readonly CLAMD_CONF="/etc/clamd.d/scan.conf"
readonly CLAMD_SOCKET="/run/clamd.scan/clamd.sock"
readonly CLAMD_SERVICE="clamd@scan"
readonly CLAMAV_CONF="/etc/system-scripts/clamav.conf"

# =============================================================================
# DIAGNOSE
# =============================================================================
cmd_diagnose() {
    echo -e "${C_BOLD}${C_CYAN}==> ClamAV Diagnostic${C_NC}"
    echo ""

    local issues=0

    # --- 1. Installation ---
    echo -e "${C_BLUE}[1/8] ClamAV Installation${C_NC}"

    if command -v clamscan &>/dev/null; then
        local version
        version=$(clamscan --version | head -1)
        echo -e "${C_GREEN}✓${C_NC} clamscan: $version"
    else
        echo -e "${C_RED}✗${C_NC} clamscan not found"
        ((issues++))
    fi

    if command -v clamdscan &>/dev/null; then
        echo -e "${C_GREEN}✓${C_NC} clamdscan found"
    else
        echo -e "${C_RED}✗${C_NC} clamdscan not found"
        ((issues++))
    fi

    if command -v clamd &>/dev/null; then
        echo -e "${C_GREEN}✓${C_NC} clamd daemon found"
    else
        echo -e "${C_RED}✗${C_NC} clamd daemon not found"
        ((issues++))
    fi
    echo ""

    # --- 2. Configuration file ---
    echo -e "${C_BLUE}[2/8] Configuration File${C_NC}"

    if [[ -f "$CLAMD_CONF" ]]; then
        echo -e "${C_GREEN}✓${C_NC} Config: $CLAMD_CONF"

        if grep -q "^Example" "$CLAMD_CONF" 2>/dev/null; then
            echo -e "${C_RED}✗${C_NC} Example line still present (config not activated)"
            ((issues++))
        else
            echo -e "${C_GREEN}✓${C_NC} Config active (Example line removed)"
        fi

        local local_socket
        local_socket=$(grep "^LocalSocket " "$CLAMD_CONF" 2>/dev/null | awk '{print $2}' || echo "")
        if [[ -n "$local_socket" ]]; then
            echo -e "${C_GREEN}✓${C_NC} LocalSocket: $local_socket"
        else
            echo -e "${C_RED}✗${C_NC} LocalSocket not configured"
            ((issues++))
        fi

        local max_threads
        max_threads=$(grep "^MaxThreads " "$CLAMD_CONF" 2>/dev/null | awk '{print $2}' || echo "")
        if [[ -n "$max_threads" ]]; then
            echo -e "${C_GREEN}✓${C_NC} MaxThreads: $max_threads"
        else
            echo -e "${C_YELLOW}⚠${C_NC} MaxThreads not set (default: 10)"
        fi

        local socket_group
        socket_group=$(grep "^LocalSocketGroup " "$CLAMD_CONF" 2>/dev/null | awk '{print $2}' || echo "")
        if [[ -n "$socket_group" ]]; then
            echo -e "${C_GREEN}✓${C_NC} LocalSocketGroup: $socket_group"
            if getent group "$socket_group" &>/dev/null; then
                echo -e "${C_GREEN}  ✓${C_NC} Group '$socket_group' exists"
            else
                echo -e "${C_RED}  ✗${C_NC} Group '$socket_group' does not exist!"
                ((issues++))
            fi
        else
            echo -e "${C_YELLOW}⚠${C_NC} LocalSocketGroup not configured"
        fi
    else
        echo -e "${C_RED}✗${C_NC} Config not found: $CLAMD_CONF"
        ((issues++))
    fi
    echo ""

    # --- 3. Service status ---
    echo -e "${C_BLUE}[3/8] Service Status${C_NC}"

    if systemctl is-active --quiet "$CLAMD_SERVICE"; then
        echo -e "${C_GREEN}✓${C_NC} $CLAMD_SERVICE is running"
        local mem
        mem=$(systemctl status "$CLAMD_SERVICE" 2>/dev/null | grep "Memory:" | awk '{print $2}' || echo "unknown")
        echo "  Memory: $mem"
        local pid
        pid=$(systemctl show -p MainPID "$CLAMD_SERVICE" --value 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && [[ "$pid" != "0" ]]; then
            echo "  PID: $pid"
        fi
    else
        echo -e "${C_YELLOW}⚠${C_NC} $CLAMD_SERVICE is not running"
        echo "  Start with: sudo systemctl start $CLAMD_SERVICE"
    fi

    if systemctl is-enabled --quiet "$CLAMD_SERVICE" 2>/dev/null; then
        echo -e "${C_YELLOW}⚠${C_NC} $CLAMD_SERVICE is enabled (starts at boot)"
        echo "  Disable to save RAM: sudo systemctl disable $CLAMD_SERVICE"
    else
        echo -e "${C_GREEN}✓${C_NC} $CLAMD_SERVICE is disabled (on-demand only)"
    fi
    echo ""

    # --- 4. Socket ---
    echo -e "${C_BLUE}[4/8] Socket File${C_NC}"

    if [[ -S "$CLAMD_SOCKET" ]]; then
        echo -e "${C_GREEN}✓${C_NC} Socket: $CLAMD_SOCKET"
        local perms owner
        perms=$(stat -c "%a" "$CLAMD_SOCKET" 2>/dev/null || echo "?")
        owner=$(stat -c "%U:%G" "$CLAMD_SOCKET" 2>/dev/null || echo "?")
        echo "  Permissions: $perms, Owner: $owner"
    else
        echo -e "${C_RED}✗${C_NC} Socket not found: $CLAMD_SOCKET"
        echo "  Normal if clamd is not running"
    fi

    local socket_dir
    socket_dir=$(dirname "$CLAMD_SOCKET")
    if [[ -d "$socket_dir" ]]; then
        echo -e "${C_GREEN}✓${C_NC} Socket dir: $socket_dir"
    else
        echo -e "${C_RED}✗${C_NC} Socket dir missing: $socket_dir"
        ((issues++))
    fi
    echo ""

    # --- 5. tmpfiles.d ---
    echo -e "${C_BLUE}[5/8] tmpfiles.d Configuration${C_NC}"

    if [[ -f /etc/tmpfiles.d/clamd.scan.conf ]]; then
        echo -e "${C_GREEN}✓${C_NC} tmpfiles.d entry exists"
        sed 's/^/  /' /etc/tmpfiles.d/clamd.scan.conf
    else
        echo -e "${C_YELLOW}⚠${C_NC} tmpfiles.d entry not found"
        echo "  Socket directory won't persist after reboot"
    fi
    echo ""

    # --- 6. Connection test ---
    echo -e "${C_BLUE}[6/8] Connection Test${C_NC}"

    if systemctl is-active --quiet "$CLAMD_SERVICE"; then
        if clamdscan --ping 5 2>/dev/null; then
            echo -e "${C_GREEN}✓${C_NC} clamdscan can connect to daemon"
        else
            echo -e "${C_RED}✗${C_NC} clamdscan cannot connect"
            echo "  Error: $(clamdscan --ping 5 2>&1 || true)"
            ((issues++))
        fi
    else
        echo -e "${C_YELLOW}⚠${C_NC} Daemon not running — skipping"
    fi
    echo ""

    # --- 7. Signatures ---
    echo -e "${C_BLUE}[7/8] Virus Signatures${C_NC}"

    if [[ -d /var/lib/clamav ]]; then
        shopt -s nullglob
        local db_files=(/var/lib/clamav/*.cvd /var/lib/clamav/*.cld)
        shopt -u nullglob

        if [[ ${#db_files[@]} -gt 0 ]]; then
            for db in "${db_files[@]}"; do
                local name size date
                name=$(basename "$db")
                size=$(du -h "$db" 2>/dev/null | cut -f1 || echo "?")
                date=$(stat -c "%y" "$db" 2>/dev/null | cut -d' ' -f1 || echo "?")
                echo "  $name — $size (updated: $date)"
            done
            local total_size
            total_size=$(du -sh /var/lib/clamav 2>/dev/null | cut -f1 || echo "?")
            echo "  Total: $total_size"
        else
            echo -e "${C_RED}  ✗${C_NC} No signature files (.cvd/.cld)"
            echo "  Run: sudo freshclam"
            ((issues++))
        fi
    else
        echo -e "${C_RED}✗${C_NC} Signature directory not found"
        ((issues++))
    fi
    echo ""

    # --- 8. System resources ---
    echo -e "${C_BLUE}[8/8] System Resources${C_NC}"

    echo "CPU cores: $(nproc)"
    echo "Total RAM: $(free -h | awk '/^Mem:/ {print $2}')"
    if systemctl is-active --quiet "$CLAMD_SERVICE"; then
        local mem_usage
        mem_usage=$(systemctl status "$CLAMD_SERVICE" 2>/dev/null | grep "Memory:" | awk '{print $2}' || echo "?")
        echo "clamd RAM: $mem_usage"
    fi
    echo ""

    # --- Summary ---
    echo -e "${C_BOLD}==> Summary${C_NC}"
    echo ""

    if [[ $issues -eq 0 ]]; then
        echo -e "${C_GREEN}✓${C_NC} All checks passed"
    else
        echo -e "${C_RED}Found $issues issue(s) — see above${C_NC}"
    fi
    echo ""
}

# =============================================================================
# CONFIGURE
# =============================================================================
cmd_configure() {
    echo -e "${C_BOLD}${C_CYAN}==> ClamAV Configuration${C_NC}"
    echo ""

    # Check prerequisites
    if [[ ! -f "$CLAMAV_CONF" ]]; then
        error "Config not found: $CLAMAV_CONF"
        echo "  Run 'make install-clamav' to set up ClamAV first."
        return 1
    fi

    # Read current profile
    local current_profile="unknown"
    if grep -q "^SCAN_PROFILE=" "$CLAMAV_CONF" 2>/dev/null; then
        current_profile=$(grep "^SCAN_PROFILE=" "$CLAMAV_CONF" | head -1 | cut -d'"' -f2)
    fi

    echo -e "Current profile: ${C_BOLD}$current_profile${C_NC}"
    echo ""
    echo -e "  ${C_BOLD}standard${C_NC} — Balanced detection, low false positives"
    echo -e "  ${C_BOLD}paranoid${C_NC} — Maximum detection, more false positives"
    echo -e "  ${C_BOLD}minimal${C_NC}  — Signatures only, near-zero false positives"
    echo ""

    local new_profile
    new_profile=$(ui_choose --header "Select scan profile" \
        "standard" "paranoid" "minimal")

    if [[ "$new_profile" == "$current_profile" ]]; then
        echo ""
        echo -e "${C_GREEN}✓${C_NC} Profile unchanged ($current_profile)"
        return 0
    fi

    # Update config file
    sed -i "s/^SCAN_PROFILE=\".*\"/SCAN_PROFILE=\"$new_profile\"/" "$CLAMAV_CONF"
    echo ""
    info "Profile updated: $current_profile → $new_profile"

    # Re-apply configuration
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local configure_script="$script_dir/../core/configure-clamav.sh"
    if [[ -x "$configure_script" ]]; then
        info "Applying configuration..."
        "$configure_script"
    else
        warn "configure-clamav.sh not found — run 'make reinstall-clamav' to apply"
    fi

    # Offer to restart clamd if running
    if systemctl is-active --quiet "$CLAMD_SERVICE"; then
        echo ""
        if ui_confirm "Restart clamd to apply changes?"; then
            systemctl restart "$CLAMD_SERVICE"
            success "clamd restarted"
        else
            info "Run 'sudo systemctl restart $CLAMD_SERVICE' later to apply"
        fi
    fi

    echo ""
    success "Configuration complete (profile: $new_profile)"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    check_root

    local command="${1:-}"

    if [[ -z "$command" ]]; then
        # Interactive menu
        echo -e "${C_BOLD}${C_CYAN}==> ClamAV Management${C_NC}"
        echo ""
        command=$(ui_choose --header "What would you like to do?" \
            "diagnose" "configure")
    fi

    case "$command" in
        diagnose)  cmd_diagnose ;;
        configure) cmd_configure ;;
        *)
            echo "Usage: sudo clamav-manage [diagnose|configure]"
            exit 1
            ;;
    esac
}

main "$@"
