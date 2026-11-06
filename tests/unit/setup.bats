#!/usr/bin/env bats
# =============================================================================
# SETUP.BATS - Unit tests for setup.sh
# =============================================================================
# Covers what setup.sh decides before it calls a module's installer: the
# submodules each action applies to, the dependents an uninstall adds, the
# targets of upgrade and reinstall, its options and its color values. Sources
# setup.sh, whose main does not run when sourced, with a module.yml, a home
# and a system registry under the test's temporary directory, and
# install_module stubbed to print what it would run. Needs yq.
#
# Run: make test
# =============================================================================

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    export SYSTEM_REGISTRY_PATH="$BATS_TEST_TMPDIR/system-registry"
    mkdir -p "$HOME"
    unset SUDO_USER
    source "$BATS_TEST_DIRNAME/../../setup.sh"
    # setup.sh's ERR trap would end a test that runs a failure on purpose
    trap - ERR

    mkdir -p "$BATS_TEST_TMPDIR/modules/demo"
    cat > "$BATS_TEST_TMPDIR/modules/demo/module.yml" <<'YAML'
name: demo
version: 0.1.0
description: "Demo module"
type: system
submodules:
  core:
    version: 0.1.0
  scanner:
    version: 0.2.0
    deps: [core]
  report:
    version: 0.1.0
    deps: [scanner]
  agent:
    version: 0.1.0
    type: user
YAML
    _discover_module "$BATS_TEST_TMPDIR/modules/demo/module.yml"

    # core is up to date, scanner outdated, report not installed, agent in the user registry
    system() { REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" "$@"; }
    system registry_set demo 0.1.0
    system registry_set demo/core 0.1.0
    system registry_set demo/scanner 0.1.0
    REGISTRY_PATH_OVERRIDE="$USER_REGISTRY" registry_set demo/agent 0.1.0

    MODE="cli"
    # shellcheck disable=SC2329  # called by the functions under test
    install_module() { echo "install_module $* force=${INSTALL_FORCE:-false}"; }
}

# Fail with a message naming what was expected and what came
expect() {
    if [[ "$2" != "$3" ]]; then
        printf '%s: expected\n%s\n--- got:\n%s\n' "$1" "$3" "$2"
        return 1
    fi
}

@test "_candidates: what each action applies to, in module.yml's order" {
    expect install "$(_candidates install demo)" $'scanner\nreport'
    expect upgrade "$(_candidates upgrade demo)" 'scanner'
    expect reinstall "$(_candidates reinstall demo)" $'core\nscanner\nagent'
    expect uninstall "$(_candidates uninstall demo)" $'core\nscanner\nagent'
}

@test "_installed_version: the user registry answers for a user submodule" {
    expect agent "$(_installed_version demo/agent)" 0.1.0
    expect report "$(_installed_version demo/report)" ""
}

@test "_with_dependents: an uninstall of core takes what depends on it, at any depth" {
    system registry_set demo/report 0.1.0
    run _with_dependents demo core
    expect picked "$(grep -v Adding <<< "$output")" $'core\nscanner\nreport'
}

@test "_reinstall_module: a module's reinstall takes its installed submodules alone" {
    run _reinstall_module demo
    expect "reinstall demo" "$output" "install_module demo core,scanner,agent force=true"
}

@test "cli_upgrade: a module's upgrade takes its outdated submodules alone" {
    run cli_upgrade demo
    expect "upgrade demo" "$output" "install_module demo scanner force=false"
}

@test "cli_upgrade: a submodule not installed is not installed by an upgrade" {
    run cli_upgrade demo/report
    [[ "$status" -ne 0 && "$output" == *"not installed"* && "$output" != *install_module* ]] \
        || { echo "status $status: $output"; return 1; }
}

@test "cli_upgrade, cli_reinstall: one submodule" {
    run cli_upgrade demo/scanner
    expect "upgrade demo/scanner" "$output" "install_module demo scanner force=false"
    run cli_upgrade demo/core
    [[ "$output" == *"up to date"* ]] || { echo "core: $output"; return 1; }
    run cli_reinstall demo/core
    expect "reinstall demo/core" "$output" "install_module demo core force=true"
}

@test "parse_args: targets, and an unknown option or a missing target is an error" {
    parse_args --install demo/core
    expect "--install" "$MODE $CLI_TARGET" "install demo/core"
    parse_args --upgrade
    expect "--upgrade" "$MODE:$CLI_TARGET" "upgrade:"
    run parse_args --bogus
    [[ "$status" -ne 0 && "$output" == *"Unknown option"* ]] || { echo "--bogus: $output"; return 1; }
    run parse_args --install
    [[ "$status" -ne 0 ]] || { echo "--install without a target was accepted"; return 1; }
}

@test "validate_target: an unknown module or submodule is an error" {
    validate_target demo/core
    run validate_target demo/nope
    [[ "$status" -ne 0 && "$output" == *"Unknown submodule"* ]] || { echo "demo/nope: $output"; return 1; }
    run validate_target nope
    [[ "$status" -ne 0 && "$output" == *"Unknown module"* ]] || { echo "nope: $output"; return 1; }
}

@test "_color_valid: ANSI 0 to 255 and hex colors" {
    local value
    for value in 0 6 08 255 "#abc" "#4f9872"; do
        _color_valid "$value" || { echo "refused $value"; return 1; }
    done
    for value in 256 -1 "#abcd" "4f9872" "red" ""; do
        if _color_valid "$value"; then echo "accepted $value"; return 1; fi
    done
}
