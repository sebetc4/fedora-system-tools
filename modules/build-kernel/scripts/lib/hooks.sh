#!/bin/bash
# =============================================================================
# HOOKS.SH - Pre-build hook engine for build-kernel
# =============================================================================
# Iterates HOOKS_PRE_BUILD[] from build.conf, exports context to each hook,
# and runs them sequentially. A failing hook aborts the build immediately.
#
# Hook array format (defined in build.conf):
#   HOOKS_PRE_BUILD=(
#       "name:/path/to/script.sh:enabled"
#       "name:/path/to/script.sh:disabled"
#   )
#
# Context exported to hooks:
#   KERNEL_DIR          Kernel source directory (fedpkg checkout)
#   KERNEL_VERSION_MMP  Kernel version major.minor.patch (e.g. 6.19.7)
#   FEDORA_RELEASE      Fedora branch (e.g. f43)
#   BUILD_ID            Build identifier (e.g. .audio)
#   DRY_RUN             true/false
#   LOG_FILE            Shared log file path
#
# Module: build-kernel
# Requires: core, log
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_HOOKS_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_HOOKS_LOADED=1

# =============================================================================
# HOOK ENGINE
# =============================================================================

# Run all hooks for a given phase.
# Args: $1 = phase name (e.g. "PRE_BUILD")
# Reads: HOOKS_<PHASE> array from calling scope
# On hook failure: logs error and exits (no continue)
run_build_hooks() {
    local phase="$1"
    local array_var="HOOKS_${phase}"

    # Use nameref to read the array from the caller's scope
    local -n _hooks_ref="${array_var}" 2>/dev/null || {
        log_warn "Hook array ${array_var} not defined — skipping phase ${phase}"
        return 0
    }

    if [[ ${#_hooks_ref[@]} -eq 0 ]]; then
        debug "No hooks defined for phase ${phase}"
        return 0
    fi

    log_section "HOOKS: ${phase}"

    for hook_entry in "${_hooks_ref[@]}"; do
        # Parse "name:script:status"
        local hook_name hook_script hook_status
        IFS=: read -r hook_name hook_script hook_status <<< "$hook_entry"

        if [[ "$hook_status" != "enabled" ]]; then
            log "Hook '${hook_name}': disabled (skipping)"
            continue
        fi

        if [[ ! -f "$hook_script" ]]; then
            log_error "Hook '${hook_name}': script not found: ${hook_script}"
            log_error "Build aborted."
            exit 1
        fi

        if [[ ! -x "$hook_script" ]]; then
            log_error "Hook '${hook_name}': script not executable: ${hook_script}"
            log_error "Build aborted."
            exit 1
        fi

        log_step "Running hook: ${hook_name}"

        # Export build context for the hook
        export KERNEL_DIR KERNEL_VERSION_MMP FEDORA_RELEASE BUILD_ID DRY_RUN LOG_FILE

        local hook_rc=0
        "$hook_script" || hook_rc=$?

        if [[ "$hook_rc" -ne 0 ]]; then
            log_error "Hook '${hook_name}' failed (exit ${hook_rc})"
            log_error "Build aborted. No kernel was built."
            exit 1
        fi

        log_success "Hook '${hook_name}' completed"
    done
}
