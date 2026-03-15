#!/bin/bash
# =============================================================================
# TORRENT INSTALL - Torrent module installation
# =============================================================================
# Installs the VPN + qBittorrent container stack:
#   - torrent           — Main CLI (start, stop, status, list, move)
#   - torrent-list      — Download listing helper
#   - torrent-move      — Download move/export helper
#   - torrent-container — Container setup, config, and lifecycle
#
# Module: torrent
# Requires: core, registry, config
# Version: 0.1.0
#
# Usage:
#   sudo ./modules/torrent/install.sh
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: Installation failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly MODULE_YML="$SCRIPT_DIR/module.yml"
readonly MODULE_NAME="torrent"
if command -v yq &>/dev/null && [[ -f "$MODULE_YML" ]]; then
    MODULE_VERSION="$(yq -r '.version' "$MODULE_YML")"
else
    MODULE_VERSION="0.1.0"
fi
readonly MODULE_VERSION

# ===================
# Check lib is installed
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
if [[ ! -f "$LIB_DIR/core.sh" ]]; then
    echo "ERROR: system-scripts library not found in $LIB_DIR"
    echo "Install it first: make install-lib"
    exit 1
fi
source "$LIB_DIR/core.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/ui.sh"

check_root

# ===================
# Detect calling user (for paths.conf generation)
# ===================
CURRENT_USER="${SUDO_USER:-$USER}"
readonly CURRENT_USER

# ===================
# Check system dependencies
# ===================
info "Checking system dependencies..."
missing_deps=()
for dep in podman curl; do
    command -v "$dep" &>/dev/null || missing_deps+=("$dep")
done

if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo -e "${C_YELLOW}Missing system packages: ${missing_deps[*]}${C_NC}"
    read -r -p "Install these packages? [y/N] " confirm_deps
    if [[ "${confirm_deps,,}" == "y" ]]; then
        dnf install -y "${missing_deps[@]}"
    else
        warn "Skipping package installation — module may not work correctly"
    fi
fi

# gum (optional, for interactive UI)
if ! command -v gum &>/dev/null; then
    read -r -p "Install gum (interactive UI toolkit)? [y/N] " confirm_gum
    if [[ "${confirm_gum,,}" == "y" ]]; then
        dnf install -y gum || warn "gum not available — fallback UI will be used"
    else
        info "Skipping Gum — scripts will use bash fallback mode."
    fi
fi

# ===================
# Create torrent downloads directory
# ===================
source "$LIB_DIR/config.sh"
load_config
mkdir -p "$DOWNLOAD_DIR/torrents"
chown "$CURRENT_USER:$CURRENT_USER" "$DOWNLOAD_DIR/torrents"
info "Torrent downloads directory: $DOWNLOAD_DIR/torrents"

# ===================
# Install binaries
# ===================
info "Installing $MODULE_NAME v$MODULE_VERSION..."

install -m 755 "$SCRIPT_DIR/scripts/torrent.sh"           /usr/local/bin/torrent
install -m 755 "$SCRIPT_DIR/scripts/torrent-list.sh"      /usr/local/bin/torrent-list
install -m 755 "$SCRIPT_DIR/scripts/torrent-move.sh"      /usr/local/bin/torrent-move
install -m 755 "$SCRIPT_DIR/scripts/torrent-container.sh" /usr/local/bin/torrent-container

# ===================
# Register module
# ===================
registry_set "$MODULE_NAME" "$MODULE_VERSION"

# ===================
# Container setup
# ===================
info "Launching container setup..."
echo ""
sudo -u "$CURRENT_USER" torrent-container install

ui_banner "$MODULE_NAME v$MODULE_VERSION installed" \
    "" \
    "Detected directories:" \
    "  Torrent downloads: $DOWNLOAD_DIR/torrents" \
    "  Export destination: $DOWNLOAD_DIR" \
    "" \
    "Usage:" \
    "  torrent start    — Start VPN + qBittorrent" \
    "  torrent stop     — Stop everything" \
    "  torrent status   — Show stack status" \
    "" \
    "  torrent list     — List downloaded files" \
    "  torrent move <#> — Move file to export dir" \
    "  torrent update   — Pull latest container images" \
    "" \
    "  torrent --help   — More options"

ui_press_enter
