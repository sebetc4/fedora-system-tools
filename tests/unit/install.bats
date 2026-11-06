#!/usr/bin/env bats
# =============================================================================
# INSTALL.BATS - Unit tests for the release detection of install.sh
# =============================================================================
# Covers latest_project_tag, which install.sh and setup.sh --self-update both
# use to pick the release to download from GitHub's list of releases. Neither
# script can be sourced whole, so the function is read out of each file.
#
# Run: make test
# =============================================================================

readonly REPO_ROOT="$BATS_TEST_DIRNAME/../.."

# Print the definition of latest_project_tag held in <file>
function_of() {
    sed -n '/^latest_project_tag() {$/,/^}$/p' "$1"
}

setup() {
    # shellcheck source=/dev/null
    source <(function_of "$REPO_ROOT/install.sh")
}

# Print a GitHub releases list holding the given tags, newest first
releases() {
    local tag sep=""
    echo "["
    for tag in "$@"; do
        printf '%s  {\n    "tag_name": "%s",\n    "name": "%s"\n  }\n' "$sep" "$tag" "$tag"
        sep=","
    done
    echo "]"
}

@test "latest_project_tag: a newer module release is skipped" {
    run latest_project_tag < <(releases clamav-v0.7.0 v0.6.0 v0.5.0)
    [[ "$status" -eq 0 && "$output" == "v0.6.0" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "latest_project_tag: a pre-release is skipped" {
    run latest_project_tag < <(releases v0.7.0-rc1 v0.6.0)
    [[ "$status" -eq 0 && "$output" == "v0.6.0" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "latest_project_tag: versions compare as numbers, whatever the list's order" {
    run latest_project_tag < <(releases v0.9.0 v0.10.0 v0.8.1)
    [[ "$status" -eq 0 && "$output" == "v0.10.0" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "latest_project_tag: a list without a project release prints nothing and fails" {
    run latest_project_tag < <(releases lib-v0.6.0 clamav-v0.2.0)
    [[ "$status" -ne 0 && -z "$output" ]] || { echo "got '$output' (status $status)"; return 1; }
}

@test "latest_project_tag: setup.sh carries the same function as install.sh" {
    local in_install in_setup
    in_install=$(function_of "$REPO_ROOT/install.sh")
    in_setup=$(function_of "$REPO_ROOT/setup.sh")
    [[ -n "$in_install" && "$in_install" == "$in_setup" ]] || { echo "the two copies differ"; return 1; }
}
