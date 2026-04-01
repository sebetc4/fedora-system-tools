#!/bin/bash
# =============================================================================
# LIB INSTALL - Shared library & Gum installation
# =============================================================================
# Installs the shared bash library to /usr/local/lib/system-scripts/ and
# optionally installs Gum (terminal UI toolkit by Charm).
#
# Module: lib
# Requires: core (local source, not yet installed)
# Version: 0.1.1
#
# Usage:
#   sudo ./lib/install.sh          # Install lib + gum
#   sudo ./lib/install.sh --no-gum # Install lib only
# =============================================================================

set -euo pipefail

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
install -m 644 "$LIB_DIR"/backup.sh "$INSTALL_DIR/"
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
# Install Gum
# ===================
if [[ "$INSTALL_GUM" == true ]]; then
    if command -v gum &>/dev/null; then
        success "Gum already installed: $(gum --version 2>/dev/null || echo 'unknown version')"
    else
        install_gum_confirmed=false
        echo -e "${C_YELLOW}Gum (terminal UI toolkit) is not installed.${C_NC}"
        echo "  Gum provides interactive menus. Without it, scripts use bash fallback mode."
        read -r -p "Install gum? [y/N] " confirm_gum
        [[ "${confirm_gum,,}" == "y" ]] && install_gum_confirmed=true

        if [[ "$install_gum_confirmed" == true ]]; then
            info "Installing Gum..."

            # Try dnf first (Fedora/RHEL), then apt (Debian/Ubuntu), then binary
            if command -v dnf &>/dev/null; then
                # Charm repo for Fedora
                if ! dnf repolist --enabled 2>/dev/null | grep -q charm; then
                    rpm --import https://repo.charm.sh/yum/gpg.key 2>/dev/null || true
                    cat > /etc/yum.repos.d/charm.repo << 'EOF'
[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key
EOF
                fi
                dnf install -y gum

            elif command -v apt-get &>/dev/null; then
                mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list
                apt-get update -qq && apt-get install -y gum

            else
                warn "Cannot auto-install Gum (no supported package manager)"
                echo "Install manually: https://github.com/charmbracelet/gum#installation"
                echo "Scripts will work without Gum (bash fallback mode)."
            fi

            # Verify installation
            if command -v gum &>/dev/null; then
                success "Gum installed: $(gum --version 2>/dev/null || echo 'ok')"
            fi
        else
            info "Skipping Gum — scripts will use bash fallback mode."
        fi
    fi
else
    echo "Skipping Gum installation (--no-gum)"
    if ! command -v gum &>/dev/null; then
        echo "Note: Scripts will use bash fallback mode without Gum."
    fi
fi

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
