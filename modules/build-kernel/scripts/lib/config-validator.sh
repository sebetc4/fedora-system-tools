#!/bin/bash
# =============================================================================
# CONFIG-VALIDATOR.SH - Build configuration validation
# =============================================================================
# Validates build.conf values and applies sensible defaults.
# Uses validate.sh from the shared lib for error accumulation.
#
# Module: build-kernel
# Requires: core, log, validate
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_CONFIG_VALIDATOR_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_CONFIG_VALIDATOR_LOADED=1

# =============================================================================
# DEFAULTS
# =============================================================================

apply_config_defaults() {
    : "${LOG_DIR:=/var/log/build-kernel}"
    : "${BUILD_ID:=.custom}"
    : "${MAX_VERSIONS_PER_MAJOR:=5}"
    : "${SUPPORTED_KERNEL_MAJORS:=}"
    : "${BUILD_WITHOUT_SELFTESTS:=true}"
    : "${BUILD_WITHOUT_DEBUG:=true}"
    : "${BUILD_WITHOUT_DEBUGINFO:=false}"
    : "${WORK_DIR:=$HOME/fedora-kernel-build}"
    : "${ENABLE_SIGNING:=true}"
    : "${MOK_CERT_NAME:=MOK Signing Key}"
    : "${MOK_KEY_CN:=Kernel Signing Key}"
    : "${MOK_VALIDITY_DAYS:=36500}"
    : "${ARCHIVE_RPMS:=true}"
    : "${ARCHIVE_DIR:=$HOME/kernel-archives}"
    : "${STATE_FILE:=/tmp/kernel-build-state}"
    : "${AUTO_INSTALL:=false}"
    : "${SET_DEFAULT_KERNEL:=true}"
    : "${DRY_RUN:=false}"
}

# =============================================================================
# VALIDATION
# =============================================================================

validate_build_config() {
    validation_reset

    # Paths
    validate_required "WORK_DIR" "$WORK_DIR"
    validate_path     "WORK_DIR" "$WORK_DIR"
    validate_path     "LOG_DIR"  "$LOG_DIR"
    validate_path     "ARCHIVE_DIR" "$ARCHIVE_DIR"

    # BUILD_ID must start with a dot
    if [[ -n "$BUILD_ID" && ! "$BUILD_ID" =~ ^\. ]]; then
        validation_add_error "BUILD_ID must start with '.' (e.g. '.audio') — got: '$BUILD_ID'"
    fi

    # Integers
    validate_integer "MAX_VERSIONS_PER_MAJOR" "$MAX_VERSIONS_PER_MAJOR"
    validate_integer "MOK_VALIDITY_DAYS"       "$MOK_VALIDITY_DAYS"

    # Booleans
    validate_boolean "ENABLE_SIGNING"            "$ENABLE_SIGNING"
    validate_boolean "BUILD_WITHOUT_SELFTESTS"   "$BUILD_WITHOUT_SELFTESTS"
    validate_boolean "BUILD_WITHOUT_DEBUG"       "$BUILD_WITHOUT_DEBUG"
    validate_boolean "BUILD_WITHOUT_DEBUGINFO"   "$BUILD_WITHOUT_DEBUGINFO"
    validate_boolean "ARCHIVE_RPMS"              "$ARCHIVE_RPMS"
    validate_boolean "AUTO_INSTALL"              "$AUTO_INSTALL"
    validate_boolean "SET_DEFAULT_KERNEL"        "$SET_DEFAULT_KERNEL"

    validation_check "$CONFIG_FILE"
}

# =============================================================================
# ENTRY POINT
# =============================================================================

validate_and_prepare_config() {
    apply_config_defaults
    validate_build_config
}

# =============================================================================
# DISPLAY
# =============================================================================

show_config() {
    echo ""
    echo -e "${C_BOLD}=== Build Configuration ===${C_NC}"
    echo ""
    echo -e "  ${C_BOLD}Paths${C_NC}"
    echo "    WORK_DIR=${WORK_DIR}"
    echo "    LOG_DIR=${LOG_DIR}"
    echo "    ARCHIVE_DIR=${ARCHIVE_DIR}"
    echo ""
    echo -e "  ${C_BOLD}Build${C_NC}"
    echo "    BUILD_ID=${BUILD_ID}"
    echo "    FEDORA_RELEASE=${FEDORA_RELEASE:-auto}"
    echo "    BUILD_WITHOUT_SELFTESTS=${BUILD_WITHOUT_SELFTESTS}"
    echo "    BUILD_WITHOUT_DEBUG=${BUILD_WITHOUT_DEBUG}"
    echo "    BUILD_WITHOUT_DEBUGINFO=${BUILD_WITHOUT_DEBUGINFO}"
    echo ""
    echo -e "  ${C_BOLD}Signing${C_NC}"
    echo "    ENABLE_SIGNING=${ENABLE_SIGNING}"
    echo "    MOK_KEY_DIR=${MOK_KEY_DIR:-default}"
    echo "    MOK_CERT_NAME=${MOK_CERT_NAME}"
    echo ""
}
