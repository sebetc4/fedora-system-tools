#!/bin/bash
# =============================================================================
# SETUP.SH - Pre-flight environment setup for kernel builds
# =============================================================================
# Checks Fedora, disk space, installs build deps, configures pesign, and
# verifies MOK signing setup. Does NOT fetch hook-specific resources.
#
# Module: build-kernel
# Requires: core, log, ui
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_SETUP_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_SETUP_LOADED=1

# =============================================================================
# SYSTEM CHECKS
# =============================================================================

check_fedora() {
    [[ -f /etc/fedora-release ]] \
        || { log_error "This script must run on Fedora"; return 1; }
    local v
    v=$(rpm -E %fedora)
    log "Fedora ${v} detected"
}

check_disk_space() {
    local work_dir="${WORK_DIR:-$HOME/fedora-kernel-build}"
    local parent_dir
    parent_dir=$(dirname "$work_dir")
    local required_gb=50

    local available_gb
    available_gb=$(df -BG "$parent_dir" 2>/dev/null | awk 'NR==2 {print int($4)}')

    if [[ -z "$available_gb" ]]; then
        log_warn "Could not determine available disk space"
        return 0
    fi

    if ((available_gb < required_gb)); then
        log_warn "Low disk space: ${available_gb}GB available, ${required_gb}GB recommended"
        ui_confirm "Continue anyway?" || return 1
    else
        log_success "Disk space OK: ${available_gb}GB available"
    fi
}

# =============================================================================
# BUILD DEPENDENCIES
# =============================================================================

_upgrade_rpm_build_packages() {
    log_step "Upgrading RPM build packages (avoids 'fg: no job control' bug)..."
    if sudo dnf upgrade -y python-rpm-macros python3-rpm-macros rpm-build \
        2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "RPM build packages up-to-date"
    else
        log_warn "Could not upgrade some RPM packages (may already be latest)"
    fi
}

install_build_dependencies() {
    log_section "Installing Build Dependencies"

    _upgrade_rpm_build_packages

    local required_packages=(
        fedpkg fedora-packager rpm-build koji
        git wget curl
        pesign sbsigntools mokutil openssl nss-tools
        grubby dracut ccache
    )

    local missing=()
    for pkg in "${required_packages[@]}"; do
        rpm -q "$pkg" &>/dev/null || missing+=("$pkg")
    done

    if ((${#missing[@]} > 0)); then
        log "Installing: ${missing[*]}"
        sudo dnf install -y "${missing[@]}" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
            || { log_error "Failed to install some build packages"; return 1; }
    fi

    log_success "All build dependencies installed"
}

# =============================================================================
# PESIGN USER CONFIGURATION
# =============================================================================

setup_pesign_user() {
    if ! grep -q "^${USER}$" /etc/pesign/users 2>/dev/null; then
        sudo bash -c "echo ${USER} >> /etc/pesign/users"
    fi
    if sudo /usr/libexec/pesign/pesign-authorize 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "Pesign configured for user ${USER}"
    else
        log_warn "Pesign authorization had warnings (often safe to ignore)"
    fi
}

# =============================================================================
# RESUME STATE CHECK
# =============================================================================

check_resume_state() {
    local saved_state
    saved_state=$(load_state)
    [[ -z "$saved_state" ]] && return 0

    log_section "Resuming from Previous State"
    log "Saved state: $saved_state"

    case "$saved_state" in
        "MOK_ENROLLED_PENDING_REBOOT")
            if check_mok_enrolled; then
                log_success "MOK enrollment completed"
                clear_state
                local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"
                if ! check_pesign_cert "$cert_name"; then
                    import_to_pesign || return 1
                fi
                log_success "Signing ready — continuing build"
            else
                log_error "MOK enrollment does not appear to have completed"
                log "Did you complete the MOK Manager prompts at boot?"
                clear_state
                return 1
            fi
            ;;
        *)
            log_warn "Unknown saved state: $saved_state — clearing"
            clear_state
            ;;
    esac
}

# =============================================================================
# MAIN SETUP WORKFLOW
# =============================================================================

run_setup() {
    log_section "Pre-flight Setup Checks"

    check_resume_state  || return 1
    check_fedora        || return 1
    check_disk_space    || return 1

    install_build_dependencies || { log_error "Failed to install build dependencies"; return 1; }
    setup_pesign_user || true

    verify_signing_setup || { log_error "Signing setup failed"; return 1; }

    log_success "All pre-flight checks passed"
}

# =============================================================================
# QUICK CHECK (--check mode)
# =============================================================================

quick_setup_check() {
    log_section "Quick Setup Check"

    echo ""
    echo -e "${C_BOLD}=== System ===${C_NC}"
    echo -ne "  Fedora: "
    check_fedora &>/dev/null \
        && echo -e "${C_GREEN}OK${C_NC} ($(rpm -E %fedora))" \
        || echo -e "${C_RED}Not Fedora${C_NC}"

    echo ""
    echo -e "${C_BOLD}=== Dependencies ===${C_NC}"
    for dep in fedpkg pesign mokutil git rpmbuild; do
        echo -ne "  ${dep}: "
        command -v "$dep" &>/dev/null \
            && echo -e "${C_GREEN}Installed${C_NC}" \
            || echo -e "${C_RED}Missing${C_NC}"
    done

    echo ""
    show_mok_status
}
