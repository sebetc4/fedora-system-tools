#!/bin/bash
# =============================================================================
# PATCH-MANAGER.SH - kernel.spec patch injection (internal hook lib)
# =============================================================================
# Copies the patch file into the kernel directory and modifies kernel.spec
# to declare and apply it, and to set the custom BUILD_ID.
#
# Module: build-kernel (hook: aw88399)
# Version: 0.1.0
# =============================================================================

[[ -n "${_AW88399_PATCH_MANAGER_LOADED:-}" ]] && return 0
readonly _AW88399_PATCH_MANAGER_LOADED=1

# =============================================================================
# PATCH VALIDATION
# =============================================================================

validate_patch() {
    local patch_file="$1"

    [[ -f "$patch_file" ]] || { log_error "Patch file not found: $patch_file"; return 1; }
    [[ -s "$patch_file" ]] || { log_error "Patch file is empty: $patch_file";  return 1; }

    local diff_count
    diff_count=$(grep -c "^diff " "$patch_file" 2>/dev/null || echo 0)
    (( diff_count > 0 )) || { log_error "Patch contains no valid diffs: $patch_file"; return 1; }

    debug "Patch valid: $diff_count file(s) modified"
}

# =============================================================================
# COPY PATCH
# =============================================================================

copy_patch_to_kernel() {
    local patch_src="$1"
    local kernel_dir="$2"

    validate_patch "$patch_src" || return 1
    [[ -d "$kernel_dir" ]] || { log_error "Kernel directory not found: $kernel_dir"; return 1; }

    local patch_name
    patch_name=$(basename "$patch_src")

    cp "$patch_src" "${kernel_dir}/${patch_name}" \
        || { log_error "Failed to copy patch to $kernel_dir"; return 1; }

    log_success "Patch copied: $patch_name"
}

# =============================================================================
# KERNEL.SPEC MODIFICATION
# =============================================================================

modify_kernel_spec() {
    local spec_file="$1"
    local patch_file="$2"
    local build_id="$3"

    [[ -f "$spec_file" ]] || { log_error "kernel.spec not found: $spec_file"; return 1; }
    [[ -n "$patch_file" ]] || { log_error "Patch file path is empty"; return 1; }

    local patch_name
    patch_name=$(basename "$patch_file")

    # Backup
    [[ -f "${spec_file}.orig" ]] || cp "$spec_file" "${spec_file}.orig"

    # 1. Declare patch (after Patch999999 line)
    local patch_line
    patch_line=$(grep -n "^Patch999999:" "$spec_file" | cut -d: -f1)
    [[ -n "$patch_line" ]] || {
        log_error "Patch999999 line not found in kernel.spec"
        return 1
    }
    sed -i "${patch_line}a Patch10000: ${patch_name}" "$spec_file"
    log "Declared: Patch10000: $patch_name"

    # 2. Apply patch (after ApplyOptionalPatch linux-kernel-test.patch)
    local apply_line
    apply_line=$(grep -n "ApplyOptionalPatch linux-kernel-test.patch" "$spec_file" | cut -d: -f1)
    [[ -n "$apply_line" ]] || {
        log_error "ApplyOptionalPatch linux-kernel-test.patch not found in kernel.spec"
        return 1
    }
    sed -i "${apply_line}a ApplyOptionalPatch ${patch_name}" "$spec_file"
    log "Added: ApplyOptionalPatch $patch_name"

    # 3. Set buildid
    if grep -q "^# define buildid .local$" "$spec_file"; then
        sed -i "s/^# define buildid .local$/%define buildid ${build_id}/" "$spec_file"
    elif grep -q "^#define buildid" "$spec_file"; then
        sed -i "s/^#define buildid.*$/%define buildid ${build_id}/" "$spec_file"
    else
        sed -i "1i %define buildid ${build_id}" "$spec_file"
    fi

    grep -q "^%define buildid ${build_id}" "$spec_file" \
        || { log_error "Failed to set buildid in kernel.spec"; return 1; }
    log "BuildID set: ${build_id}"

    # 4. Verification summary
    echo ""
    echo -e "${C_BOLD}=== Declared Patches ===${C_NC}"
    grep "^Patch" "$spec_file" | tail -3
    echo ""
    echo -e "${C_BOLD}=== BuildID ===${C_NC}"
    grep "define buildid" "$spec_file" | grep -v "^#"
    echo ""
    echo -e "${C_BOLD}=== Applied Patches ===${C_NC}"
    grep "ApplyOptionalPatch" "$spec_file" | grep -v "ApplyOptionalPatch()" | tail -3
    echo ""

    log_success "kernel.spec modified successfully"
}
