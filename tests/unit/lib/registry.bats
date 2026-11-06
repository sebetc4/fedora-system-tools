#!/usr/bin/env bats
# =============================================================================
# REGISTRY.BATS - Unit tests for lib/registry.sh
# =============================================================================
# Covers version_compare, which every install, upgrade and min_lib_version
# decision relies on.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/registry.sh"
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
