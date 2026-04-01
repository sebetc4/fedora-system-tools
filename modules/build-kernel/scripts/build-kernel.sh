#!/bin/bash
# =============================================================================
# BUILD-KERNEL - Custom Fedora kernel builder with pre-build hook support
# =============================================================================
# Orchestrates the full kernel build workflow:
#   1. MOK signing setup (with reboot support)
#   2. Clone / update Fedora kernel repository
#   3. Select desired kernel version
#   4. Download sources and install build deps
#   [PRE_BUILD hooks] — patches, config, firmware, ... (hook-managed)
#   5. Build kernel RPMs (fedpkg local)
#   6. Install kernel RPMs (dnf install)
#   7. Sign kernel for Secure Boot (pesign)
#   8. Archive RPMs and cleanup
#
# Module: build-kernel
# Requires: core, log, ui, validate
# Version: 0.1.0
#
# Usage:
#   build-kernel [options]
#
# Options:
#   -c, --config FILE    Use custom config file
#   -v, --version VER    Build specific kernel version (skip interactive selection)
#   --setup-mok          Setup MOK signing only (interactive)
#   --check              Quick check of system status
#   --skip-setup         Skip pre-flight setup phase
#   --skip-cleanup       Keep build directories after build
#   --cleanup-only       Archive RPMs and remove build dirs (no build)
#   --no-sign            Build without signing (overrides ENABLE_SIGNING)
#   -h, --help           Show this help
# =============================================================================

set -euo pipefail
trap '_notify "user.error" "dialog-error" "Build failed" "Kernel build failed at line $LINENO — check the log"; echo "ERROR: build-kernel failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"
readonly BUILD_KERNEL_LIB="/usr/local/lib/build-kernel"

if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: Shared library not installed. Run: sudo make install-lib" >&2
    exit 1
fi

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/validate.sh"

check_root

for _lib in config-validator version-detection mok-manager signing setup cleanup hooks; do
    # shellcheck source=/dev/null
    source "${BUILD_KERNEL_LIB}/${_lib}.sh"
done
unset _lib

# =============================================================================
# NOTIFICATIONS
# =============================================================================
readonly LOG_TAG="build-kernel"

_notify() {
    local priority="$1"   # user.notice | user.warning | user.error
    local icon="$2"
    local title="$3"
    local message="$4"
    logger -t "$LOG_TAG" -p "$priority" "[ICON:${icon}] ${title}: ${message}" 2>/dev/null || true
}

# =============================================================================
# CONFIGURATION
# =============================================================================

# Resolve real user home — the script runs as root (sudo) but config lives
# in the invoking user's home directory.
_REAL_USER="${SUDO_USER:-$USER}"
_REAL_HOME="$(getent passwd "$_REAL_USER" | cut -d: -f6)"

readonly DEFAULT_CONFIG="${_REAL_HOME}/.config/build-kernel/build.conf"
CONFIG_FILE="${DEFAULT_CONFIG}"

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
KERNEL_VERSION=""
SKIP_SETUP=false
SKIP_CLEANUP=false
CLEANUP_ONLY=false
SETUP_MOK_ONLY=false
CHECK_ONLY=false
NO_SIGN=false

_show_help() {
    grep "^#" "$0" | grep -v "^#!/" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            [[ -n "${2:-}" ]] || { error "--config requires a file path" "exit"; }
            CONFIG_FILE="$2"; shift 2 ;;
        -v|--version)
            [[ -n "${2:-}" ]] || { error "--version requires a version string" "exit"; }
            KERNEL_VERSION="$2"; shift 2 ;;
        --setup-mok)    SETUP_MOK_ONLY=true;  shift ;;
        --check)        CHECK_ONLY=true;       shift ;;
        --skip-setup)   SKIP_SETUP=true;       shift ;;
        --skip-cleanup) SKIP_CLEANUP=true;     shift ;;
        --cleanup-only) CLEANUP_ONLY=true;     shift ;;
        --no-sign)      NO_SIGN=true;          shift ;;
        -h|--help)      _show_help; exit 0 ;;
        *) error "Unknown option: $1 — use --help" "exit" ;;
    esac
done

# =============================================================================
# LOAD CONFIGURATION
# =============================================================================
[[ -f "$CONFIG_FILE" ]] \
    || { error "Config file not found: $CONFIG_FILE" "exit"; }

# shellcheck source=/dev/null
source "$CONFIG_FILE"

[[ "$NO_SIGN" == "true" ]] && ENABLE_SIGNING=false

validate_and_prepare_config

# =============================================================================
# INIT LOGGING
# =============================================================================
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/build-$(date +%Y-%m-%d-%H-%M-%S).log"
log_open_fd
trap 'log_close_fd' EXIT

log_section "Fedora Kernel Build"
log "Config:    $CONFIG_FILE"
log "Log:       $LOG_FILE"
log "Work dir:  $WORK_DIR"

_notify "user.notice" "applications-development" "Build started" "Fedora kernel build initiated"

# =============================================================================
# MODE: Quick Check
# =============================================================================
if [[ "$CHECK_ONLY" == "true" ]]; then
    quick_setup_check
    exit 0
fi

# =============================================================================
# MODE: MOK Setup Only
# =============================================================================
if [[ "$SETUP_MOK_ONLY" == "true" ]]; then
    show_mok_status
    if check_signing_prerequisites; then
        log_success "Signing already fully configured"
    fi
    setup_mok_workflow
    exit $?
fi

# =============================================================================
# MODE: Cleanup Only
# =============================================================================
if [[ "$CLEANUP_ONLY" == "true" ]]; then
    log_section "Cleanup Only Mode"
    KERNEL_DIR="${WORK_DIR}/kernel"

    if [[ -d "${KERNEL_DIR}/x86_64" ]]; then
        BUILT_KERNEL_VERSION=$(find "${KERNEL_DIR}/x86_64" -maxdepth 1 \
            -name "kernel-[0-9]*.rpm" -type f 2>/dev/null \
            | head -1 \
            | grep -oP 'kernel-\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[^.]+\.fc[0-9]+\.x86_64' \
            || echo "")
        if [[ -n "$BUILT_KERNEL_VERSION" ]]; then
            run_cleanup "$BUILT_KERNEL_VERSION"
            log_success "Cleanup completed"
        else
            log_error "No kernel RPMs found in ${KERNEL_DIR}/x86_64"
            exit 1
        fi
    else
        log_error "Build directory not found: ${KERNEL_DIR}/x86_64"
        exit 1
    fi
    exit 0
fi

# =============================================================================
# PHASE 0: Pre-flight Setup
# =============================================================================
if [[ "$SKIP_SETUP" == "false" ]]; then
    run_setup || { log_error "Pre-flight setup failed"; exit 1; }
else
    log "Skipping pre-flight setup (--skip-setup)"
fi

# =============================================================================
# PHASE 1: Pre-requisites
# =============================================================================
log_section "Phase 1: Pre-requisites"

if [[ -z "${FEDORA_RELEASE:-}" ]]; then
    FEDORA_RELEASE=$(detect_fedora_release) \
        || { log_error "Failed to detect Fedora release"; exit 1; }
    log "Auto-detected Fedora release: $FEDORA_RELEASE"
else
    log "Using configured Fedora release: $FEDORA_RELEASE"
fi

check_deps git fedpkg rpmbuild dnf

# =============================================================================
# PHASE 2: Kernel Source Preparation
# =============================================================================
log_section "Phase 2: Kernel Source Preparation"

mkdir -p "$WORK_DIR"
KERNEL_DIR="${WORK_DIR}/kernel"

log_step "Setting up Fedora kernel repository"

if [[ -d "$KERNEL_DIR" ]]; then
    log "Updating existing kernel repository..."
    git -C "$KERNEL_DIR" fetch --all || log_warn "Failed to fetch updates"
else
    log "Cloning Fedora kernel repository (this may take a while)..."
    fedpkg clone -a kernel "$KERNEL_DIR" \
        || { log_error "Failed to clone kernel repository"; exit 1; }
fi

log_success "Kernel repository ready: $KERNEL_DIR"

log_step "Checking out Fedora ${FEDORA_RELEASE} branch"
git -C "$KERNEL_DIR" checkout "$FEDORA_RELEASE" \
    || { log_error "Failed to checkout branch $FEDORA_RELEASE"; exit 1; }
log_success "Branch $FEDORA_RELEASE checked out"

# =============================================================================
# PHASE 3: Version Selection
# =============================================================================
log_section "Phase 3: Kernel Version Selection"

if [[ -n "$KERNEL_VERSION" ]]; then
    SELECTED_VERSION="$KERNEL_VERSION"
    log "Using specified version: $SELECTED_VERSION"
else
    log_step "Detecting available kernel versions..."
    AVAILABLE_VERSIONS=$(list_available_kernel_versions "$KERNEL_DIR" "$MAX_VERSIONS_PER_MAJOR") \
        || { log_error "Failed to list kernel versions"; exit 1; }

    VERSION_COUNT=$(echo "$AVAILABLE_VERSIONS" | wc -l)
    log_success "Found $VERSION_COUNT versions"

    SELECTED_VERSION=$(select_kernel_version "$AVAILABLE_VERSIONS") \
        || { log_error "No version selected"; exit 1; }

    [[ -n "$SELECTED_VERSION" ]] || { log_error "No version selected"; exit 1; }
fi

log_success "Selected: kernel-${SELECTED_VERSION}"

# major.minor.patch (e.g. 6.19.7) — exported for PRE_BUILD hooks via hooks.sh
# shellcheck disable=SC2034
KERNEL_VERSION_MMP=$(echo "$SELECTED_VERSION" | grep -oP '^\d+\.\d+\.\d+')

# Find the commit
log_step "Finding commit for kernel-${SELECTED_VERSION}..."
COMMIT_HASH=$(find_commit_for_version "$KERNEL_DIR" "$SELECTED_VERSION") \
    || { log_error "Commit not found for $SELECTED_VERSION"; exit 1; }
log_success "Commit: $COMMIT_HASH"

# Create build branch
BUILD_BRANCH="build-${SELECTED_VERSION}"
log_step "Creating build branch: $BUILD_BRANCH"
git -C "$KERNEL_DIR" branch -D "$BUILD_BRANCH" 2>/dev/null || true
git -C "$KERNEL_DIR" checkout -b "$BUILD_BRANCH" "$COMMIT_HASH" \
    || { log_error "Failed to create build branch"; exit 1; }
log_success "Build branch ready: $BUILD_BRANCH"

# =============================================================================
# PHASE 4: Download Sources
# =============================================================================
log_section "Phase 4: Downloading Kernel Sources"

cd "$KERNEL_DIR"

log_step "Downloading source archives (fedpkg sources)..."
fedpkg sources || { log_error "Failed to download sources"; exit 1; }
ls ./*.tar.xz &>/dev/null || { log_error "Source tarball not found"; exit 1; }
log_success "Sources downloaded"

log_step "Installing build dependencies (dnf builddep)..."
if sudo dnf builddep -y kernel.spec; then
    log_success "Build dependencies installed"
else
    log_warn "Some build deps may have failed (may already be installed)"
fi

# =============================================================================
# PRE-BUILD HOOKS
# =============================================================================
# Hooks are fully autonomous: they download their own resources,
# apply patches, modify kernel.spec and config files, etc.
# A failing hook aborts the build immediately.
run_build_hooks "PRE_BUILD"

# =============================================================================
# PHASE 5: Build Kernel
# =============================================================================
log_section "Phase 5: Building Kernel"

log "Build started at: $(date '+%Y-%m-%d %H:%M:%S')"
log "This will take 1-5 hours depending on your machine..."

# Assemble fedpkg options
_fedpkg_opts=()
[[ "${BUILD_WITHOUT_SELFTESTS:-true}"  == "true" ]] && _fedpkg_opts+=(--without selftests)
[[ "${BUILD_WITHOUT_DEBUG:-true}"      == "true" ]] && _fedpkg_opts+=(--without debug)
[[ "${BUILD_WITHOUT_DEBUGINFO:-false}" == "true" ]] && _fedpkg_opts+=(--without debuginfo)

log "Build options: ${_fedpkg_opts[*]:-none}"

BUILD_START=$(date +%s)

# shellcheck disable=SC2086
fedpkg --release "$FEDORA_RELEASE" local "${_fedpkg_opts[@]}" \
    || { log_error "Kernel build failed"; exit 1; }

BUILD_DURATION=$(( $(date +%s) - BUILD_START ))
log_success "Build completed in $(( BUILD_DURATION / 60 )) minutes"

# Verify RPMs
RPM_DIR="${KERNEL_DIR}/x86_64"
[[ -d "$RPM_DIR" ]] || { log_error "RPM directory not found: $RPM_DIR"; exit 1; }

RPM_COUNT=$(find "$RPM_DIR" -name "*.rpm" -type f | wc -l)
(( RPM_COUNT > 0 )) || { log_error "No RPMs generated"; exit 1; }
log_success "Generated ${RPM_COUNT} RPM packages"

# =============================================================================
# PHASE 6: Install Kernel RPMs
# =============================================================================
log_section "Phase 6: Installing Kernel RPMs"

# Build can take hours — sudo session has likely expired.
# Send a desktop notification and prompt for re-authentication before proceeding.
_notify "user.warning" "dialog-password" \
    "Authentication required" \
    "Kernel build complete — sudo needed for install phase"
log "Build complete. Re-authenticating for install phase (sudo session may have expired)..."
sudo -v || { log_error "sudo authentication failed — cannot install kernel RPMs"; exit 1; }
log_success "Authentication confirmed"

KERNEL_RPM=$(find "$RPM_DIR" -name "kernel-[0-9]*.rpm" -type f \
    | grep -v "kernel-core\|kernel-modules\|kernel-devel\|kernel-headers" \
    | head -1)

[[ -n "$KERNEL_RPM" ]] || { log_error "No kernel RPM found"; exit 1; }

KERNEL_VERSION_FULL=$(basename "$KERNEL_RPM" .rpm | sed 's/^kernel-//')
log "Installing kernel: $KERNEL_VERSION_FULL"

INSTALL_LIST=()
for _pkg in \
    "kernel-${KERNEL_VERSION_FULL}.rpm" \
    "kernel-core-${KERNEL_VERSION_FULL}.rpm" \
    "kernel-modules-${KERNEL_VERSION_FULL}.rpm" \
    "kernel-modules-core-${KERNEL_VERSION_FULL}.rpm" \
    "kernel-modules-extra-${KERNEL_VERSION_FULL}.rpm" \
    "kernel-devel-${KERNEL_VERSION_FULL}.rpm"; do
    [[ -f "${RPM_DIR}/${_pkg}" ]] && INSTALL_LIST+=("${RPM_DIR}/${_pkg}")
done
unset _pkg

(( ${#INSTALL_LIST[@]} > 0 )) || { log_error "No RPMs found to install"; exit 1; }

sudo dnf install -y "${INSTALL_LIST[@]}" \
    || { log_error "Failed to install kernel RPMs"; exit 1; }
log_success "Kernel RPMs installed"

VMLINUZ_PATH="/boot/vmlinuz-${KERNEL_VERSION_FULL}"
if [[ -f "$VMLINUZ_PATH" ]]; then
    log_success "Kernel verified: $VMLINUZ_PATH"
else
    log_error "Kernel not found at $VMLINUZ_PATH after installation"
    exit 1
fi

# =============================================================================
# PHASE 7: Sign Kernel
# =============================================================================
if [[ "${ENABLE_SIGNING:-true}" == "true" ]]; then
    sign_kernel_pesign "$VMLINUZ_PATH" "${MOK_CERT_NAME:-MOK Signing Key}" \
        || log_warn "Kernel signing failed — kernel will boot but Secure Boot may reject it"
else
    log "Kernel signing disabled (ENABLE_SIGNING=false or --no-sign)"
fi

# =============================================================================
# PHASE 8: Cleanup and Archive
# =============================================================================
if [[ "$SKIP_CLEANUP" == "false" ]]; then
    if run_cleanup "${KERNEL_VERSION_FULL}"; then
        log_success "Cleanup completed"
    else
        log_warn "Cleanup failed or cancelled"
        log "Build artifacts preserved at: $WORK_DIR"
    fi
else
    log "Skipping cleanup (--skip-cleanup)"
    log "Build artifacts preserved at: $WORK_DIR"
fi

# =============================================================================
# BUILD COMPLETE
# =============================================================================
_notify "user.notice" "dialog-information" \
    "Build successful" \
    "Kernel ${KERNEL_VERSION_FULL} installed — reboot to use it"

echo ""
ui_banner "Kernel Build Successful!" \
    "Kernel:  ${KERNEL_VERSION_FULL}" \
    "Log:     ${LOG_FILE}" \
    "Signing: $( [[ "${ENABLE_SIGNING:-true}" == "true" ]] && echo "Enabled" || echo "Disabled" )"

if [[ "${SET_DEFAULT_KERNEL:-true}" == "true" ]]; then
    if sudo grubby --set-default="$VMLINUZ_PATH"; then
        log_success "Set as default boot kernel"
    else
        log_warn "Could not set as default — run manually: sudo grubby --set-default=${VMLINUZ_PATH}"
    fi
fi

echo ""
log "Next steps:"
log "  1. Reboot:              sudo reboot"
log "  2. Verify:              uname -r"
log "  3. Check log:           $LOG_FILE"
echo ""

log_close_fd
