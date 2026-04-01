#!/bin/bash
# =============================================================================
# AW88399 - Pre-build hook: Awinic AW88399 audio patch
# =============================================================================
# Fully autonomous pre-build hook for the AW88399 audio chip fix.
# Manages its own resources, applies the patch, and configures kernel options.
#
# Steps performed:
#   1. Clone / update upstream audio fix repository
#   2. Select patch for the current kernel version
#   3. Copy patch to kernel directory and modify kernel.spec
#   4. Configure audio kernel options (all .config files)
#   5. Validate with fedpkg prep
#   6. Install firmware (aw88399_acf.bin) and UCM2 config files
#
# Module: build-kernel (hook)
# Requires: core, log, ui
# Version: 0.1.0
#
# Usage (standalone):
#   aw88399.sh [--dry-run] [-c <config>] [-h]
#
# Usage (as hook):
#   Called automatically by build-kernel via HOOKS_PRE_BUILD[].
#   Receives KERNEL_DIR, KERNEL_VERSION_MMP, FEDORA_RELEASE, BUILD_ID,
#   DRY_RUN, LOG_FILE via environment.
#   Config: ~/.config/build-kernel/hooks/aw88399.conf
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: aw88399 hook failed at line $LINENO" >&2; exit 1' ERR

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly HOOK_DIR

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed. Run: sudo make install-lib" >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/validate.sh"
source "${HOOK_DIR}/lib/resources.sh"
source "${HOOK_DIR}/lib/patch-manager.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
readonly DEFAULT_CONFIG="${REAL_HOME}/.config/build-kernel/hooks/aw88399.conf"

# Inherit from build-kernel (set when called as hook, or defaults for standalone)
KERNEL_DIR="${KERNEL_DIR:-}"
KERNEL_VERSION_MMP="${KERNEL_VERSION_MMP:-}"
FEDORA_RELEASE="${FEDORA_RELEASE:-}"
BUILD_ID="${BUILD_ID:-.audio}"
DRY_RUN="${DRY_RUN:-false}"
LOG_FILE="${LOG_FILE:-}"

# Hook-specific config variables (populated by load_config)
AW88399_FIX_REPO=""
RESOURCE_CACHE_DIR=""

# =============================================================================
# HELP
# =============================================================================
_show_help() {
    cat << EOF
${C_CYAN}AW88399 Pre-build Hook v${VERSION}${C_NC}

Applies the Awinic AW88399 audio patch to a Fedora kernel build.

${C_BOLD}Usage:${C_NC}
    $0 [--dry-run] [-c <config>]

${C_BOLD}Options:${C_NC}
    -c, --config <file>  Override default config (optional)
                         Default: ~/.config/build-kernel/hooks/aw88399.conf
    --dry-run            Simulate without modifying any files
    -h, --help           Show this help

${C_BOLD}Environment (set by build-kernel):${C_NC}
    KERNEL_DIR           Kernel source directory
    KERNEL_VERSION_MMP   Kernel version (e.g. 6.19.7)
    FEDORA_RELEASE       Fedora branch (e.g. f43)
    BUILD_ID             Build identifier (e.g. .audio)
    DRY_RUN              true/false
    LOG_FILE             Shared log file path

EOF
}

# =============================================================================
# CONFIG
# =============================================================================
HOOK_CONFIG="$DEFAULT_CONFIG"

load_config() {
    local config_file="$1"

    [[ -f "$config_file" ]] \
        || { error "Hook config not found: $config_file" "exit"; }

    # shellcheck source=/dev/null
    source "$config_file"

    # Defaults
    : "${AW88399_FIX_REPO:=https://github.com/sebetc4/16iax10h-linux-sound-saga-fedora.git}"
    : "${RESOURCE_CACHE_DIR:=${HOME}/fedora-kernel-build/resources}"

    # Re-export for lib/resources.sh
    export AW88399_FIX_REPO RESOURCE_CACHE_DIR
}

validate_hook_config() {
    validation_reset

    validate_required "KERNEL_DIR (env)"           "$KERNEL_DIR"
    validate_required "KERNEL_VERSION_MMP (env)"   "$KERNEL_VERSION_MMP"
    validate_required "FEDORA_RELEASE (env)"        "$FEDORA_RELEASE"
    validate_required "AW88399_FIX_REPO"            "$AW88399_FIX_REPO"
    validate_required "RESOURCE_CACHE_DIR"          "$RESOURCE_CACHE_DIR"
    validate_path     "RESOURCE_CACHE_DIR"          "$RESOURCE_CACHE_DIR"

    [[ -d "$KERNEL_DIR" ]] \
        || validation_add_error "KERNEL_DIR does not exist: $KERNEL_DIR"

    validation_check "$HOOK_CONFIG"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)  HOOK_CONFIG="$2"; shift 2 ;;
            --dry-run)    DRY_RUN=true;     shift ;;
            -y|--yes)     shift ;;  # hook engine compatibility
            -h|--help)    _show_help; exit 0 ;;
            *) error "Unknown option: $1" "exit" ;;
        esac
    done
}

# =============================================================================
# HOOK LOGIC
# =============================================================================

_step1_fetch_resources() {
    log_section "Step 1/6 — Fetching AW88399 resources"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would clone/update: $AW88399_FIX_REPO"
        return 0
    fi

    clone_audio_fix_repo || return 1
}

_step2_select_patch() {
    log_section "Step 2/6 — Selecting patch for kernel $KERNEL_VERSION_MMP"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would call get_patch_file $KERNEL_VERSION_MMP"
        AUDIO_PATCH="/dry-run/fake.patch"
        return 0
    fi

    AUDIO_PATCH=$(get_patch_file "$KERNEL_VERSION_MMP") \
        || { log_error "No patch available for kernel $KERNEL_VERSION_MMP"; return 1; }
    log_success "Using patch: $(basename "$AUDIO_PATCH")"
}

_step3_apply_patch() {
    log_section "Step 3/6 — Applying patch to kernel.spec"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would copy $(basename "$AUDIO_PATCH") and modify kernel.spec"
        return 0
    fi

    copy_patch_to_kernel "$AUDIO_PATCH" "$KERNEL_DIR"  || return 1
    modify_kernel_spec "${KERNEL_DIR}/kernel.spec" "$AUDIO_PATCH" "$BUILD_ID" || return 1
}

_step4_configure_options() {
    log_section "Step 4/6 — Configuring audio kernel options"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would add AW88399 options to kernel-*.config files"
        return 0
    fi

    cd "$KERNEL_DIR"

    # --- add-audio-config.sh (generated and run in-place) ---
    local add_script="${KERNEL_DIR}/add-audio-config.sh"
    install -m 755 /dev/null "$add_script"
    cat > "$add_script" << 'ADDEOF'
#!/bin/bash
set -e

OPTIONS_TO_ADD=(
  "CONFIG_SND_HDA_SCODEC_AW88399"
  "CONFIG_SND_HDA_SCODEC_AW88399_I2C"
  "CONFIG_SND_SOC_SOF_INTEL_COMMON"
  "CONFIG_SND_SOC_SOF_INTEL_MTL"
  "CONFIG_SND_SOC_SOF_INTEL_LNL"
)

clean_duplicates() {
    awk '!seen[$0]++' "$1" > "$1.tmp"
    mv "$1.tmp" "$1"
}

remove_option() {
    sed -i "/^${2}=/d" "$1"
    sed -i "/^# ${2} is not set/d" "$1"
}

for config in kernel-*.config; do
    clean_duplicates "$config"
    for option in "${OPTIONS_TO_ADD[@]}"; do
        remove_option "$config" "$option"
    done
done

# x86_64 configs: enable modules
for config in kernel-x86_64*-fedora.config kernel-x86_64*-rhel.config; do
    [ -f "$config" ] || continue
    cat >> "$config" << 'AUDIOCFG'

# Audio fix for Awinic AW88399
CONFIG_SND_HDA_SCODEC_AW88399=m
CONFIG_SND_HDA_SCODEC_AW88399_I2C=m
CONFIG_SND_SOC_SOF_INTEL_COMMON=m
CONFIG_SND_SOC_SOF_INTEL_MTL=m
CONFIG_SND_SOC_SOF_INTEL_LNL=m
AUDIOCFG
done

# Other arch configs: disable
for config in kernel-*-fedora.config kernel-*-rhel.config; do
    [[ "$config" == kernel-x86_64* ]] && continue
    [ -f "$config" ] || continue
    cat >> "$config" << 'AUDIOCFG'

# Audio fix for Awinic AW88399
# CONFIG_SND_HDA_SCODEC_AW88399 is not set
# CONFIG_SND_HDA_SCODEC_AW88399_I2C is not set
# CONFIG_SND_SOC_SOF_INTEL_COMMON is not set
# CONFIG_SND_SOC_SOF_INTEL_MTL is not set
# CONFIG_SND_SOC_SOF_INTEL_LNL is not set
AUDIOCFG
done

echo "Audio configuration added"
ADDEOF

    "$add_script" || { log_error "Failed to apply audio configuration"; return 1; }
    rm -f "$add_script"

    log_success "Audio kernel options configured"

    # --- Verification summary ---
    log_section "Step 4/6 — Verifying audio options"
    local config_file="kernel-x86_64-fedora.config"
    if [[ -f "$config_file" ]]; then
        for option in \
            CONFIG_SND_HDA_SCODEC_AW88399 \
            CONFIG_SND_HDA_SCODEC_AW88399_I2C \
            CONFIG_SND_SOC_SOF_INTEL_COMMON \
            CONFIG_SND_SOC_SOF_INTEL_MTL \
            CONFIG_SND_SOC_SOF_INTEL_LNL; do
            if grep -q "^${option}=" "$config_file" 2>/dev/null; then
                log_success "  $option"
            else
                log_warn "  $option (missing)"
            fi
        done
    fi
}

_step5_validate() {
    log_section "Step 5/6 — Validating with fedpkg prep"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would run: fedpkg --release $FEDORA_RELEASE prep"
        return 0
    fi

    cd "$KERNEL_DIR"
    rm -rf kernel-*-build/ 2>/dev/null || true

    local max_attempts=2
    local attempt=1
    while ((attempt <= max_attempts)); do
        local prep_output prep_rc=0
        prep_output=$(fedpkg --release "$FEDORA_RELEASE" prep 2>&1) || prep_rc=$?

        if ((prep_rc == 0)); then
            log_success "fedpkg prep succeeded"
            return 0
        fi

        if echo "$prep_output" | grep -q "fg: no job control" && ((attempt < max_attempts)); then
            log_warn "Detected 'fg: no job control' — upgrading python-rpm-macros and retrying..."
            sudo dnf update -y python3-devel python-rpm-macros rpm-build \
                2>&1 | tee -a "${LOG_FILE:-/dev/null}" || true
            ((attempt++))
            continue
        fi

        log_error "fedpkg prep failed"
        echo "$prep_output" | tee -a "${LOG_FILE:-/dev/null}"
        return 1
    done
}

_step6_install_resources() {
    log_section "Step 6/6 — Installing firmware and UCM2"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install firmware and UCM2 config files"
        return 0
    fi

    install_firmware || { log_error "Firmware installation failed"; return 1; }
    install_ucm2     || log_warn "UCM2 installation failed (can be done manually)"
}

run_hook() {
    _step1_fetch_resources  || return 1
    _step2_select_patch     || return 1
    _step3_apply_patch      || return 1
    _step4_configure_options || return 1
    _step5_validate         || return 1
    _step6_install_resources || return 1

    log_success "AW88399 hook completed"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_arguments "$@"
    load_config "$HOOK_CONFIG"
    validate_hook_config
    run_hook
}

main "$@"
