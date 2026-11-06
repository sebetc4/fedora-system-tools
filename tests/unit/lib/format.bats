#!/usr/bin/env bats
# =============================================================================
# FORMAT.BATS - Unit tests for lib/format.sh
# =============================================================================
# Covers format_size, format_date and truncate_name, which the quarantine
# and torrent listings print.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/format.sh"
}

# Assert that <function> <args...> succeeds and prints <expected>, the last argument
assert_prints() {
    local expected="${!#}"
    run "${@:1:$#-1}"
    if [[ "$status" -ne 0 || "$output" != "$expected" ]]; then
        echo "${*:1:$#-1}: expected '$expected', got '$output' (status $status)"
        return 1
    fi
}

@test "format_size: below 1 KB, bytes" {
    assert_prints format_size 0 "0 B"
    assert_prints format_size 1023 "1023 B"
}

@test "format_size: each unit starts at its exact size" {
    assert_prints format_size 1024 "1.0 KB"
    assert_prints format_size 1048576 "1.0 MB"
    assert_prints format_size 1073741824 "1.0 GB"
}

@test "format_size: one decimal" {
    assert_prints format_size 1536 "1.5 KB"
    assert_prints format_size 5242880 "5.0 MB"
    assert_prints format_size 3221225472 "3.0 GB"
}

@test "format_date: a timestamp prints as its day, an invalid one as ?" {
    TZ=UTC assert_prints format_date 1700000000 "2023-11-14"
    assert_prints format_date not-a-date "?"
}

@test "truncate_name: a name over the limit ends with ... at the limit" {
    assert_prints truncate_name "abcdefghij" 8 "abcde..."
    assert_prints truncate_name "abcdefgh" 8 "abcdefgh"
}
