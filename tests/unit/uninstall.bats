#!/usr/bin/env bats
# =============================================================================
# UNINSTALL.BATS - Unit tests for uninstall.sh
# =============================================================================
# Covers module_installed, which decides the modules the complete uninstall
# hands to their uninstallers, on a system registry and a user registry under
# the test's temporary directory. Sources uninstall.sh, whose main does not
# run when sourced.
#
# Run: make test
# =============================================================================

setup() {
    export SYSTEM_REGISTRY_PATH="$BATS_TEST_TMPDIR/system-registry"
    source "$BATS_TEST_DIRNAME/../../uninstall.sh"
    REAL_REGISTRY="$BATS_TEST_TMPDIR/user-registry"
    REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" registry_set build-kernel 0.1.0
    REGISTRY_PATH_OVERRIDE="$REAL_REGISTRY" registry_set notifications 0.1.0
}

@test "module_installed: a module whose name holds a dash" {
    module_installed build-kernel || { echo "build-kernel not found"; return 1; }
}

@test "module_installed: a user module, in the user registry" {
    module_installed notifications || { echo "notifications not found"; return 1; }
}

@test "module_installed: a module in neither registry" {
    if module_installed clamav; then echo "clamav found"; return 1; fi
}
