#!/bin/bash
# =============================================================================
# VERSION-DETECTION.SH - Fedora release and kernel version detection
# =============================================================================
# Detects the current Fedora release, lists available kernel versions from the
# fedpkg git history, and presents an interactive selection via ui_filter().
#
# Module: build-kernel
# Requires: core, log, ui
# Version: 0.1.0
# =============================================================================

[[ -n "${_BUILD_KERNEL_VERSION_DETECTION_LOADED:-}" ]] && return 0
readonly _BUILD_KERNEL_VERSION_DETECTION_LOADED=1

# =============================================================================
# FEDORA RELEASE
# =============================================================================

detect_fedora_release() {
    if [[ ! -f /etc/fedora-release ]]; then
        log_error "This system is not Fedora"
        return 1
    fi
    local fedora_version
    fedora_version=$(rpm -E %fedora)
    echo "f${fedora_version}"
}

# =============================================================================
# VERSION LISTING
# =============================================================================

# List available kernel versions from the fedpkg git repository.
# Args: $1 = repo_dir, $2 = max versions per major (default: 3)
list_available_kernel_versions() {
    local repo_dir="$1"
    local max_per_major="${2:-3}"

    if ! cd "$repo_dir" 2>/dev/null; then
        log_error "Cannot access repository: $repo_dir"
        return 1
    fi

    local all_versions
    all_versions=$(git log --oneline --all 2>/dev/null \
        | grep -oP 'kernel-\K[0-9]+\.[0-9]+\.[0-9]+-[0-9]+' \
        | sort -Vru)

    if [[ -z "$all_versions" ]]; then
        log_error "No kernel versions found in git repository"
        return 1
    fi

    local major_versions
    if [[ -n "${SUPPORTED_KERNEL_MAJORS:-}" ]]; then
        major_versions=$(echo "$SUPPORTED_KERNEL_MAJORS" | tr ' ' '\n' | sort -Vru)
    else
        major_versions=$(echo "$all_versions" | cut -d. -f1-2 | sort -Vru)
    fi

    local selected_versions=""
    local major
    for major in $major_versions; do
        local versions
        versions=$(echo "$all_versions" | grep "^${major}\." | head -n "$max_per_major")
        selected_versions="${selected_versions}${versions}"$'\n'
    done

    echo "$selected_versions" | grep -v '^$'
}

# =============================================================================
# INTERACTIVE SELECTION
# =============================================================================

# Present an interactive version picker.
# Args: $1 = newline-separated list of versions
# Prints the selected version to stdout.
select_kernel_version() {
    local versions="$1"

    local -a version_list
    mapfile -t version_list <<< "$versions"

    local selected
    selected=$(ui_choose --header "Select kernel version to build" "${version_list[@]}")

    echo "$selected"
}

# =============================================================================
# COMMIT LOOKUP
# =============================================================================

# Find the git commit hash for a specific kernel version string.
# Args: $1 = repo_dir, $2 = version (e.g. 6.19.7-200)
find_commit_for_version() {
    local repo_dir="$1"
    local version="$2"

    if ! cd "$repo_dir" 2>/dev/null; then
        log_error "Cannot access repository: $repo_dir"
        return 1
    fi

    local commit
    commit=$(git log --oneline --all 2>/dev/null \
        | grep -F "kernel-${version}" \
        | head -n1 \
        | awk '{print $1}')

    if [[ -z "$commit" ]]; then
        log_error "Commit not found for kernel-${version}"
        return 1
    fi

    echo "$commit"
}
