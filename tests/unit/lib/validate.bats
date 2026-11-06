#!/usr/bin/env bats
# =============================================================================
# VALIDATE.BATS - Unit tests for lib/validate.sh
# =============================================================================
# Covers the config validators and their error accumulator, which every
# backup script runs before touching a disk.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/validate.sh"
    validation_reset
}

# Assert that the accumulator holds exactly the given errors, in order
assert_errors() {
    local expected actual
    expected=$(printf '%s\n' "$@")
    actual=$(printf '%s\n' "${_VALIDATION_ERRORS[@]}")
    [[ $# -eq 0 ]] && expected=$'\n'
    [[ ${#_VALIDATION_ERRORS[@]} -eq 0 ]] && actual=$'\n'
    if [[ "$actual" != "$expected" ]]; then
        printf 'expected errors:\n%s\n--- got:\n%s\n' "$expected" "$actual"
        return 1
    fi
}

@test "validate_required: empty fails, anything else passes" {
    validate_required backup.mount ""
    validate_required backup.dest "/mnt"
    assert_errors "backup.mount is required"
}

@test "validate_boolean: true and false pass, empty is left to validate_required" {
    validate_boolean a true
    validate_boolean b false
    validate_boolean c ""
    validate_boolean d yes
    assert_errors "d must be 'true' or 'false' (got: 'yes')"
}

@test "validate_integer: digits pass, a sign, a decimal or text fail" {
    validate_integer a 0
    validate_integer b 30
    validate_integer c -1
    validate_integer d 1.5
    validate_integer e ten
    assert_errors "c must be a number (got: '-1')" "d must be a number (got: '1.5')" "e must be a number (got: 'ten')"
}

@test "validate_path: absolute passes, relative fails" {
    validate_path a /mnt/backup
    validate_path b mnt/backup
    validate_path c "./backup"
    assert_errors "b must be an absolute path starting with / (got: 'mnt/backup')" "c must be an absolute path starting with / (got: './backup')"
}

@test "validate_pattern: the pattern is a regex, the hint replaces the default message" {
    validate_pattern host "my-vps" '^[a-z0-9.-]+$'
    validate_pattern host "bad host" '^[a-z0-9.-]+$' "must be a hostname"
    assert_errors "host must be a hostname (got: 'bad host')"
}

@test "validate_mount: an unmounted path fails, empty is left to validate_required" {
    validate_mount a ""
    validate_mount b "$BATS_TEST_TMPDIR"
    assert_errors "b is not a mounted filesystem: $BATS_TEST_TMPDIR — is the drive plugged in and mounted?"
}

@test "validation_check: no error returns 0, errors exit 1 listing each with the config" {
    run validation_check "config.yml"
    [[ "$status" -eq 0 ]] || { echo "no error: status $status"; return 1; }
    validate_required a ""
    validate_integer b x
    run validation_check "config.yml"
    [[ "$status" -eq 1 && "$output" == *"a is required"* && "$output" == *"b must be a number"* && "$output" == *"Config: config.yml"* ]] \
        || { echo "got '$output' (status $status)"; return 1; }
}

@test "validation_reset: a new pass starts empty" {
    validate_required a ""
    validation_reset
    assert_errors
}
