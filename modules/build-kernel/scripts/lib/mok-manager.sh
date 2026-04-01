#!/bin/bash
# =============================================================================
# MOK-MANAGER.SH - MOK key management for Secure Boot signing
# =============================================================================
# Handles MOK key creation, UEFI enrollment, and pesign database setup.
# Interactive prompts use ui_confirm() / ui_choose() from the shared lib.
#
# Module: build-kernel
# Requires: core, log, ui
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_MOK_MANAGER_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_MOK_MANAGER_LOADED=1

readonly _DEFAULT_MOK_DIR="/var/lib/shim-signed/mok"

# =============================================================================
# EFI / MOK CHECKS
# =============================================================================

check_efi_support() {
    [[ -d /sys/firmware/efi ]] && \
    { [[ -d /sys/firmware/efi/efivars ]] || [[ -d /sys/firmware/efi/vars ]]; }
}

check_mok_files_exist() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    [[ -f "${mok_dir}/MOK.priv" && -f "${mok_dir}/MOK.der" ]]
}

check_mok_enrolled() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local der_cert="${mok_dir}/MOK.der"

    if ! command -v mokutil &>/dev/null; then
        log_warn "mokutil not installed — cannot verify MOK enrollment"
        return 1
    fi

    if [[ -f "$der_cert" ]]; then
        local local_fp
        local_fp=$(openssl x509 -inform DER -in "$der_cert" -noout -fingerprint -sha1 2>/dev/null \
            | cut -d= -f2 | tr '[:upper:]' '[:lower:]')

        if [[ -n "$local_fp" ]]; then
            mokutil --list-enrolled 2>/dev/null | grep -qF "$local_fp"
            return
        fi
    fi

    # Fallback: any MOK enrolled?
    mokutil --list-enrolled 2>/dev/null | grep -q "Subject:"
}

check_pesign_cert() {
    local cert_name="$1"
    sudo certutil -d /etc/pki/pesign -L 2>/dev/null | grep -qF "$cert_name"
}

check_pesign_key() {
    local cert_name="$1"
    sudo certutil -d /etc/pki/pesign -K 2>/dev/null | grep -qF "$cert_name"
}

check_signing_prerequisites() {
    local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"
    command -v pesign &>/dev/null \
        && check_pesign_cert "$cert_name" \
        && check_pesign_key  "$cert_name"
}

# =============================================================================
# KEY CREATION
# =============================================================================

create_mok_key() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local key_cn="${MOK_KEY_CN:-Kernel Signing Key}"
    local validity="${MOK_VALIDITY_DAYS:-36500}"

    log_section "Creating New MOK Key Pair"

    sudo mkdir -p "$mok_dir" || { log_error "Failed to create MOK directory"; return 1; }

    log_step "Generating RSA 2048-bit key pair..."
    sudo openssl req -new -x509 -newkey rsa:2048 \
        -keyout "${mok_dir}/MOK.priv" \
        -outform DER -out "${mok_dir}/MOK.der" \
        -days "$validity" \
        -subj "/CN=${key_cn}/" \
        -nodes 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to generate MOK key pair"; return 1; }

    log_step "Converting to PEM..."
    sudo openssl x509 -inform DER \
        -in  "${mok_dir}/MOK.der" \
        -out "${mok_dir}/MOK.pem" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to convert to PEM"; return 1; }

    sudo chmod 600 "${mok_dir}/MOK.priv"
    sudo chmod 644 "${mok_dir}/MOK.der" "${mok_dir}/MOK.pem"

    log_success "MOK key pair created: ${mok_dir}/"
}

# =============================================================================
# UEFI ENROLLMENT
# =============================================================================

enroll_mok() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local der_cert="${mok_dir}/MOK.der"

    log_section "Enrolling MOK in UEFI"

    [[ -f "$der_cert" ]] || { log_error "MOK certificate not found: $der_cert"; return 1; }

    if ! check_efi_support; then
        log_error "EFI/UEFI not supported on this system — MOK enrollment impossible"
        return 1
    fi

    log_warn "You will be prompted to set a one-time password (needed at next boot)"
    sudo mokutil --import "$der_cert" \
        || { log_error "Failed to import MOK certificate"; return 1; }

    log_success "MOK certificate queued for enrollment"
    log_warn "Reboot required — the MOK Manager will appear on next boot"
}

# =============================================================================
# PESIGN DATABASE
# =============================================================================

import_to_pesign() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"
    local priv_key="${mok_dir}/MOK.priv"
    local pem_cert="${mok_dir}/MOK.pem"

    log_section "Importing MOK to Pesign Database"

    [[ -f "$priv_key" && -f "$pem_cert" ]] \
        || { log_error "MOK key files not found in $mok_dir"; return 1; }

    local p12_file
    p12_file=$(sudo mktemp --tmpdir MOK-XXXXXX.p12)
    trap 'sudo shred -u "$p12_file" 2>/dev/null || sudo rm -f "$p12_file"' RETURN
    sudo chmod 600 "$p12_file"

    sudo openssl pkcs12 -export \
        -out "$p12_file" -inkey "$priv_key" -in "$pem_cert" \
        -name "$cert_name" -passout pass: 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to create PKCS#12 bundle"; return 1; }

    # Remove existing entry if present
    if check_pesign_cert "$cert_name"; then
        sudo certutil -d /etc/pki/pesign -D -n "$cert_name" 2>/dev/null || true
    fi

    sudo pk12util -d /etc/pki/pesign -i "$p12_file" -W "" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to import into pesign database"; return 1; }

    if check_pesign_cert "$cert_name" && check_pesign_key "$cert_name"; then
        log_success "MOK imported to pesign database — certificate and key verified"
    else
        log_error "Pesign import verification failed"
        return 1
    fi
}

# =============================================================================
# STATE MANAGEMENT (resume after reboot)
# =============================================================================

save_state() {
    local state="$1"
    {
        echo "STATE=$state"
        echo "TIMESTAMP=$(date +%s)"
    } > "${STATE_FILE:-/tmp/kernel-build-state}"
}

load_state() {
    local sf="${STATE_FILE:-/tmp/kernel-build-state}"
    [[ -f "$sf" ]] || { echo ""; return; }

    local state_value=""
    while IFS='=' read -r key value; do
        key="${key// /}"
        [[ "$key" == "STATE" ]] && { state_value="$value"; break; }
    done < "$sf"
    echo "$state_value"
}

clear_state() {
    rm -f "${STATE_FILE:-/tmp/kernel-build-state}"
}

# =============================================================================
# INTERACTIVE SETUP WORKFLOW
# =============================================================================

setup_mok_workflow() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"

    log_section "MOK Signing Setup"

    # --- Step 1: Key files ---
    log_step "1. Checking MOK key files"

    if ! check_mok_files_exist; then
        log_warn "MOK key files not found in $mok_dir"

        local action
        action=$(ui_choose \
            "Create new MOK key pair" \
            "Specify path to existing MOK key" \
            "Skip signing (build without signature)")

        case "$action" in
            "Create new MOK key pair")
                create_mok_key || return 1
                ;;
            "Specify path to existing MOK key")
                local custom_path
                custom_path=$(ui_input "Path to MOK directory" "/var/lib/shim-signed/mok")
                if [[ -f "${custom_path}/MOK.priv" && -f "${custom_path}/MOK.der" ]]; then
                    MOK_KEY_DIR="$custom_path"
                    log_success "Using MOK from: $custom_path"
                else
                    log_error "MOK files not found in: $custom_path"
                    return 1
                fi
                ;;
            *)
                # shellcheck disable=SC2034
                ENABLE_SIGNING=false
                log "Signing disabled — continuing without signature"
                return 0
                ;;
        esac
    else
        log_success "MOK key files found"
    fi

    # --- Step 2: UEFI enrollment ---
    log_step "2. Checking MOK enrollment in UEFI"

    if ! check_mok_enrolled; then
        log_warn "MOK not enrolled in UEFI"

        if ! check_efi_support; then
            log_error "EFI/UEFI not supported — MOK enrollment impossible"
            if ui_confirm "Continue without signing?"; then
                # shellcheck disable=SC2034
                ENABLE_SIGNING=false
                return 0
            fi
            return 1
        fi

        local enroll_action
        enroll_action=$(ui_choose \
            "Enroll MOK now (requires reboot)" \
            "Continue without signing")

        case "$enroll_action" in
            "Enroll MOK now (requires reboot)")
                enroll_mok || return 1
                save_state "MOK_ENROLLED_PENDING_REBOOT"
                log_warn "Reboot required to complete MOK enrollment"
                if ui_confirm "Reboot now?"; then
                    sudo reboot
                fi
                exit 0
                ;;
            *)
                # shellcheck disable=SC2034
                ENABLE_SIGNING=false
                log "Signing disabled — continuing without signature"
                return 0
                ;;
        esac
    else
        log_success "MOK enrolled in UEFI"
    fi

    # --- Step 3: Pesign database ---
    log_step "3. Checking pesign database"

    if check_pesign_cert "$cert_name" && check_pesign_key "$cert_name"; then
        log_success "MOK already configured in pesign database"
    else
        log "Importing MOK into pesign database..."
        import_to_pesign || return 1
    fi

    clear_state
    log_success "MOK signing fully configured"
}

# =============================================================================
# STATUS DISPLAY
# =============================================================================

show_mok_status() {
    local mok_dir="${MOK_KEY_DIR:-$_DEFAULT_MOK_DIR}"
    local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"

    echo ""
    echo -e "${C_BOLD}=== MOK Status ===${C_NC}"
    echo ""

    local _ok="${C_GREEN}OK${C_NC}"
    local _miss="${C_RED}Missing${C_NC}"
    local _no="${C_RED}No${C_NC}"
    local _yes="${C_GREEN}Yes${C_NC}"

    echo -ne "  MOK key files (${mok_dir}): "
    check_mok_files_exist && echo -e "$_ok" || echo -e "$_miss"

    echo -ne "  MOK enrolled in UEFI:     "
    check_mok_enrolled && echo -e "$_yes" || echo -e "$_no"

    echo -ne "  Pesign certificate:        "
    check_pesign_cert "$cert_name" && echo -e "$_ok" || echo -e "$_miss"

    echo -ne "  Pesign private key:        "
    check_pesign_key "$cert_name" && echo -e "$_ok" || echo -e "$_miss"

    echo -ne "  Signing ready:             "
    check_signing_prerequisites && echo -e "$_yes" || echo -e "$_no"

    echo ""
}
