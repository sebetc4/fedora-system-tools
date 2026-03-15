#!/bin/bash
# =============================================================================
# INSTALL-VPS - VPS backup install hook
# =============================================================================
# Handles VPS-specific setup that the submodule engine cannot:
#   - Logrotate (user-prefixed filename requires sudo tee)
#   - systemd user instance availability check
#   - SSH agent detection + guidance
#   - PATH check for ~/.local/bin
#
# The submodule engine handles: binary, systemd service/timer, config,
# log directory, notifications, and registry (via module.yml).
#
# Module: backup
# Requires: core
# Version: 0.1.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
BASE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly BASE_DIR

# Shared library
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# Resolve real user (running under sudo)
readonly REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
readonly REAL_HOME
readonly BIN_DIR="$REAL_HOME/.local/bin"

# ===================
# systemd user instance check
# ===================
local_uid=$(id -u "$REAL_USER")
if ! sudo -u "$REAL_USER" XDG_RUNTIME_DIR="/run/user/$local_uid" \
    systemctl --user list-units &>/dev/null 2>&1; then
    warn "systemd user instance not available for $REAL_USER"
    echo "  Ensure the user has a graphical/login session"
fi

# ===================
# Logrotate (user-prefixed filename)
# ===================
info "Configuring log rotation..."
LOGROTATE_FILE="/etc/logrotate.d/${REAL_USER}-backup-vps"
sed -e "s|__HOME__|$REAL_HOME|g" \
    -e "s|__USER__|$REAL_USER|g" \
    "$BASE_DIR/vps/logrotate/user-logs.tpl" > "$LOGROTATE_FILE"
chmod 644 "$LOGROTATE_FILE"
echo -e "${C_GREEN}✓ Log rotation configured${C_NC}"

# ===================
# PATH check
# ===================
if ! sudo -u "$REAL_USER" bash -lc "echo \$PATH" 2>/dev/null | grep -q "$BIN_DIR"; then
    warn "$BIN_DIR may not be in $REAL_USER's PATH"
    echo "  Add to ~/.bashrc: export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ===================
# SSH agent check
# ===================
info "Checking SSH agent..."

# Check SSH_AUTH_SOCK via the user's environment
local_ssh_sock=""
if [[ -S "/run/user/$local_uid/gcr/ssh" ]]; then
    local_ssh_sock="/run/user/$local_uid/gcr/ssh"
elif [[ -S "/run/user/$local_uid/keyring/ssh" ]]; then
    local_ssh_sock="/run/user/$local_uid/keyring/ssh"
fi

if [[ -n "$local_ssh_sock" ]]; then
    if sudo -u "$REAL_USER" SSH_AUTH_SOCK="$local_ssh_sock" ssh-add -l &>/dev/null; then
        echo -e "${C_GREEN}✓ SSH agent active with loaded keys${C_NC}"
    else
        warn "SSH agent active but no keys loaded"
        echo "  Load your key: ssh-add ~/.ssh/id_ed25519"
    fi

    if [[ "$local_ssh_sock" == *"gcr"* ]]; then
        echo -e "${C_GREEN}✓ gcr-ssh-agent detected${C_NC}"
        info "When SSH asks for your passphrase, accept the prompt"
        echo "  to save it. The systemd timer will then work unattended."
    elif [[ "$local_ssh_sock" == *"keyring"* ]]; then
        warn "SSH agent is GNOME Keyring (legacy)"
        echo "  The systemd timer uses gcr-ssh-agent (SSH_AUTH_SOCK=%t/gcr/ssh)"
        echo "  Update the service Environment if your system uses keyring instead."
    fi
else
    warn "No SSH agent detected"
    echo "  The systemd timer requires gcr-ssh-agent to handle SSH passphrases."
    echo "  Ensure gcr-ssh-agent is running and your key passphrase is saved."
fi

# ===================
# Summary
# ===================
echo ""
echo -e "${C_BOLD}==> VPS Backup${C_NC}"
echo ""
echo -e "${C_YELLOW}Next steps:${C_NC}"
echo "  1. Edit config:   nano $REAL_HOME/.config/backup/vps.yml"
echo "  2. Save SSH key:  ssh main-vps  (accept GNOME Keyring prompt)"
echo "  3. Test dry-run:  backup-vps --dry-run"
echo "  4. Test real:     backup-vps"
echo "  5. Check timer:   systemctl --user status backup-vps.timer"
echo ""
echo -e "${C_BLUE}Useful commands:${C_NC}"
echo "  Manual run:     systemctl --user start backup-vps.service"
echo "  Timer status:   systemctl --user list-timers | grep vps"
echo "  Service logs:   journalctl --user -u backup-vps -n 30"
echo "  Pull log:       cat $REAL_HOME/.local/log/backup-vps/backup-vps.log"
echo ""
