#!/bin/bash
# =============================================================================
# CHECK-NOTIFY-DEPENDENCIES - Notification dependencies checker
# =============================================================================
# Checks and installs dependencies for the notification system:
#   - jq (JSON parsing)
#   - notify-send (libnotify)
#   - systemd user session
#   - DBus session
#   - journalctl
#
# Module: notifications
# Requires: none (standalone utility)
# Version: 0.1.0
#
# Usage:
#   ./check-notify-dependencies.sh
# =============================================================================

set -euo pipefail

echo "=== Notification System Dependencies Check (Fedora) ==="

# --------------------------------------------------
# jq (JSON parsing)
# --------------------------------------------------
if ! command -v jq &>/dev/null; then
    read -r -p "jq is missing. Install it? [y/N] " confirm_jq
    if [[ "${confirm_jq,,}" == "y" ]]; then
        sudo dnf install -y jq
    else
        echo "⚠️ jq not installed — notification system requires it"
    fi
else
    echo "✅ jq installed ($(jq --version))"
fi

# --------------------------------------------------
# notify-send (libnotify)
# --------------------------------------------------
if ! command -v notify-send &>/dev/null; then
    read -r -p "libnotify (notify-send) is missing. Install it? [y/N] " confirm_libnotify
    if [[ "${confirm_libnotify,,}" == "y" ]]; then
        sudo dnf install -y libnotify
    else
        echo "⚠️ libnotify not installed — notifications won't work"
    fi
else
    echo "✅ notify-send installed"
fi

# --------------------------------------------------
# systemd user session
# --------------------------------------------------
if systemctl --user list-units &>/dev/null; then
    echo "✅ systemd user instance available"
else
    echo "⚠️ systemd user instance not available (non-graphical session?)"
fi

# --------------------------------------------------
# DBus session (required for notifications)
# --------------------------------------------------
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    echo "⚠️ DBus session not detected – notify-send may not work"
else
    echo "✅ DBus session available"
fi

# --------------------------------------------------
# journalctl
# --------------------------------------------------
if command -v journalctl &>/dev/null; then
    echo "✅ journalctl available"
else
    echo "❌ journalctl missing (systemd required)"
fi

echo "=== Dependency check completed ==="
