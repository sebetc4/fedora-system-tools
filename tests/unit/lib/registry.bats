#!/usr/bin/env bats
# =============================================================================
# REGISTRY.BATS - Unit tests for lib/registry.sh
# =============================================================================
# Covers version_compare, which every install, upgrade and min_lib_version
# decision relies on, and the registry file's layout across writes and
# removals, in a registry under the test's own temporary directory.
#
# Run: make test
# =============================================================================

setup() {
    unset SUDO_USER
    export REGISTRY_PATH_OVERRIDE="$BATS_TEST_TMPDIR/config/system-scripts/registry"
    source "$BATS_TEST_DIRNAME/../../../lib/registry.sh"
}

# Assert that the registry, its installed= dates left out, reads <expected>
assert_registry() {
    local actual
    actual=$(grep -v '^installed=' "$REGISTRY_PATH_OVERRIDE")
    if [[ "$actual" != "$1" ]]; then
        printf 'expected registry:\n%s\n--- got:\n%s\n' "$1" "$actual"
        return 1
    fi
}

# Assert that version_compare <v1> <v2> succeeds and prints <expected>
assert_compare() {
    run version_compare "$1" "$2"
    if [[ "$status" -ne 0 || "$output" != "$3" ]]; then
        echo "version_compare $1 $2: expected '$3', got '$output' (status $status)"
        return 1
    fi
}

@test "version_compare: identical versions are equal" {
    assert_compare 0.1.0 0.1.0 eq
}

@test "version_compare: a lower patch is lower, a higher one higher" {
    assert_compare 0.1.0 0.1.1 lt
    assert_compare 0.1.1 0.1.0 gt
}

@test "version_compare: minor outranks patch" {
    assert_compare 0.2.0 0.1.9 gt
    assert_compare 0.1.9 0.2.0 lt
}

@test "version_compare: major outranks minor and patch" {
    assert_compare 1.0.0 0.99.99 gt
    assert_compare 0.99.99 1.0.0 lt
}

@test "version_compare: components compare as numbers, not text" {
    assert_compare 0.10.0 0.9.0 gt
    assert_compare 0.9.0 0.10.0 lt
}

@test "version_compare: a missing component counts as 0" {
    assert_compare 0.1 0.1.0 eq
    assert_compare 1 0.9.9 gt
}

@test "registry_set: rewriting the last entry adds no blank line" {
    registry_set lib 0.1.0
    registry_set notifications 0.1.0
    registry_set notifications 0.1.0
    registry_set notifications 0.2.0
    assert_registry $'# Fedora System Tools - Installation Registry\n\n[lib]\nversion=0.1.0\n\n[notifications]\nversion=0.2.0'
}

@test "registry_set: rewriting the only entry keeps the header" {
    registry_set lib 0.1.0
    registry_set lib 0.2.0
    assert_registry $'# Fedora System Tools - Installation Registry\n\n[lib]\nversion=0.2.0'
}

@test "registry_remove: removing one entry keeps the others and one blank line between them" {
    registry_set lib 0.1.0
    registry_set clamav 0.1.0
    registry_set notifications 0.1.0
    registry_remove clamav
    assert_registry $'# Fedora System Tools - Installation Registry\n\n[lib]\nversion=0.1.0\n\n[notifications]\nversion=0.1.0'
}

@test "registry_remove: removing the last entry removes the file and its empty folder" {
    registry_set notifications 0.1.0
    registry_remove notifications
    [[ ! -e "$REGISTRY_PATH_OVERRIDE" ]] || { echo "registry left"; return 1; }
    [[ ! -e "${REGISTRY_PATH_OVERRIDE%/*}" ]] || { echo "folder left"; return 1; }
}

@test "registry_remove_submodule: removing the last submodule removes the file and its empty folder" {
    registry_set_submodule backup vps 0.1.0 0.1.0
    registry_remove_submodule backup vps
    [[ ! -e "$REGISTRY_PATH_OVERRIDE" ]] || { echo "registry left"; return 1; }
    [[ ! -e "${REGISTRY_PATH_OVERRIDE%/*}" ]] || { echo "folder left"; return 1; }
}

@test "registry_remove: a folder holding other files stays" {
    registry_set notifications 0.1.0
    touch "${REGISTRY_PATH_OVERRIDE%/*}/color.conf"
    registry_remove notifications
    [[ ! -e "$REGISTRY_PATH_OVERRIDE" ]] || { echo "registry left"; return 1; }
    [[ -f "${REGISTRY_PATH_OVERRIDE%/*}/color.conf" ]] || { echo "color.conf gone"; return 1; }
}
