#!/bin/bash
# =============================================================================
# CLEANUP.SH - Build artifact archiving and cleanup
# =============================================================================
# Archives kernel RPMs and removes build directories after a successful build.
# Interactive confirmation via ui_confirm().
#
# Module: build-kernel
# Requires: core, log, ui
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_CLEANUP_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_CLEANUP_LOADED=1

# =============================================================================
# RPM ARCHIVING
# =============================================================================

archive_kernel_rpms() {
    local kernel_version="$1"
    local rpm_dir="${WORK_DIR}/kernel/x86_64"

    [[ -n "$kernel_version" ]] || { log_error "Kernel version required for archiving"; return 1; }
    [[ -d "$rpm_dir" ]]        || { log_warn "RPM directory not found: $rpm_dir"; return 1; }

    log_section "Archiving Kernel RPMs"

    local rpm_patterns=(
        "kernel-${kernel_version}.rpm"
        "kernel-core-${kernel_version}.rpm"
        "kernel-modules-${kernel_version}.rpm"
        "kernel-modules-core-${kernel_version}.rpm"
        "kernel-modules-extra-${kernel_version}.rpm"
        "kernel-devel-${kernel_version}.rpm"
    )

    local temp_dir="${WORK_DIR}/archive"
    mkdir -p "$temp_dir"

    local count=0
    for pattern in "${rpm_patterns[@]}"; do
        local rpm_file="${rpm_dir}/${pattern}"
        if [[ -f "$rpm_file" ]]; then
            cp "$rpm_file" "$temp_dir/"
            log "  + $(basename "$rpm_file")"
            ((count++))
        fi
    done

    ((count > 0)) || { log_error "No RPMs found to archive"; rm -rf "$temp_dir"; return 1; }

    mkdir -p "$ARCHIVE_DIR"
    local archive_name="kernel-${kernel_version}-rpms.tar.gz"

    tar -czf "${ARCHIVE_DIR}/${archive_name}" -C "${WORK_DIR}" archive/ \
        2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to create archive"; rm -rf "$temp_dir"; return 1; }

    rm -rf "$temp_dir"

    local size
    size=$(du -h "${ARCHIVE_DIR}/${archive_name}" | cut -f1)
    log_success "Archive created: ${ARCHIVE_DIR}/${archive_name} (${size}, ${count} RPMs)"
    log "To reinstall: cd ${ARCHIVE_DIR} && tar -xzf ${archive_name} && cd archive && sudo dnf install -y *.rpm"
}

# =============================================================================
# DIRECTORY CLEANUP
# =============================================================================

cleanup_build_directories() {
    log_section "Cleaning up Build Directories"

    local dirs_to_clean=("${WORK_DIR}" "${HOME}/rpmbuild")

    log_warn "This will permanently delete build directories:"
    for dir in "${dirs_to_clean[@]}"; do
        [[ -d "$dir" ]] && log "  - ${dir} ($(du -sh "$dir" 2>/dev/null | cut -f1))"
    done

    ui_confirm "Proceed with cleanup?" || { log "Cleanup cancelled"; return 0; }

    for dir in "${dirs_to_clean[@]}"; do
        if [[ -d "$dir" ]]; then
            if rm -rf "$dir" 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
                log_success "Removed: $dir"
            else
                log_error "Failed to remove: $dir"
            fi
        fi
    done

    log_success "Build directories removed"
}

# =============================================================================
# COMPLETE CLEANUP WORKFLOW
# =============================================================================

run_cleanup() {
    local kernel_version="$1"

    [[ -n "$kernel_version" ]] || { log_error "Kernel version required for cleanup"; return 1; }

    if [[ "${ARCHIVE_RPMS:-true}" == "true" ]]; then
        archive_kernel_rpms "$kernel_version" \
            || { log_warn "Archive failed — preserving build dirs for safety: ${WORK_DIR}"; return 1; }
    else
        log "RPM archiving disabled (ARCHIVE_RPMS=false)"
        ui_confirm "Delete build directories without archiving RPMs?" \
            || { log "Cleanup cancelled"; return 0; }
    fi

    cleanup_build_directories
}
