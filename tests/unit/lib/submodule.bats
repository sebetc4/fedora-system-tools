#!/usr/bin/env bats
# =============================================================================
# SUBMODULE.BATS - Unit tests for lib/submodule.sh
# =============================================================================
# Covers what the engine decides before it touches the system: uninstall
# order, submodule types and dependents, missing packages, logrotate names,
# which directories an uninstall may remove and prune, hook scripts, config
# files, and the orchestrators' options. Everything is written under the
# test's temporary directory, in a registry and a home of its own. Needs yq.
#
# Run: make test
# =============================================================================

setup() {
    unset SUDO_USER
    export REGISTRY_PATH_OVERRIDE="$BATS_TEST_TMPDIR/registry"
    export SUBMODULE_HOOKS_DIR="$BATS_TEST_TMPDIR/hooks.d"
    source "$BATS_TEST_DIRNAME/../../../lib/submodule.sh"

    # The context the engine resolves for a submodule, pointed at a home of the test's
    _real_user=$(id -un)
    _real_home="$BATS_TEST_TMPDIR/home"
    mkdir -p "$_real_home"

    # A checkout of the test's, its my-config/ beside modules/
    CHECKOUT="$BATS_TEST_TMPDIR/checkout"
    MODULE_DIR="$CHECKOUT/modules/demo"
    MODULE_YML="$MODULE_DIR/module.yml"
    mkdir -p "$MODULE_DIR"
    cat > "$MODULE_YML" <<'YAML'
name: demo
type: system
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
  agent:
    version: 0.1.0
    type: user
  agent-report:
    version: 0.1.0
    deps: [agent]
  units:
    version: 0.1.0
    services: [services/scan.service, services/watch.service.tpl, services/usb@.service]
    timers: [timers/scan.timer]
  hooked:
    version: 0.1.0
    hook_scripts: hooks.d
  configured:
    version: 0.1.0
    configs:
      - source: config.yml
        dest: ~/.config/demo/demo.yml
      - source: hooks-config/check.yml
        dest: ~/.config/demo/hooks/check.yml
  broken-hook:
    version: 0.1.0
    hooks:
      install: shared/missing.sh
YAML
}

# Fail with a message naming what was expected and what came
expect() {
    if [[ "$2" != "$3" ]]; then
        printf '%s: expected\n%s\n--- got:\n%s\n' "$1" "$3" "$2"
        return 1
    fi
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

# ===================
# Uninstall order
# ===================

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

# ===================
# Types and dependents
# ===================

@test "_submodule_type: a submodule's own type overrides the module's" {
    expect agent "$(_submodule_type agent "$MODULE_YML")" user
    expect core "$(_submodule_type core "$MODULE_YML")" system
}

@test "_submodule_type: a module without a type is a system module" {
    printf 'name: bare\nsubmodules:\n  only:\n    version: 0.1.0\n' > "$BATS_TEST_TMPDIR/bare.yml"
    expect only "$(_submodule_type only "$BATS_TEST_TMPDIR/bare.yml")" system
}

@test "_submodule_dependents: a system dependent of a user submodule is found in the system registry" {
    registry_set_submodule demo agent-report 0.1.0 0.1.0
    run _submodule_dependents demo agent "$MODULE_YML"
    expect "dependents of agent" "$output" agent-report
}

@test "_submodule_dependents: a dependent not installed holds nothing back" {
    registry_set_submodule demo scanner 0.1.0 0.1.0
    run _submodule_dependents demo core "$MODULE_YML"
    expect "dependents of core" "$output" scanner
    run _submodule_dependents demo scanner "$MODULE_YML"
    expect "dependents of scanner" "$output" ""
}

# ===================
# Packages and names
# ===================

@test "_submodule_missing_packages: names packages, not commands" {
    command -v rpm >/dev/null || skip "rpm is not installed"
    run _submodule_missing_packages bash glibc no-such-package-fst
    expect "missing among bash, glibc, no-such-package-fst" "$output" no-such-package-fst
}

@test "_submodule_logrotate_dest: a template goes under the user's name" {
    _real_user=alice
    expect template "$(_submodule_logrotate_dest bitwarden/logrotate/backup-bitwarden.tpl)" \
        /etc/logrotate.d/alice-backup-bitwarden
    expect static "$(_submodule_logrotate_dest logrotate/backup-scripts)" /etc/logrotate.d/backup-scripts
}

@test "_submodule_units: timers first, templates under their rendered name" {
    run _submodule_units units "$MODULE_YML"
    expect units "$output" $'scan.timer\nscan.service\nwatch.service\nusb@.service'
}

# ===================
# Removal guards
# ===================

@test "_submodule_removable_dir: refuses a path an uninstall must never remove" {
    local dir
    for dir in / /var relative/dir /var/log/../.. /var/./log //var/log \
        "$_real_home" "$_real_home/" "$_real_home/.local" "$_real_home/.local/../.."; do
        if _submodule_removable_dir "$dir"; then
            echo "accepted $dir"
            return 1
        fi
    done
}

@test "_submodule_removable_dir: accepts a module's own directory" {
    local dir
    for dir in /var/log/backup /var/quarantine "$_real_home/.local/log/backup-vps"; do
        _submodule_removable_dir "$dir" || { echo "refused $dir"; return 1; }
    done
}

@test "_submodule_removable_dir: refuses a directory a package owns" {
    command -v rpm >/dev/null && rpm -qf /var/log >/dev/null 2>&1 || skip "no package owns /var/log here"
    if _submodule_removable_dir /var/log; then
        echo "accepted /var/log"
        return 1
    fi
}

@test "_submodule_prune_home_dir: removes empty folders up to the home's direct children" {
    mkdir -p "$_real_home/.local/log" "$_real_home/.config/systemd/user/timers.target.wants"
    _submodule_prune_home_dir "$_real_home/.local/log/backup-vps"
    _submodule_prune_home_dir "$_real_home/.config/systemd/user/timers.target.wants"
    [[ ! -e "$_real_home/.local/log" ]] || { echo ".local/log kept"; return 1; }
    [[ ! -e "$_real_home/.config/systemd" ]] || { echo ".config/systemd kept"; return 1; }
    [[ -d "$_real_home/.local" && -d "$_real_home/.config" ]] || { echo "a direct child of the home went"; return 1; }
}

@test "_submodule_prune_home_dir: keeps a folder holding anything" {
    mkdir -p "$_real_home/.local/log/other"
    _submodule_prune_home_dir "$_real_home/.local/log/backup-vps"
    [[ -d "$_real_home/.local/log/other" ]] || { echo ".local/log/other went"; return 1; }
}

@test "_submodule_prune_home_dir: never acts outside the home" {
    mkdir -p "$BATS_TEST_TMPDIR/outside/a/b"
    _submodule_prune_home_dir "$BATS_TEST_TMPDIR/outside/a/b"
    [[ -d "$BATS_TEST_TMPDIR/outside/a/b" ]] || { echo "a folder outside the home went"; return 1; }
}

# ===================
# Hook scripts and configs
# ===================

@test "_uninstall_submodule_hooks: removes the module's hook scripts and keeps the user's" {
    mkdir -p "$MODULE_DIR/hooks.d/pre-backup"
    printf '#!/bin/bash\n' > "$MODULE_DIR/hooks.d/pre-backup/shipped.sh"
    _install_submodule_hooks "$MODULE_DIR" hooked "$MODULE_YML" > /dev/null
    [[ -x "$SUBMODULE_HOOKS_DIR/pre-backup/shipped.sh" ]] || { echo "shipped.sh not installed"; return 1; }
    printf '#!/bin/bash\n' > "$SUBMODULE_HOOKS_DIR/pre-backup/mine.sh"

    _uninstall_submodule_hooks "$MODULE_DIR" hooked "$MODULE_YML"
    [[ ! -e "$SUBMODULE_HOOKS_DIR/pre-backup/shipped.sh" ]] || { echo "shipped.sh kept"; return 1; }
    [[ -f "$SUBMODULE_HOOKS_DIR/pre-backup/mine.sh" ]] || { echo "the user's mine.sh went"; return 1; }
}

@test "_uninstall_submodule_hooks: leaves no empty folder behind" {
    mkdir -p "$MODULE_DIR/hooks.d/pre-backup"
    printf '#!/bin/bash\n' > "$MODULE_DIR/hooks.d/pre-backup/shipped.sh"
    _install_submodule_hooks "$MODULE_DIR" hooked "$MODULE_YML" > /dev/null
    _uninstall_submodule_hooks "$MODULE_DIR" hooked "$MODULE_YML"
    [[ ! -e "$SUBMODULE_HOOKS_DIR" ]] || { echo "hooks.d kept: $(find "$SUBMODULE_HOOKS_DIR")"; return 1; }
}

# Write the module's two default configs
write_default_configs() {
    mkdir -p "$MODULE_DIR/hooks-config"
    printf 'value: default\n' > "$MODULE_DIR/config.yml"
    printf 'hook: default\n' > "$MODULE_DIR/hooks-config/check.yml"
}

@test "_install_submodule_configs: without a copy, the module's default" {
    write_default_configs
    _install_submodule_configs "$MODULE_DIR" configured "$MODULE_YML" > /dev/null
    expect demo.yml "$(cat "$_real_home/.config/demo/demo.yml")" "value: default"
    expect check.yml "$(cat "$_real_home/.config/demo/hooks/check.yml")" "hook: default"
}

@test "_install_submodule_configs: the user's copy in my-config/ comes before the default" {
    write_default_configs
    mkdir -p "$CHECKOUT/my-config/modules/demo/hooks-config"
    printf 'hook: mine\n' > "$CHECKOUT/my-config/modules/demo/hooks-config/check.yml"
    run _install_submodule_configs "$MODULE_DIR" configured "$MODULE_YML"
    expect "check.yml, from the copy" "$(cat "$_real_home/.config/demo/hooks/check.yml")" "hook: mine"
    expect "demo.yml, no copy" "$(cat "$_real_home/.config/demo/demo.yml")" "value: default"
    [[ "$output" == *"check.yml (from my-config)"* ]] || { echo "the copy is not named: $output"; return 1; }
}

@test "_install_submodule_configs: MY_CONFIG_DIR points at the copies elsewhere" {
    write_default_configs
    mkdir -p "$BATS_TEST_TMPDIR/copies/modules/demo"
    printf 'value: elsewhere\n' > "$BATS_TEST_TMPDIR/copies/modules/demo/config.yml"
    MY_CONFIG_DIR="$BATS_TEST_TMPDIR/copies" _install_submodule_configs "$MODULE_DIR" configured "$MODULE_YML" > /dev/null
    expect demo.yml "$(cat "$_real_home/.config/demo/demo.yml")" "value: elsewhere"
}

@test "_install_submodule_configs: an installed config is never overwritten" {
    write_default_configs
    _install_submodule_configs "$MODULE_DIR" configured "$MODULE_YML" > /dev/null
    printf 'value: edited\n' > "$_real_home/.config/demo/demo.yml"
    mkdir -p "$CHECKOUT/my-config/modules/demo"
    printf 'value: mine\n' > "$CHECKOUT/my-config/modules/demo/config.yml"
    run _install_submodule_configs "$MODULE_DIR" configured "$MODULE_YML"
    expect "second install" "$(cat "$_real_home/.config/demo/demo.yml")" "value: edited"
    [[ "$output" == *"differs from"*"my-config/modules/demo/config.yml"* ]] || { echo "the difference is not said: $output"; return 1; }
    run _show_preserved_configs configured "$MODULE_YML"
    [[ "$output" == *"$_real_home/.config/demo/demo.yml"* ]] || { echo "not shown as kept: $output"; return 1; }
}

@test "submodule_install: a declared install hook that is missing stops the install" {
    run submodule_install "$MODULE_DIR" broken-hook "$MODULE_YML"
    [[ "$status" -ne 0 ]] || { echo "installed without its hook: $output"; return 1; }
    [[ "$output" == *"Install hook not found"* ]] || { echo "no message naming the hook: $output"; return 1; }
    ! registry_is_submodule_installed demo broken-hook || { echo "registered"; return 1; }
}

# ===================
# Orchestrator options
# ===================

@test "_submodule_parse_args: reads --all, --only and --force" {
    local _mode _only _force
    _submodule_parse_args true --force --only core,scanner
    expect "--force --only" "$_mode $_only $_force" "only core,scanner true"
    _submodule_parse_args true --all
    expect "--all" "$_mode $_force" "all false"
    _submodule_parse_args false
    expect "no option" "$_mode" interactive
}

@test "_submodule_parse_args: an unknown option, or --only without a list, is an error" {
    local _mode _only _force args
    for args in "--bogus" "--only" "--only --all" "--all extra"; do
        # shellcheck disable=SC2086  # split on purpose
        if _submodule_parse_args true $args 2>/dev/null; then
            echo "accepted: $args"
            return 1
        fi
    done
    if _submodule_parse_args false --force 2>/dev/null; then
        echo "an uninstall accepted --force"
        return 1
    fi
}

@test "_submodule_check_names: an unknown submodule is an error" {
    _submodule_check_names "$MODULE_YML" core scanner
    run _submodule_check_names "$MODULE_YML" core nope
    [[ "$status" -ne 0 && "$output" == *"Unknown submodule: nope"* ]] || { echo "got: $output (status $status)"; return 1; }
}
