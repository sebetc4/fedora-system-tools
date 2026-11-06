#!/usr/bin/env bats
# =============================================================================
# SUBMODULE.BATS - Unit tests for lib/submodule.sh
# =============================================================================
# Covers submodule_sort_uninstall, which orders an uninstall so that no
# submodule goes before one that depends on it, on a module.yml written in
# the test's temporary directory. Needs yq.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/submodule.sh"
    MODULE_YML="$BATS_TEST_TMPDIR/module.yml"
    cat > "$MODULE_YML" <<'YAML'
name: demo
submodules:
  core:
    version: 0.1.0
  scanner:
    version: 0.1.0
    deps: [core]
  report:
    version: 0.1.0
    deps: [scanner]
  quarantine:
    version: 0.1.0
    deps: [core]
  standalone:
    version: 0.1.0
YAML
}

# Assert that sorting <subs...> for uninstall gives <expected>, the last argument, one per line
assert_order() {
    local expected="${!#}"
    run submodule_sort_uninstall "$MODULE_YML" "${@:1:$#-1}"
    if [[ "$status" -ne 0 || "$output" != "$expected" ]]; then
        printf 'sorting %s: expected\n%s\n--- got (status %s):\n%s\n' "${*:1:$#-1}" "$expected" "$status" "$output"
        return 1
    fi
}

@test "submodule_sort_uninstall: dependents go before the core they depend on" {
    assert_order core scanner quarantine $'scanner\nquarantine\ncore'
}

@test "submodule_sort_uninstall: a chain goes from its end to its root" {
    assert_order core scanner report $'report\nscanner\ncore'
    assert_order report core scanner $'report\nscanner\ncore'
}

@test "submodule_sort_uninstall: independent submodules keep their order" {
    assert_order standalone quarantine $'standalone\nquarantine'
}

@test "submodule_sort_uninstall: a dependency not selected does not hold anything back" {
    assert_order core report $'core\nreport'
}

@test "submodule_sort_uninstall: one submodule comes back alone" {
    assert_order core 'core'
}
