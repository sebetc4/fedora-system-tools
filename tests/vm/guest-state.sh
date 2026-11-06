#!/bin/bash
# =============================================================================
# GUEST-STATE - Print a test VM's state for the harness's comparison
# =============================================================================
# Runs inside a test VM, as root. Prints one tab-separated line per entry:
#   f|d|l <path>      a file, directory or symlink under the scanned roots
#   h <sha256> <path> the content of a regular file under /etc or ~/.config
#   u|g <name>        a user or group account
# The harness compares two outputs to find what an uninstall left behind.
#
# Module: tests
# Requires: none
# Version: 0.1.1
#
# Usage:
#   sudo bash guest-state.sh <user>
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: guest-state failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
CHECKOUT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly CHECKOUT_DIR

readonly TARGET_USER="${1:?Usage: guest-state.sh <user>}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
readonly TARGET_HOME

# ===================
# Scanned roots and volatile paths
# ===================
readonly ROOTS=(/etc /opt /srv /usr/local /var /root "$TARGET_HOME")

# Paths that change on their own, or belong to the package manager and the
# session rather than to a module
readonly EXCLUDES=(
    "$CHECKOUT_DIR"
    "$TARGET_HOME/.cache"
    "$TARGET_HOME/.local/state"
    "$TARGET_HOME/.bash_history"
    "$TARGET_HOME/.lesshst"
    "$TARGET_HOME/.ssh"
    "$TARGET_HOME/.sudo_as_admin_successful"
    "$TARGET_HOME/.viminfo"
    /etc/cups/subscriptions.conf
    /etc/cups/subscriptions.conf.O
    /etc/ld.so.cache
    /etc/selinux
    /etc/pki/ca-trust/extracted
    /etc/udev/hwdb.bin
    /var/cache
    /var/tmp
    /var/spool
    /var/log/journal
    /var/lib/dnf
    /var/lib/rpm
    /var/lib/rpm-state
    /var/lib/selinux
    /var/lib/systemd
    /var/lib/sss
    /var/lib/NetworkManager
    /var/lib/PackageKit
    /var/lib/flatpak
    /var/lib/fwupd
    /var/lib/logrotate
    /var/lib/chrony
    /var/lib/upower
)

# ===================
# Paths
# ===================
prune=()
for path in "${EXCLUDES[@]}"; do
    prune+=(-path "$path" -o)
done

find "${ROOTS[@]}" -xdev \( "${prune[@]}" -false \) -prune -o \
    \( -type f -printf 'f\t%p\n' \) -o \
    \( -type d -printf 'd\t%p\n' \) -o \
    \( -type l -printf 'l\t%p\n' \) 2>/dev/null || true

# ===================
# Contents
# ===================
# The registries are hashed without their `installed=` dates and blank lines,
# which every reinstall of the library rewrites
readonly REGISTRIES=(/etc/system-scripts/registry "$TARGET_HOME/.config/system-scripts/registry")

find /etc "$TARGET_HOME/.config" -xdev \( "${prune[@]}" -false \) -prune -o \
    -type f -print0 2>/dev/null \
    | xargs -0 -r sha256sum 2>/dev/null \
    | awk -v r1="${REGISTRIES[0]}" -v r2="${REGISTRIES[1]}" '
        { sum = $1; sub(/^[^ ]+  /, "") }
        $0 != r1 && $0 != r2 { printf "h\t%s\t%s\n", sum, $0 }' || true

for registry in "${REGISTRIES[@]}"; do
    if [[ -f "$registry" ]]; then
        sum=$({ grep -vE '^(installed=|[[:space:]]*$)' "$registry" || true; } | sha256sum | cut -d' ' -f1)
        printf 'h\t%s\t%s\n' "$sum" "$registry"
    fi
done

# ===================
# Accounts
# ===================
getent passwd | cut -d: -f1 | sed 's/^/u\t/'
getent group | cut -d: -f1 | sed 's/^/g\t/'
