#!/bin/bash
# =============================================================================
# NOTIFY-DAEMON - System notification daemon
# =============================================================================
# User service that listens to system notifications via journald.
# Monitors configured services and dispatches desktop notifications
# based on syslog priority levels.
#
# Module: notifications
# Requires: none (self-contained service)
# Version: 0.1.0
#
# Usage:
#   notify-daemon  (started by systemd user service)
# =============================================================================

# Note: -e (errexit) intentionally omitted — daemon handles errors explicitly
set -uo pipefail

LOG_FILE="$HOME/.local/log/notifications/notify-daemon.log"
CONFIG_DIR="$HOME/.config/notify-daemon"
SERVICES_FILE="$CONFIG_DIR/services.conf"
ICONS_FILE="$CONFIG_DIR/icons.conf"
LEVELS_FILE="$CONFIG_DIR/levels.conf"
STATE_FILE="$CONFIG_DIR/state"

# ===================
# Configuration
# ===================
ENABLE_DESKTOP=true
# shellcheck disable=SC2034  # ENABLE_LOG reserved for future log toggle
ENABLE_LOG=true
ENABLE_EMAIL=false
EMAIL_TO="root"

# Default icons by urgency level
declare -A URGENCY_ICONS=(
    [critical]="dialog-error"
    [warning]="dialog-warning"
    [normal]="dialog-information"
    [info]="dialog-information"
)

# Service-specific icons (loaded from config)
declare -A SERVICE_ICONS

# Per-tag notification levels (loaded from config)
declare -A TAG_LEVELS
DEFAULT_LEVEL="all"

mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$CONFIG_DIR"

# Create empty services file if it doesn't exist
# Modules register their own tags via lib/notify.sh or direct file write
if [[ ! -f "$SERVICES_FILE" ]]; then
    echo "# Services monitored by notify-daemon (one per line)" > "$SERVICES_FILE"
    echo "# Lines starting with # are ignored" >> "$SERVICES_FILE"
    echo "# Tags are registered by module installers" >> "$SERVICES_FILE"
fi

# Create empty icons configuration file if it doesn't exist
# Modules register their own icon mappings via lib/notify.sh or direct file write
if [[ ! -f "$ICONS_FILE" ]]; then
    cat > "$ICONS_FILE" << 'EOF'
# Custom icons per service
# Format: service_name=icon_name
# Icon mappings are registered by module installers
#
# Available standard icons:
#   dialog-information, dialog-warning, dialog-error
#   security-low, security-medium, security-high
#   drive-harddisk, drive-removable-media
#   network-error, network-idle, network-transmit-receive
#   emblem-important, emblem-synchronizing, tools, preferences-system
EOF
fi

# Create empty levels configuration file if it doesn't exist
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

# ===================
# Functions
# ===================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

send_desktop() {
    local urgency="$1"
    local title="$2"
    local message="$3"
    local icon="$4"

    [[ "$ENABLE_DESKTOP" == true ]] || return 0

    notify-send -u "$urgency" -i "$icon" "$title" "$message" 2>/dev/null
}

send_email() {
    local title="$1"
    local message="$2"

    [[ "$ENABLE_EMAIL" == true ]] || return 0

    echo -e "$message" | mail -s "$title" "$EMAIL_TO" 2>/dev/null || true
}

# Extract icon from message if specified with [ICON:name] syntax
extract_icon() {
    local message="$1"
    local icon=""

    if [[ "$message" =~ ^\[ICON:([^]]+)\] ]]; then
        icon="${BASH_REMATCH[1]}"
    fi

    echo "$icon"
}

# Remove icon directive from message
strip_icon_directive() {
    local message="$1"
    echo "$message" | sed -E 's/^\[ICON:[^]]+\][[:space:]]*//'
}

# Format tag for display: strip "notify-" prefix and capitalize
format_tag() {
    local tag="$1"
    local display="${tag#notify-}"
    # Capitalize first letter
    echo "${display^}"
}

# Determine the icon to use (priority: inline > service config > urgency default)
get_notification_icon() {
    local inline_icon="$1"
    local service="$2"
    local urgency="$3"

    # Priority 1: Inline icon directive
    if [[ -n "$inline_icon" ]]; then
        echo "$inline_icon"
        return
    fi

    # Priority 2: Service-specific icon from config
    if [[ -n "${SERVICE_ICONS[$service]:-}" ]]; then
        echo "${SERVICE_ICONS[$service]}"
        return
    fi

    # Priority 3: Default icon for urgency level
    echo "${URGENCY_ICONS[$urgency]:-dialog-information}"
}

# ===================
# State management
# ===================

# Last processed timestamp (microseconds since epoch, from journald)
LAST_TIMESTAMP=0

# Load last processed timestamp from state file
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        local ts
        ts=$(cat "$STATE_FILE" 2>/dev/null)
        if [[ "$ts" =~ ^[0-9]+$ ]]; then
            LAST_TIMESTAMP="$ts"
            log "Loaded state: last_timestamp=$LAST_TIMESTAMP"
        else
            log "WARNING: Invalid state file, starting fresh"
        fi
    else
        log "No state file, processing all new entries"
    fi
}

# Save last processed timestamp to state file
save_state() {
    echo "$LAST_TIMESTAMP" > "$STATE_FILE"
}

# Load notification levels from configuration file
load_levels() {
    [[ ! -f "$LEVELS_FILE" ]] && return

    while IFS='=' read -r key value; do
        # Ignore empty lines and comments
        [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        [[ -z "$key" || -z "$value" ]] && continue

        if [[ "$key" == "default" ]]; then
            DEFAULT_LEVEL="$value"
        else
            TAG_LEVELS["$key"]="$value"
        fi
    done < "$LEVELS_FILE"

    log "Loaded notification levels: default=$DEFAULT_LEVEL, ${#TAG_LEVELS[@]} tag override(s)"
}

# Get the notification level for a tag
get_tag_level() {
    local tag="$1"
    echo "${TAG_LEVELS[$tag]:-$DEFAULT_LEVEL}"
}

# Check if a notification should be sent based on level and urgency
# Returns 0 (true) if notification should be sent, 1 (false) if filtered
should_notify() {
    local level="$1"
    local urgency="$2"

    case "$level" in
        none)      return 1 ;;
        important) [[ "$urgency" == "critical" || "$urgency" == "warning" ]] ;;
        all|*)     return 0 ;;
    esac
}

process_notification() {
    local urgency="$1"
    local tag="$2"
    local message="$3"

    # --- Level filtering ---
    local level
    level=$(get_tag_level "$tag")

    if ! should_notify "$level" "$urgency"; then
        log "Filtered: [$urgency] $tag (level=$level): $message"
        return 0
    fi

    # Extract icon from message if present
    local inline_icon
    inline_icon=$(extract_icon "$message")

    # Strip icon directive from message
    if [[ -n "$inline_icon" ]]; then
        message=$(strip_icon_directive "$message")
    fi

    # Determine which icon to use
    local icon
    icon=$(get_notification_icon "$inline_icon" "$tag" "$urgency")

    # Format tag for display (strip notify- prefix, capitalize)
    local title
    title=$(format_tag "$tag")

    log "Received: [$urgency] $tag: $message (icon: $icon)"

    # Dispatch based on urgency
    # Levels:
    #   critical - popup + email (user.crit/err/alert/emerg)
    #   warning  - popup with warning icon (user.warning)
    #   normal   - popup with info icon (user.notice)
    #   info     - no popup, visible in notification panel (user.info)
    case "$urgency" in
        critical)
            send_desktop "critical" "$title" "$message" "$icon"
            send_email "[CRITICAL] $title" "$message"
            ;;
        warning)
            send_desktop "normal" "$title" "$message" "$icon"
            ;;
        normal)
            send_desktop "normal" "$title" "$message" "$icon"
            ;;
        info|*)
            send_desktop "low" "$title" "$message" "$icon"
            ;;
    esac
}

# Load services from configuration file
load_services() {
    local services=()
    while IFS= read -r line; do
        # Ignore empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        # Trim whitespace
        line=$(echo "$line" | xargs)
        [[ -n "$line" ]] && services+=("$line")
    done < "$SERVICES_FILE"

    printf '%s\n' "${services[@]}"
}

# Load service icons from configuration file
load_service_icons() {
    [[ ! -f "$ICONS_FILE" ]] && return

    while IFS='=' read -r service icon; do
        # Ignore empty lines and comments
        [[ -z "$service" || "$service" =~ ^[[:space:]]*# ]] && continue
        # Trim whitespace
        service=$(echo "$service" | xargs)
        icon=$(echo "$icon" | xargs)
        [[ -n "$service" && -n "$icon" ]] && SERVICE_ICONS["$service"]="$icon"
    done < "$ICONS_FILE"

    if [[ ${#SERVICE_ICONS[@]} -gt 0 ]]; then
        log "Loaded custom icons for ${#SERVICE_ICONS[@]} service(s)"
    fi
}

# Build -t arguments for journalctl
build_journal_args() {
    local services
    mapfile -t services < <(load_services)
    local args=()

    if [[ ${#services[@]} -eq 0 ]]; then
        log "WARNING: No services configured in $SERVICES_FILE"
        return 1
    fi

    for service in "${services[@]}"; do
        args+=("-t" "$service")
    done

    printf '%s\n' "${args[@]}"
}

# ===================
# Journald monitoring
# ===================

watch_journal() {
    local journal_args
    mapfile -t journal_args < <(build_journal_args)

    if [[ ${#journal_args[@]} -eq 0 ]]; then
        log "ERROR: No services to monitor"
        return 1
    fi

    log "Watching services: $(load_services | tr '\n' ' ')"

    # Monitor dynamically configured tags
    journalctl -f "${journal_args[@]}" -o json 2>/dev/null | \
    while IFS= read -r json_line; do
        # JSON parsing with error handling
        local message priority tag timestamp
        message=$(echo "$json_line" | jq -r '.MESSAGE // empty' 2>/dev/null)
        priority=$(echo "$json_line" | jq -r '.PRIORITY // "6"' 2>/dev/null)
        tag=$(echo "$json_line" | jq -r '.SYSLOG_IDENTIFIER // "system"' 2>/dev/null)
        timestamp=$(echo "$json_line" | jq -r '.__REALTIME_TIMESTAMP // "0"' 2>/dev/null)

        [[ -z "$message" ]] && continue

        # Skip already-processed entries (prevents replays on daemon restart)
        if [[ "$timestamp" -le "$LAST_TIMESTAMP" ]]; then
            continue
        fi

        # Convert syslog priority → urgency
        # 0-3: critical, 4: warning, 5: normal (popup), 6-7: info (no popup)
        local urgency="info"
        case "$priority" in
            [0-3]) urgency="critical" ;;
            4)     urgency="warning" ;;
            5)     urgency="normal" ;;
        esac

        # Pattern matching for urgency override
        if echo "$message" | grep -qiE "(virus|infected|malware)"; then
            urgency="critical"
        elif echo "$message" | grep -qiE "(error|failed|failure)"; then
            urgency="warning"
        fi

        process_notification "$urgency" "$tag" "$message"

        # Update state with latest processed timestamp
        LAST_TIMESTAMP="$timestamp"
        save_state
    done
}

# ===================
# Main
# ===================

log "=== Notify daemon started ==="
log "Desktop: $ENABLE_DESKTOP | Email: $ENABLE_EMAIL"
log "Services config: $SERVICES_FILE"
log "Icons config: $ICONS_FILE"
log "Levels config: $LEVELS_FILE"
log "State file: $STATE_FILE"

# Load service-specific icons, notification levels, and state
load_service_icons
load_levels
load_state

# Check dependencies
if ! command -v jq &>/dev/null; then
    log "ERROR: jq not found, exiting"
    echo "ERROR: jq is required. Install with: sudo dnf install jq" >&2
    exit 1
fi

if [[ "$ENABLE_DESKTOP" == true ]] && ! command -v notify-send &>/dev/null; then
    log "WARNING: notify-send not found, desktop notifications disabled"
    ENABLE_DESKTOP=false
fi

# Start monitoring
watch_journal &
JOURNAL_PID=$!

# Cleanup on exit
trap 'kill $JOURNAL_PID 2>/dev/null; log "Daemon stopped"' EXIT INT TERM

# Keep script running
wait