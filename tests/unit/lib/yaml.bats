#!/usr/bin/env bats
# =============================================================================
# YAML.BATS - Unit tests for lib/yaml.sh
# =============================================================================
# Covers the yq readers the backup configs go through, on a config written
# in the test's temporary directory. Needs yq.
#
# Run: make test
# =============================================================================

setup() {
    source "$BATS_TEST_DIRNAME/../../../lib/yaml.sh"
    YAML_FILE="$BATS_TEST_TMPDIR/config.yml"
    cat > "$YAML_FILE" <<'YAML'
backup:
  mount: /mnt/backup
  enabled: false
  empty: ""
  nothing: null
exclude: []
directories:
  - /home
  - null
  - "/srv/with space"
paths:
  - name: home
    exclusions: [".cache", "Downloads"]
  - name: etc
YAML
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

@test "parse_yaml: a value, false kept as text" {
    assert_prints parse_yaml backup.mount "/mnt/backup"
    assert_prints parse_yaml backup.enabled "false"
}

@test "parse_yaml: missing, null and empty values print nothing" {
    assert_prints parse_yaml backup.missing ""
    assert_prints parse_yaml backup.nothing ""
    assert_prints parse_yaml backup.empty ""
}

@test "parse_yaml: a file passed as argument wins over YAML_FILE" {
    printf 'backup:\n  mount: /other\n' > "$BATS_TEST_TMPDIR/other.yml"
    assert_prints parse_yaml backup.mount "$BATS_TEST_TMPDIR/other.yml" "/other"
}

@test "parse_yaml: a missing file stops with a message" {
    YAML_FILE="$BATS_TEST_TMPDIR/absent.yml" run parse_yaml backup.mount
    [[ "$status" -ne 0 && "$output" == *"YAML file not found"* ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "parse_yaml_array: one item per line, nulls skipped" {
    assert_prints parse_yaml_array directories $'/home\n/srv/with space'
}

@test "parse_yaml_array: an empty or missing list prints nothing and returns 1" {
    run parse_yaml_array exclude
    [[ "$status" -eq 1 && -z "$output" ]] || { echo "empty list: got '$output' (status $status)"; return 1; }
    run parse_yaml_array missing
    [[ "$status" -eq 1 && -z "$output" ]] || { echo "missing list: got '$output' (status $status)"; return 1; }
}

@test "parse_yaml_count: a list's length, 0 when missing" {
    assert_prints parse_yaml_count paths "2"
    assert_prints parse_yaml_count missing "0"
}

@test "parse_yaml_index: a field of a list element, empty when missing" {
    assert_prints parse_yaml_index paths 1 name "etc"
    assert_prints parse_yaml_index paths 1 exclusions_missing ""
}

@test "parse_yaml_index_array: an array field of a list element" {
    assert_prints parse_yaml_index_array paths 0 exclusions $'.cache\nDownloads'
}
