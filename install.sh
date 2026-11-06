#!/bin/bash
# =============================================================================
# INSTALL - Bootstrap installer for Fedora System Tools
# =============================================================================
# Downloads the latest release and installs to /opt/fedora-system-tools/.
# Creates /usr/local/bin/system-tools symlink for easy access.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/sebetc4/fedora-system-tools/main/install.sh | bash
#   curl -sSL ... | bash -s -- --all    # Bootstrap + install all modules
#
# Requires: bash 4+, curl, tar, sudo
# Version: 0.2.0
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly GITHUB_REPO="sebetc4/fedora-system-tools"
readonly INSTALL_DIR="/opt/fedora-system-tools"
readonly SYMLINK_PATH="/usr/local/bin/system-tools"
readonly API_URL="https://api.github.com/repos/${GITHUB_REPO}/releases"

# Download folder, removed on exit
TMP_DIR=""
trap 'rm -rf "$TMP_DIR"' EXIT

# Colors (disabled if not a terminal)
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_NC='\033[0m'

if [[ ! -t 1 ]]; then
    C_RED='' C_GREEN='' C_CYAN='' C_BOLD='' C_NC=''
fi

error()   { echo -e "${C_RED}Error: $1${C_NC}" >&2; }
success() { echo -e "${C_GREEN}✓ $1${C_NC}"; }
info()    { echo -e "${C_CYAN}$1${C_NC}"; }

# =============================================================================
# PREREQUISITES
# =============================================================================

check_prerequisites() {
    local missing=()

    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        error "Bash 4+ required (found ${BASH_VERSION})"
        exit 1
    fi

    for cmd in curl tar sudo; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required commands: ${missing[*]}"
        echo "Install them with: sudo dnf install ${missing[*]}" >&2
        exit 1
    fi
}

# =============================================================================
# VERSION DETECTION
# =============================================================================

# Print the newest project release tag (vX.Y.Z) of a GitHub releases list read
# on stdin, without jq. Module tags (clamav-v0.2.0) and pre-releases
# (v1.0.0-rc1) are skipped: releases/latest may be either. setup.sh holds the
# same function, which tests/unit/install.bats keeps identical.
latest_project_tag() {
    grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -V | tail -n 1 | grep .
}

# Download a release's tarball into a folder and check that it reads as an
# archive, before anything installed is touched. setup.sh holds the same
# function, which tests/unit/install.bats keeps identical.
# Args: tag dir
# Output: the tarball's path
download_release() {
    local tag="$1" dir="$2"
    local tarball="fedora-system-tools-${tag#v}.tar.gz"
    curl -fsSL -o "$dir/$tarball" "https://github.com/${GITHUB_REPO}/releases/download/${tag}/${tarball}" \
        || return 1
    tar -tzf "$dir/$tarball" > /dev/null || return 1
    echo "$dir/$tarball"
}

get_latest_version() {
    local response
    response=$(curl -fsSL "${API_URL}?per_page=100" 2>/dev/null) || {
        error "Failed to query GitHub API"
        exit 1
    }

    local tag
    tag=$(latest_project_tag <<< "$response") || true

    if [[ -z "$tag" ]]; then
        error "Could not determine latest release from GitHub"
        exit 1
    fi

    echo "$tag"
}

# =============================================================================
# DOWNLOAD & INSTALL
# =============================================================================

download_and_install() {
    local tag="$1"
    local version="${tag#v}"
    local tarball

    TMP_DIR=$(mktemp -d)
    info "Downloading release ${tag}..."
    if ! tarball=$(download_release "$tag" "$TMP_DIR"); then
        error "Failed to download release ${tag}"
        exit 1
    fi

    info "Installing to ${INSTALL_DIR}..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo tar xzf "$tarball" -C "$INSTALL_DIR" --strip-components=1

    # --- Store installed version ---
    echo "$version" | sudo tee "${INSTALL_DIR}/.version" > /dev/null

    # --- Create symlink ---
    sudo ln -sf "${INSTALL_DIR}/setup.sh" "$SYMLINK_PATH"
    sudo chmod +x "${INSTALL_DIR}/setup.sh"

    # --- Install shared library ---
    info "Installing shared library..."
    sudo "${INSTALL_DIR}/lib/install.sh"

    success "Fedora System Tools v${version} installed"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    echo ""
    echo -e "${C_BOLD}${C_CYAN}Fedora System Tools — Remote Installer${C_NC}"
    echo ""

    check_prerequisites

    # --- Install, unless already installed ---
    if [[ -f "${INSTALL_DIR}/.version" ]]; then
        info "Already installed: v$(cat "${INSTALL_DIR}/.version")"
        info "Use 'system-tools --self-update' to update"
        echo ""
    else
        local tag
        tag=$(get_latest_version)
        info "Latest release: ${tag}"

        download_and_install "$tag"

        echo ""
        echo -e "${C_BOLD}Next steps:${C_NC}"
        echo "  system-tools               # Interactive menu"
        echo "  system-tools --install X   # Install a module"
        echo "  system-tools --list        # List installed modules"
        echo "  sudo ${INSTALL_DIR}/uninstall.sh   # Remove everything"
        echo ""
    fi

    # --- Forward arguments to setup.sh ---
    if [[ $# -gt 0 ]]; then
        info "Running: system-tools $*"
        echo ""
        "$SYMLINK_PATH" "$@"
    fi
}

main "$@"
