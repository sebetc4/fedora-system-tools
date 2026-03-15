#!/bin/bash
# =============================================================================
# UPDATE-DEFINITIONS - ClamAV virus definition updater
# =============================================================================
# Ensures freshclam configuration has the correct database mirror
# and update logging settings.
#
# Module: clamav
# Requires: none
# Version: 0.1.0
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

if ! grep -q '^DatabaseMirror' /etc/freshclam.conf; then
    echo "DatabaseMirror missing, adding configuration..."
    # shellcheck disable=SC2002  # cat needed: sudo doesn't affect redirects (SC2024)
    cat "$SCRIPT_DIR/../../templates/freshclam-config.conf" | sudo tee -a /etc/freshclam.conf > /dev/null
    echo "Configuration added!"
fi
