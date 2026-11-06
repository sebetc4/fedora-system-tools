#!/usr/bin/env bats
# =============================================================================
# NOTIFY.BATS - Unit tests for lib/notify.sh
# =============================================================================
# Covers _notify_resolve_home, which decides whose notify-daemon config an
# install writes, under sudo and without it, and what notify_unregister
# leaves of what notify_register wrote, in a home under the test's temporary
# directory with systemctl stubbed.
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

# ===================
# Register and unregister
# ===================

# Point the config at the test's home, and keep the host's notify-daemon out of reach
use_test_home() {
    unset SUDO_USER
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    NOTIFY_DIR="$HOME/.config/notify-daemon"
    systemctl() { echo inactive; return 3; }
}

@test "notify_unregister: the last tag removed leaves nothing of what notify_register wrote" {
    use_test_home
    notify_register notify-demo drive-harddisk important
    [[ -f "$NOTIFY_DIR/levels.conf" ]] || { echo "levels.conf not written"; return 1; }
    notify_unregister notify-demo
    [[ ! -e "$NOTIFY_DIR" ]] || { echo "left: $(find "$NOTIFY_DIR")"; return 1; }
}

@test "notify_unregister: another tag, or a default the user changed, keeps the files" {
    use_test_home
    notify_register notify-demo drive-harddisk important
    notify_register notify-other security-high all
    notify_unregister notify-demo
    grep -qx notify-other "$NOTIFY_DIR/services.conf" || { echo "services.conf lost notify-other"; return 1; }
    grep -qx notify-other=all "$NOTIFY_DIR/levels.conf" || { echo "levels.conf lost notify-other"; return 1; }

    sed -i 's/^default=all$/default=important/' "$NOTIFY_DIR/levels.conf"
    notify_unregister notify-other
    grep -qx default=important "$NOTIFY_DIR/levels.conf" || { echo "the user's default went"; return 1; }
}
