#!/usr/bin/env bats
# =============================================================================
# UI.BATS - Unit tests for lib/ui.sh
# =============================================================================
# Covers ui_press_enter, which ends every module installer, run where no
# terminal can answer it, as the VM harness runs installers over ssh.
#
# Run: make test
# =============================================================================

setup() {
    LIB="$BATS_TEST_DIRNAME/../../../lib"
}

@test "ui_press_enter: returns at once when no terminal can answer" {
    command -v setsid >/dev/null || skip "setsid is not installed"
    # setsid gives the shell no controlling terminal, so /dev/tty cannot open
    # shellcheck disable=SC2016  # $1 expands in the inner shell
    run setsid bash -c 'set -euo pipefail; source "$1/ui.sh"; NONINTERACTIVE=0 ui_press_enter; echo reached' _ "$LIB" < /dev/null
    [[ "$status" -eq 0 && "$output" == *reached* ]] || { echo "status $status: $output"; return 1; }
}

@test "ui_press_enter: NONINTERACTIVE=1 skips the pause" {
    # shellcheck disable=SC2016  # $1 expands in the inner shell
    run bash -c 'set -euo pipefail; source "$1/ui.sh"; NONINTERACTIVE=1 ui_press_enter; echo reached' _ "$LIB" < /dev/null
    [[ "$status" -eq 0 && "$output" == *reached* ]] || { echo "status $status: $output"; return 1; }
}

@test "ui_choose_many: without gum, numbers or all pick, an empty answer picks nothing" {
    # shellcheck disable=SC2016  # $1 expands in the inner shell
    local script='source "$1/ui.sh"; has_gum() { return 1; }; ui_choose_many "Pick:" a b c 2>/dev/null'
    run bash -c "$script" _ "$LIB" <<< "1 3"
    [[ "$output" == $'a\nc' ]] || { echo "1 3: $output"; return 1; }
    run bash -c "$script" _ "$LIB" <<< "all"
    [[ "$output" == $'a\nb\nc' ]] || { echo "all: $output"; return 1; }
    run bash -c "$script" _ "$LIB" <<< ""
    [[ -z "$output" ]] || { echo "empty: $output"; return 1; }
    run bash -c "$script" _ "$LIB" <<< "9"
    [[ -z "$output" ]] || { echo "9: $output"; return 1; }
}
