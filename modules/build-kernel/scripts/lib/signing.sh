#!/bin/bash
# =============================================================================
# SIGNING.SH - Kernel signing with pesign (Secure Boot)
# =============================================================================
# Signs the installed kernel using the MOK key via pesign.
# Requires mok-manager.sh to be loaded (check_signing_prerequisites etc.).
#
# Module: build-kernel
# Requires: core, log
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_SIGNING_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_SIGNING_LOADED=1

# =============================================================================
# KERNEL SIGNING
# =============================================================================

sign_kernel_pesign() {
    local kernel_path="$1"
    local cert_name="${2:-${MOK_CERT_NAME:-MOK Signing Key}}"

    log_section "Kernel Signing"

    check_signing_prerequisites \
        || { log_error "Signing prerequisites not met — run: build-kernel --setup-mok"; return 1; }

    [[ -f "$kernel_path" ]] \
        || { log_error "Kernel not found: $kernel_path"; return 1; }

    # Backup
    if [[ ! -f "${kernel_path}.unsigned" ]]; then
        sudo cp "$kernel_path" "${kernel_path}.unsigned"
        log "Backup: ${kernel_path}.unsigned"
    fi

    # Sign
    log_step "Signing with pesign (cert: ${cert_name})..."
    local signed_path="${kernel_path}.signed"

    sudo pesign -n /etc/pki/pesign -c "$cert_name" \
        -i "$kernel_path" -o "$signed_path" -s 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Kernel signing failed"; return 1; }

    sudo mv "$signed_path" "$kernel_path" \
        || { log_error "Failed to replace kernel with signed version"; return 1; }

    log_success "Kernel signed: $kernel_path"

    # Regenerate GRUB config
    log_step "Regenerating GRUB configuration..."
    if sudo grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
        log_success "GRUB configuration updated"
    else
        log_warn "GRUB mkconfig had warnings (usually safe to ignore)"
    fi

    # Verify
    _verify_kernel_signature "$kernel_path"
}

# =============================================================================
# SIGNATURE VERIFICATION
# =============================================================================

_verify_kernel_signature() {
    local kernel_path="$1"

    if ! command -v sbverify &>/dev/null; then
        log_warn "sbverify not installed — skipping signature verification"
        return 0
    fi

    if sudo sbverify --list "$kernel_path" &>/dev/null; then
        log_success "Kernel signature verified"
        echo ""
        sudo sbverify --list "$kernel_path" 2>&1 | grep -E "(signature|Subject|CN=)" | head -10
        echo ""
    else
        log_warn "Could not verify signature (sbverify failed — non-blocking)"
    fi
}

# =============================================================================
# PRE-BUILD VERIFICATION
# =============================================================================

# Verify signing prerequisites before starting the long build.
# Attempts auto-import if pesign DB is not configured.
verify_signing_setup() {
    local cert_name="${MOK_CERT_NAME:-MOK Signing Key}"

    log_section "Pre-build Signing Verification"

    if [[ "${ENABLE_SIGNING:-true}" != "true" ]]; then
        log "Signing disabled — kernel will NOT be signed for Secure Boot"
        return 0
    fi

    log_step "Checking MOK key files..."
    check_mok_files_exist \
        || { log_error "MOK key files missing — run: build-kernel --setup-mok"; return 1; }
    log_success "MOK key files: OK"

    log_step "Checking MOK enrollment..."
    check_mok_enrolled \
        || { log_error "MOK not enrolled in UEFI — run: build-kernel --setup-mok"; return 1; }
    log_success "MOK enrollment: OK"

    log_step "Checking pesign database..."
    if check_pesign_cert "$cert_name" && check_pesign_key "$cert_name"; then
        log_success "Pesign database: OK"
    else
        log "Pesign not configured — attempting auto-import..."
        import_to_pesign || { log_error "Failed to configure pesign database"; return 1; }
        log_success "Pesign database: OK (just configured)"
    fi

    log_success "Signing setup verified — ready to build and sign"
}
