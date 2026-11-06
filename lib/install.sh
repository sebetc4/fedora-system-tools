#!/bin/bash
# =============================================================================
# LIB INSTALL - Shared library & dependencies installation
# =============================================================================
# Installs yq and Gum from Fedora's repositories, then the shared bash library
# to /usr/local/lib/system-scripts/. yq parses every module.yml; Gum drives
# the interactive menus, which fall back to plain bash without it.
#
# Module: lib
# Requires: core (local source, not yet installed)
# Version: 0.6.0
#
# Usage:
#   sudo ./lib/install.sh          # Install yq, gum and the lib
#   sudo ./lib/install.sh --no-gum # Install yq and the lib, without gum
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Library installation failed at line $LINENO" >&2; exit 1' ERR

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LIB_DIR
readonly INSTALL_DIR="/usr/local/lib/system-scripts"

# Source core.sh from the same directory (not yet installed, use local copy)
source "$LIB_DIR/core.sh"

# ===================
# Parse arguments
# ===================
INSTALL_GUM=true
for arg in "$@"; do
    case "$arg" in
        --no-gum) INSTALL_GUM=false ;;
    esac
done

# ===================
# Root check
# ===================
check_root "$@"

# ===================
# Install dependencies
# ===================
packages=(yq)
if [[ "$INSTALL_GUM" == true ]]; then
    packages+=(gum)
else
    info "Skipping Gum (--no-gum): menus will use the bash fallback."
fi

missing=()
for pkg in "${packages[@]}"; do
    command -v "$pkg" &>/dev/null || missing+=("$pkg")
done
if (( ${#missing[@]} > 0 )); then
    info "Installing ${missing[*]} from Fedora's repositories..."
    dnf install -y "${missing[@]}"
fi
success "yq: $(yq --version)"
if command -v gum &>/dev/null; then
    success "Gum: $(gum --version)"
fi
echo ""

# ===================
# Install shared library
# ===================
info "Installing shared library to $INSTALL_DIR..."

mkdir -p "$INSTALL_DIR"
install -m 644 "$LIB_DIR"/core.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/log.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/config.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/format.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/ui.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/yaml.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/validate.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/fs.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/registry.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/notify.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/submodule.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/paths.sh "$INSTALL_DIR/"
install -m 644 "$LIB_DIR"/color.sh "$INSTALL_DIR/"

echo ""
success "Shared library installed ($(find "$INSTALL_DIR" -maxdepth 1 -name '*.sh' | wc -l) files)"

lib_modules=$(find "$INSTALL_DIR" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' | sed 's/\.sh$//' | sort)
info "Lib version installed: ${LIB_VERSION}"
info "Lib modules installed:"
while IFS= read -r module_name; do
    echo "  - $module_name"
done <<< "$lib_modules"
echo ""

# ===================
# Generate paths.conf
# ===================
source "$INSTALL_DIR/paths.sh"
CURRENT_USER="${SUDO_USER:-$USER}"
mkdir -p /etc/system-scripts
if [[ ! -f /etc/system-scripts/paths.conf ]]; then
    info "Generating path configuration for user: $CURRENT_USER"
    generate_paths_conf "$CURRENT_USER" > /etc/system-scripts/paths.conf
    chmod 644 /etc/system-scripts/paths.conf
    success "Config: /etc/system-scripts/paths.conf"
else
    info "paths.conf already exists — skipping generation"
fi

# ===================
# Generate color.conf
# ===================
if [[ ! -f /etc/system-scripts/color.conf ]]; then
    info "Installing default color configuration..."
    install -m 644 "$LIB_DIR/../templates/color.conf.default" /etc/system-scripts/color.conf
    success "Config: /etc/system-scripts/color.conf"
else
    info "color.conf already exists — skipping generation"
fi

# ===================
# Register lib in registry
# ===================
source "$INSTALL_DIR/registry.sh"
registry_set "lib" "$LIB_VERSION"
success "Library registered (v${LIB_VERSION})"

# ===================
# Create system-tools symlink
# ===================
# If running from /opt/fedora-system-tools/ (remote install), create the
# system-tools command. Skip if running from a dev checkout (git clone).
REPO_DIR="$(cd "$LIB_DIR/.." && pwd)"
readonly SYSTEM_TOOLS_BIN="/usr/local/bin/system-tools"

if [[ "$REPO_DIR" == "/opt/fedora-system-tools" ]] && [[ -f "$REPO_DIR/setup.sh" ]]; then
    ln -sf "$REPO_DIR/setup.sh" "$SYSTEM_TOOLS_BIN"
    chmod +x "$REPO_DIR/setup.sh"
    success "Command: system-tools → ${REPO_DIR}/setup.sh"
fi

echo ""
success "Library installation complete."
echo "  Lib path: $INSTALL_DIR"
echo "  Gum:      $(command -v gum &>/dev/null && echo 'installed' || echo 'not installed (fallback mode)')"
if [[ -L "$SYSTEM_TOOLS_BIN" ]]; then
    echo "  Command:  system-tools"
fi
