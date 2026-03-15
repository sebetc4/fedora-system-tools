#!/bin/bash
# =============================================================================
# NOTIFY.SH - Notification registration helpers
# =============================================================================
# Functions for modules to register/unregister their notification tags
# with the notify-daemon configuration files.
#
# This lib provides direct file manipulation — no dependency on
# notify-manage or the notifications module being installed.
#
# Usage: source "$LIB_DIR/notify.sh"
# =============================================================================

# Double-sourcing guard
[[ -n "${_LIB_NOTIFY_LOADED:-}" ]] && return 0
readonly _LIB_NOTIFY_LOADED=1

# =============================================================================
# CONFIGURATION
# =============================================================================

# Resolve target user home for notify-daemon config
# When running as root (install.sh), we need the real user's home
_notify_resolve_home() {
    if [[ -n "${SUDO_USER:-}" ]]; then
        eval echo "~${SUDO_USER}"
    else
        echo "$HOME"
    fi
}

# =============================================================================
# REGISTRATION
# =============================================================================

# Register a notification tag with optional icon and default level
#
# Usage: notify_register <tag> [icon] [level]
#
# - Creates ~/.config/notify-daemon/ if needed
# - Adds tag to services.conf (idempotent)
# - Adds tag=icon to icons.conf if icon provided (idempotent)
# - Adds tag=level to levels.conf if level provided and not already set
#   (preserves user customizations)
notify_register() {
    local tag="$1"
    local icon="${2:-}"
    local level="${3:-}"
    local target_home
    target_home="$(_notify_resolve_home)"
    local notify_dir="$target_home/.config/notify-daemon"
    local services_file="$notify_dir/services.conf"
    local icons_file="$notify_dir/icons.conf"
    local levels_file="$notify_dir/levels.conf"

    # Create directory if needed
    mkdir -p "$notify_dir"

    # --- services.conf ---
    if [[ -f "$services_file" ]]; then
        # File exists — add tag if not already present
        grep -qxF "$tag" "$services_file" 2>/dev/null || echo "$tag" >> "$services_file"
    else
        # File doesn't exist — create with header
        {
            echo "# Services monitored by notify-daemon (one per line)"
            echo "# Lines starting with # are ignored"
            echo "$tag"
        } > "$services_file"
    fi

    # --- icons.conf ---
    if [[ -n "$icon" ]]; then
        if [[ -f "$icons_file" ]]; then
            # File exists — add mapping if not already present
            grep -q "^${tag}=" "$icons_file" 2>/dev/null || echo "${tag}=${icon}" >> "$icons_file"
        else
            # File doesn't exist — create with header
            {
                echo "# Custom icons per service"
                echo "# Format: service_name=icon_name"
                echo "${tag}=${icon}"
            } > "$icons_file"
        fi
    fi

    # --- levels.conf (only if level provided AND not already set) ---
    if [[ -n "$level" ]]; then
        if [[ -f "$levels_file" ]]; then
            # Only add if no entry exists yet (preserve user customizations)
            grep -q "^${tag}=" "$levels_file" 2>/dev/null || echo "${tag}=${level}" >> "$levels_file"
        else
            # File doesn't exist — create with header and default
            {
                echo "# Notification level per tag"
                echo "# Levels: all | important | none"
                echo "# Managed via: notify-manage level"
                echo ""
                echo "default=all"
                echo "${tag}=${level}"
            } > "$levels_file"
        fi
    fi

    # Fix ownership if running as root
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
        chown -R "${SUDO_USER}:${SUDO_USER}" "$notify_dir"
    fi

    # Reload notify-daemon service if it exists and is active
    _notify_reload_daemon
}

# =============================================================================
# DAEMON RELOAD
# =============================================================================

# Reload notify-daemon service if installed
#
# Internal function called after registration changes.
# Detects if notify-daemon.service is active and reloads it.
_notify_reload_daemon() {
    local target_user="${SUDO_USER:-$USER}"
    
    # Check if service exists and is active
    local service_status
    if [[ -n "${SUDO_USER:-}" && $EUID -eq 0 ]]; then
        # Running as root via sudo — check as target user
        service_status=$(sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$(id -u "$target_user")" \
            systemctl --user is-active notify-daemon.service 2>/dev/null || echo "inactive")
    else
        # Running as regular user
        service_status=$(systemctl --user is-active notify-daemon.service 2>/dev/null || echo "inactive")
    fi

    if [[ "$service_status" == "active" ]]; then
        # Service is running — reload it
        if [[ -n "${SUDO_USER:-}" && $EUID -eq 0 ]]; then
            sudo -u "$target_user" XDG_RUNTIME_DIR="/run/user/$(id -u "$target_user")" \
                systemctl --user reload-or-restart notify-daemon.service 2>/dev/null || true
        else
            systemctl --user reload-or-restart notify-daemon.service 2>/dev/null || true
        fi
    fi
}

# Unregister a notification tag
#
# Usage: notify_unregister <tag>
#
# - Removes tag from services.conf
# - Removes tag mapping from icons.conf
# - Deletes files if no active entries remain
notify_unregister() {
    local tag="$1"
    local target_home
    target_home="$(_notify_resolve_home)"
    local notify_dir="$target_home/.config/notify-daemon"
    local services_file="$notify_dir/services.conf"
    local icons_file="$notify_dir/icons.conf"
    local levels_file="$notify_dir/levels.conf"

    # --- services.conf ---
    if [[ -f "$services_file" ]]; then
        sed -i "/^${tag}$/d" "$services_file"
        # Remove file if no active entries remain
        if ! grep -qv '^#\|^$' "$services_file" 2>/dev/null; then
            rm -f "$services_file"
        fi
    fi

    # --- icons.conf ---
    if [[ -f "$icons_file" ]]; then
        sed -i "/^${tag}=/d" "$icons_file"
        # Remove file if no active entries remain
        if ! grep -qv '^#\|^$' "$icons_file" 2>/dev/null; then
            rm -f "$icons_file"
        fi
    fi

    # --- levels.conf ---
    if [[ -f "$levels_file" ]]; then
        sed -i "/^${tag}=/d" "$levels_file"
    fi

    # Reload notify-daemon service if it exists and is active
    _notify_reload_daemon
}
