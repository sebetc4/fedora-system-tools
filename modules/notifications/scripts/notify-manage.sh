#!/bin/bash
# =============================================================================
# NOTIFY-MANAGE - Notification service manager
# =============================================================================
# Utility to manage services monitored by notify-daemon.
# Add, remove, list, and test monitored services.
#
# Module: notifications
# Requires: core
# Version: 0.1.0
#
# Usage:
#   notify-manage <command> [args]
# =============================================================================

# Note: -e (errexit) intentionally omitted — interactive tool handles errors explicitly
set -uo pipefail

readonly CONFIG_DIR="$HOME/.config/notify-daemon"
readonly SERVICES_FILE="$CONFIG_DIR/services.conf"
readonly ICONS_FILE="$CONFIG_DIR/icons.conf"
readonly LEVELS_FILE="$CONFIG_DIR/levels.conf"

# Shared library
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"

usage() {
    cat << EOF
Usage: notify-manage <command> [args]

Manage services monitored by notify-daemon

Commands:
  list                          Display currently monitored services
  add <service> [--icon <icon>] Add a service to monitor (with optional icon)
  remove <service>              Remove a service from monitoring
  level [<tag> [<level>]]       View or set notification levels
  test <service>                Send a test notification

Levels:
  all         All notifications (info, normal, warning, critical)
  important   Warning + critical only (threats, errors)
  none        No desktop notifications (still logged to journald)

Examples:
  notify-manage list
  notify-manage add backup-vps --icon drive-harddisk
  notify-manage remove smartd
  notify-manage level                           Show all tag levels
  notify-manage level notify-daily-scan           Show level for a tag
  notify-manage level notify-daily-scan important  Set level for a tag
  notify-manage test clamav-scan

Configuration: $SERVICES_FILE
             $ICONS_FILE
             $LEVELS_FILE
EOF
    exit 1
}

# Initialize config files if they don't exist
# Tags are registered by module installers — no hardcoded defaults
init_config() {
    mkdir -p "$CONFIG_DIR"
    if [[ ! -f "$SERVICES_FILE" ]]; then
        echo "# Services monitored by notify-daemon (one per line)" > "$SERVICES_FILE"
        echo "# Lines starting with # are ignored" >> "$SERVICES_FILE"
        echo "# Tags are registered by module installers" >> "$SERVICES_FILE"
        echo -e "${C_GREEN}Configuration initialized: $SERVICES_FILE${C_NC}"
    fi
    if [[ ! -f "$ICONS_FILE" ]]; then
        echo "# Custom icons per service" > "$ICONS_FILE"
        echo "# Format: service_name=icon_name" >> "$ICONS_FILE"
        echo "# Icon mappings are registered by module installers" >> "$ICONS_FILE"
    fi
    if [[ ! -f "$LEVELS_FILE" ]]; then
        cat > "$LEVELS_FILE" << 'EOF'
# Notification level per tag
# Levels: all | important | none
#
#   all       — All notifications (info, normal, warning, critical)
#   important — Warning + critical only (threats, errors)
#   none      — No desktop notifications (still logged to journald)
#
# Tags not listed here use the default level.
# Managed via: notify-manage level

default=all
EOF
    fi
}

# List monitored services
list_services() {
    init_config

    echo -e "${C_GREEN}Currently monitored services:${C_NC}"
    echo ""

    local count=0
    while IFS= read -r line; do
        # Ignore empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        line=$(echo "$line" | xargs)
        if [[ -n "$line" ]]; then
            echo "  - $line"
            ((count++))
        fi
    done < "$SERVICES_FILE"

    echo ""
    echo "Total: $count service(s)"
    echo ""
    echo "Configuration file: $SERVICES_FILE"
}

# Add a service (with optional icon)
add_service() {
    local service="$1"
    shift
    local icon=""

    # Parse --icon option
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --icon)
                icon="${2:-}"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [[ -z "$service" ]]; then
        echo -e "${C_RED}Error: Service name required${C_NC}"
        echo "Usage: notify-manage add <service> [--icon <icon>]"
        exit 1
    fi

    init_config

    # Add to services.conf if not already present
    if grep -qxF "$service" "$SERVICES_FILE"; then
        echo -e "${C_YELLOW}Service '$service' is already monitored${C_NC}"
    else
        echo "$service" >> "$SERVICES_FILE"
        echo -e "${C_GREEN}Service '$service' added${C_NC}"
    fi

    # Add icon mapping if provided
    if [[ -n "$icon" ]]; then
        if grep -q "^${service}=" "$ICONS_FILE" 2>/dev/null; then
            echo -e "${C_YELLOW}Icon for '$service' already configured${C_NC}"
        else
            echo "${service}=${icon}" >> "$ICONS_FILE"
            echo -e "${C_GREEN}Icon '${icon}' set for '$service'${C_NC}"
        fi
    fi

    echo ""
    _reload_daemon
}

# Remove a service (from both services.conf and icons.conf)
remove_service() {
    local service="$1"

    if [[ -z "$service" ]]; then
        echo -e "${C_RED}Error: Service name required${C_NC}"
        echo "Usage: notify-manage remove <service>"
        exit 1
    fi

    init_config

    # Remove from services.conf
    if grep -qxF "$service" "$SERVICES_FILE"; then
        grep -vxF "$service" "$SERVICES_FILE" > "$SERVICES_FILE.tmp"
        mv "$SERVICES_FILE.tmp" "$SERVICES_FILE"
        echo -e "${C_GREEN}Service '$service' removed${C_NC}"

        # Delete file if no active entries remain
        if ! grep -qv '^#\|^$' "$SERVICES_FILE" 2>/dev/null; then
            rm -f "$SERVICES_FILE"
        fi
    else
        echo -e "${C_YELLOW}Service '$service' is not monitored${C_NC}"
    fi

    # Remove from icons.conf
    if [[ -f "$ICONS_FILE" ]] && grep -q "^${service}=" "$ICONS_FILE" 2>/dev/null; then
        sed -i "/^${service}=/d" "$ICONS_FILE"
        echo -e "${C_GREEN}Icon mapping for '$service' removed${C_NC}"

        # Delete file if no active entries remain
        if ! grep -qv '^#\|^$' "$ICONS_FILE" 2>/dev/null; then
            rm -f "$ICONS_FILE"
        fi
    fi

    # Remove from levels.conf
    if [[ -f "$LEVELS_FILE" ]] && grep -q "^${service}=" "$LEVELS_FILE" 2>/dev/null; then
        sed -i "/^${service}=/d" "$LEVELS_FILE"
        echo -e "${C_GREEN}Notification level for '$service' removed${C_NC}"
    fi

    echo ""
    _reload_daemon
}

# Test a service
test_service() {
    local service="${1:-test-notify}"

    echo "Sending 3 test notifications for service '$service'..."
    echo ""

    # Test info
    logger -t "$service" -p user.info "[ICON:dialog-information] Test notification INFO - $(date '+%H:%M:%S')"
    echo -e "${C_GREEN}✓${C_NC} INFO notification sent"
    sleep 1

    # Test warning
    logger -t "$service" -p user.warning "[ICON:dialog-warning] Test notification WARNING - $(date '+%H:%M:%S')"
    echo -e "${C_YELLOW}✓${C_NC} WARNING notification sent"
    sleep 1

    # Test critical
    logger -t "$service" -p user.crit "[ICON:dialog-error] Test notification CRITICAL - $(date '+%H:%M:%S')"
    echo -e "${C_RED}✓${C_NC} CRITICAL notification sent"

    # Show current level for context
    local level
    level=$(_get_tag_level "$service")
    echo ""
    echo -e "Current level: ${C_BOLD}${level}${C_NC} ($(_level_description "$level"))"
    case "$level" in
        all)       echo "  Expected: all 3 notifications should appear" ;;
        important) echo "  Expected: only WARNING + CRITICAL should appear" ;;
        none)      echo "  Expected: no desktop notifications (still logged)" ;;
    esac

    echo ""
    echo "Notifications should appear if:"
    echo "  1. The notify-daemon daemon is active"
    echo "  2. The service '$service' is monitored (see: notify-manage list)"
    echo ""
    echo "Check logs: tail -f ~/.local/log/notifications/notify-daemon.log"
}

# ===================
# Level management
# ===================

# Get the default level from levels.conf
_get_default_level() {
    local default="all"
    if [[ -f "$LEVELS_FILE" ]]; then
        local val
        val=$(grep '^default=' "$LEVELS_FILE" 2>/dev/null | tail -1 | cut -d= -f2 | xargs)
        [[ -n "$val" ]] && default="$val"
    fi
    echo "$default"
}

# Get the level for a specific tag
_get_tag_level() {
    local tag="$1"
    local default
    default=$(_get_default_level)

    if [[ -f "$LEVELS_FILE" ]] && grep -q "^${tag}=" "$LEVELS_FILE" 2>/dev/null; then
        grep "^${tag}=" "$LEVELS_FILE" | tail -1 | cut -d= -f2 | xargs
    else
        echo "$default"
    fi
}

# Format level with description
_level_description() {
    local level="$1"
    case "$level" in
        all)       echo "all notifications" ;;
        important) echo "warning + critical" ;;
        none)      echo "disabled" ;;
        *)         echo "unknown" ;;
    esac
}

# Validate a level value
_validate_level() {
    local level="$1"
    case "$level" in
        all|important|none) return 0 ;;
        *)
            echo -e "${C_RED}Error: Invalid level '$level'${C_NC}"
            echo "Valid levels: all, important, none"
            return 1
            ;;
    esac
}

# List all tag levels
level_list() {
    init_config

    local default
    default=$(_get_default_level)

    echo -e "${C_BOLD}${C_CYAN}Notification levels${C_NC}"
    echo -e "  Default: ${C_BOLD}${default}${C_NC} ($(_level_description "$default"))"
    echo ""

    if [[ ! -f "$SERVICES_FILE" ]]; then
        echo "  No services configured."
        return
    fi

    # Read all monitored services and show their level
    local count=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        line=$(echo "$line" | xargs)
        [[ -z "$line" ]] && continue

        local level
        level=$(_get_tag_level "$line")
        local is_override=""

        # Check if this tag has an explicit override
        if [[ -f "$LEVELS_FILE" ]] && grep -q "^${line}=" "$LEVELS_FILE" 2>/dev/null; then
            is_override=" *"
        fi

        # Color based on level
        local color="$C_GREEN"
        case "$level" in
            important) color="$C_YELLOW" ;;
            none)      color="$C_DIM" ;;
        esac

        printf "  %-30s ${color}%-12s${C_NC}${C_DIM}(%s)${C_NC}%s\n" \
            "$line" "$level" "$(_level_description "$level")" "$is_override"
        ((count++))
    done < "$SERVICES_FILE"

    echo ""
    if [[ $count -gt 0 ]]; then
        echo -e "${C_DIM}  * = explicit override (others inherit default)${C_NC}"
        echo ""
    fi
    echo "Configuration file: $LEVELS_FILE"
}

# Get or set level for a tag
level_manage() {
    local tag="${1:-}"
    local level="${2:-}"

    # No args: list all
    if [[ -z "$tag" ]]; then
        level_list
        return
    fi

    init_config

    # One arg: show level for tag
    if [[ -z "$level" ]]; then
        local current
        current=$(_get_tag_level "$tag")
        local is_default=""
        if [[ -f "$LEVELS_FILE" ]] && grep -q "^${tag}=" "$LEVELS_FILE" 2>/dev/null; then
            is_default=""
        else
            is_default=" (default)"
        fi
        echo -e "${C_BOLD}$tag${C_NC}: $current ($(_level_description "$current"))$is_default"
        return
    fi

    # Two args: set level
    _validate_level "$level" || exit 1

    if [[ -f "$LEVELS_FILE" ]] && grep -q "^${tag}=" "$LEVELS_FILE" 2>/dev/null; then
        # Update existing entry
        sed -i "s/^${tag}=.*/${tag}=${level}/" "$LEVELS_FILE"
    else
        # Append new entry
        echo "${tag}=${level}" >> "$LEVELS_FILE"
    fi

    echo -e "${C_GREEN}Level for '$tag' set to: ${level} ($(_level_description "$level"))${C_NC}"
    echo ""
    _reload_daemon
}

# =============================================================================
# HELPERS
# =============================================================================

# Get list of active tags (non-comment, non-empty lines from services.conf)
_get_active_tags() {
    [[ ! -f "$SERVICES_FILE" ]] && return
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        line=$(echo "$line" | xargs)
        [[ -n "$line" ]] && echo "$line"
    done < "$SERVICES_FILE"
}

# Restart daemon if running
_reload_daemon() {
    if systemctl --user is-active notify-daemon.service &>/dev/null; then
        systemctl --user restart notify-daemon.service 2>/dev/null \
            && echo -e "${C_GREEN}Daemon restarted${C_NC}" \
            || echo -e "${C_YELLOW}Failed to restart daemon. Run manually:${C_NC}
  systemctl --user restart notify-daemon.service"
    else
        echo -e "${C_DIM}Daemon is not running — changes will apply on next start${C_NC}"
    fi
}

# =============================================================================
# INTERACTIVE FUNCTIONS
# =============================================================================

# Interactive add: prompt for tag name and optional icon
interactive_add() {
    echo -e "${C_BOLD}${C_CYAN}Add a notification tag${C_NC}"
    echo ""

    local tag
    tag=$(ui_input "Tag name (syslog identifier)" "notify-")
    [[ -z "$tag" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    local icon
    icon=$(ui_input "Icon name (optional, leave empty to skip)" "")

    if [[ -n "$icon" ]]; then
        add_service "$tag" --icon "$icon"
    else
        add_service "$tag"
    fi
}

# Interactive remove: choose from existing tags
interactive_remove() {
    init_config

    local tags=()
    mapfile -t tags < <(_get_active_tags)

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}No tags configured${C_NC}"
        return
    fi

    echo -e "${C_BOLD}${C_CYAN}Remove a notification tag${C_NC}"
    echo ""

    local tag
    tag=$(ui_choose --header "Select tag to remove" "${tags[@]}")
    [[ -z "$tag" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    if ui_confirm "Remove '$tag'?"; then
        remove_service "$tag"
    else
        echo -e "${C_YELLOW}Cancelled${C_NC}"
    fi
}

# Interactive level: choose tag, then choose level
interactive_level() {
    init_config

    local tags=()
    mapfile -t tags < <(_get_active_tags)

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}No tags configured${C_NC}"
        return
    fi

    # Show current levels first
    level_list
    echo ""

    local tag
    tag=$(ui_choose --header "Select tag to change level" "${tags[@]}")
    [[ -z "$tag" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    local current
    current=$(_get_tag_level "$tag")

    echo ""
    echo -e "Current level for ${C_BOLD}$tag${C_NC}: $current ($(_level_description "$current"))"
    echo ""

    local level
    level=$(ui_choose --header "Select new level" \
        "all       — all notifications" \
        "important — warning + critical only" \
        "none      — disabled (still logged)")
    [[ -z "$level" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    # Extract level name (first word before spaces)
    level="${level%% *}"

    level_manage "$tag" "$level"
}

# Interactive test: choose tag to test
interactive_test() {
    init_config

    local tags=()
    mapfile -t tags < <(_get_active_tags)

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "${C_YELLOW}No tags configured — using 'test-notify'${C_NC}"
        test_service "test-notify"
        return
    fi

    echo -e "${C_BOLD}${C_CYAN}Test notifications${C_NC}"
    echo ""

    local tag
    tag=$(ui_choose --header "Select tag to test" "${tags[@]}")
    [[ -z "$tag" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    echo ""
    test_service "$tag"
}

# Main interactive menu (loop)
interactive_menu() {
    while true; do
        ui_header "NOTIFY-MANAGE"

        local action
        action=$(ui_choose --header "What do you want to do?" \
            "List tags" \
            "Add tag" \
            "Remove tag" \
            "Change level" \
            "Test notifications" \
            "Quit")

        echo ""

        case "$action" in
            "List tags")          list_services ;;
            "Add tag")            interactive_add ;;
            "Remove tag")         interactive_remove ;;
            "Change level")       interactive_level ;;
            "Test notifications") interactive_test ;;
            "Quit"|"")            break ;;
        esac

        echo ""
        echo -e "${C_DIM}Press Enter to continue...${C_NC}"
        read -r
    done
}

# =============================================================================
# MAIN
# =============================================================================

# No args: interactive mode
if [[ $# -eq 0 ]]; then
    interactive_menu
    exit 0
fi

CMD="$1"
shift

case "$CMD" in
    list)
        list_services
        ;;
    add)
        add_service "${1:-}" "${@:2}"
        ;;
    remove)
        remove_service "${1:-}"
        ;;
    level)
        level_manage "${1:-}" "${2:-}"
        ;;
    test)
        test_service "${1:-test-notify}"
        ;;
    --help|-h|help)
        usage
        ;;
    *)
        echo -e "${C_RED}Unknown command: $CMD${C_NC}"
        echo ""
        usage
        ;;
esac
