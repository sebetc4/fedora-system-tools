#!/usr/bin/env bats
# =============================================================================
# NOTIFY.BATS - Unit tests for lib/notify.sh
# =============================================================================
# Covers _notify_resolve_home, which decides whose notify-daemon config an
# install writes, under sudo and without it.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/notify.sh"
}

@test "_notify_resolve_home: without sudo, the caller's home" {
    unset SUDO_USER
    run _notify_resolve_home
    [[ "$status" -eq 0 && "$output" == "$HOME" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "_notify_resolve_home: under sudo, the home of SUDO_USER" {
    local user expected
    user=$(id -un)
    expected=$(getent passwd "$user" | cut -d: -f6)
    SUDO_USER="$user" run _notify_resolve_home
    [[ "$status" -eq 0 && "$output" == "$expected" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "_notify_resolve_home: a SUDO_USER holding shell syntax runs nothing and fails" {
    SUDO_USER="nobody;touch $BATS_TEST_TMPDIR/ran" run _notify_resolve_home
    [[ ! -e "$BATS_TEST_TMPDIR/ran" ]] || { echo "the user name ran as a command"; return 1; }
    [[ "$status" -ne 0 ]] || { echo "an unknown user resolved to '$output'"; return 1; }
}
