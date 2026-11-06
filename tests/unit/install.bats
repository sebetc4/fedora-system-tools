#!/usr/bin/env bats
# =============================================================================
# INSTALL.BATS - Unit tests for the release download of install.sh
# =============================================================================
# Covers latest_project_tag, which install.sh and setup.sh --self-update both
# use to pick the release to download from GitHub's list of releases, and
# download_release, which both use to fetch it, with curl stubbed. install.sh
# cannot be sourced whole, so each function is read out of the file.
#
# Run: make test
# =============================================================================

readonly REPO_ROOT="$BATS_TEST_DIRNAME/../.."

# Print the definition of <function> held in <file>
function_of() {
    sed -n "/^$1() {\$/,/^}\$/p" "$2"
}

setup() {
    # shellcheck source=/dev/null
    source <(function_of latest_project_tag "$REPO_ROOT/install.sh")
    # shellcheck source=/dev/null
    source <(function_of download_release "$REPO_ROOT/install.sh")
    # shellcheck disable=SC2034  # read by download_release
    GITHUB_REPO="owner/repo"
}

# Stub curl: write <file> where -o says, or fail when <file> is "fail"
stub_curl() {
    export CURL_GIVES="$1"
    curl() {
        local out=""
        while (( $# > 0 )); do
            [[ "$1" == "-o" ]] && out="$2"
            shift
        done
        [[ "$CURL_GIVES" != "fail" ]] || return 22
        cp "$CURL_GIVES" "$out"
    }
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

@test "latest_project_tag, download_release: setup.sh carries the same functions as install.sh" {
    local name in_install in_setup
    for name in latest_project_tag download_release; do
        in_install=$(function_of "$name" "$REPO_ROOT/install.sh")
        in_setup=$(function_of "$name" "$REPO_ROOT/setup.sh")
        [[ -n "$in_install" && "$in_install" == "$in_setup" ]] || { echo "the two copies of $name differ"; return 1; }
    done
}

@test "download_release: a release archive comes back as its path" {
    mkdir -p "$BATS_TEST_TMPDIR/src/fedora-system-tools-0.7.0"
    tar -czf "$BATS_TEST_TMPDIR/release.tar.gz" -C "$BATS_TEST_TMPDIR/src" .
    stub_curl "$BATS_TEST_TMPDIR/release.tar.gz"
    mkdir "$BATS_TEST_TMPDIR/dl"
    run download_release v0.7.0 "$BATS_TEST_TMPDIR/dl"
    [[ "$status" -eq 0 && "$output" == "$BATS_TEST_TMPDIR/dl/fedora-system-tools-0.7.0.tar.gz" ]] \
        || { echo "got '$output' (status $status)"; return 1; }
}

@test "download_release: an answer that is no archive, such as an error page, fails" {
    printf '<html>Not Found</html>\n' > "$BATS_TEST_TMPDIR/page.html"
    stub_curl "$BATS_TEST_TMPDIR/page.html"
    mkdir "$BATS_TEST_TMPDIR/dl"
    run download_release v0.7.0 "$BATS_TEST_TMPDIR/dl"
    [[ "$status" -ne 0 ]] || { echo "accepted an error page: $output"; return 1; }
}

@test "download_release: a failed download fails" {
    stub_curl fail
    mkdir "$BATS_TEST_TMPDIR/dl"
    run download_release v0.7.0 "$BATS_TEST_TMPDIR/dl"
    [[ "$status" -ne 0 ]] || { echo "a failed download succeeded: $output"; return 1; }
}
