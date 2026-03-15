#!/bin/bash
# =============================================================================
# INSTALL - ClamAV package installation
# =============================================================================
# Installs ClamAV packages, sets up log directories, SELinux contexts,
# and enables core ClamAV services on Fedora.
#
# Module: clamav
# Requires: none
# Version: 0.1.0
# =============================================================================

set -euo pipefail

echo "=== Installing ClamAV (Fedora) ==="

# --------------------------------------------------
# Packages
# --------------------------------------------------
dnf install -y clamav clamav-update clamd clamtk

# --------------------------------------------------
# Logs directory
# --------------------------------------------------
# ClamAV on Fedora uses user 'clamscan' and group 'virusgroup'
mkdir -p /var/log/clamav

# Detect ClamAV user and group (created by package installation)
CLAM_USER="clamscan"
CLAM_GROUP="virusgroup"

# Verify they exist (should be created by the ClamAV packages)
if ! id "$CLAM_USER" &>/dev/null; then
    echo "Warning: User $CLAM_USER not found, using root"
    CLAM_USER="root"
fi

if ! getent group "$CLAM_GROUP" &>/dev/null; then
    echo "Warning: Group $CLAM_GROUP not found"
    if id "$CLAM_USER" &>/dev/null; then
        CLAM_GROUP=$(id -gn "$CLAM_USER")
    else
        CLAM_GROUP="root"
    fi
fi

chown "$CLAM_USER:$CLAM_GROUP" /var/log/clamav
chmod 755 /var/log/clamav

# SELinux context
restorecon -Rv /var/log/clamav

# --------------------------------------------------
# Enable services
# --------------------------------------------------
systemctl enable --now clamav-freshclam.service
systemctl enable --now clamd@scan.service

# --------------------------------------------------
# Status
# --------------------------------------------------
systemctl --no-pager status clamav-freshclam.service
systemctl --no-pager status clamd@scan.service

echo "✅ ClamAV installed and configured"
