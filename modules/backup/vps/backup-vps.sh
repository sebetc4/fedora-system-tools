#!/bin/bash
# =============================================================================
# BACKUP-VPS - Off-site backup from VPS to local machine
# =============================================================================
# Runs on LOCAL machine. Pulls VPS backups via SSH, applies GFS rotation.
# Called by systemd user timer: backup-vps.timer
#
# Features:
#   - YAML-based configuration (~/.config/backup/vps.yml)
#   - GFS rotation (Grandfather-Father-Son)
#   - Notifications via notify-daemon (logger)
#   - Dry-run mode for testing
#   - Lock file to prevent concurrent runs
#
# Module: backup-vps
# Requires: none (self-contained)
# Version: 0.1.0
#
# Usage:
#   backup-vps [OPTIONS]
#
# Options:
#   -c, --config <file>  Configuration file
#   -n, --dry-run        Simulate without modifying files
#   -h, --help           Display this help
# =============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # available for sourcing scripts
readonly SCRIPT_DIR
readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

# Default configuration file path (can be overridden with -c option)
readonly DEFAULT_CONFIG_FILE="$HOME/.config/backup/vps.yml"

# Lock file to prevent concurrent executions (user-level)
readonly LOCK_FILE="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/backup-vps.lock"

# Logger tag for notify-daemon integration
readonly LOG_TAG="notify-backup-vps"

# ============================================================================
# LOGGING FUNCTIONS (optimized with file descriptor)
# ============================================================================
LOG_FD_OPENED=false

open_log_fd() {
    if [[ "$LOG_FD_OPENED" = false ]] && [[ -n "$LOG_FILE" ]]; then
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null || true
        exec 3>>"$LOG_FILE"
        LOG_FD_OPENED=true
    fi
}

close_log_fd() {
    if [[ "$LOG_FD_OPENED" = true ]]; then
        exec 3>&-
        LOG_FD_OPENED=false
    fi
}

log() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '[%s] %s\n' "$ts" "$1" >&3
    printf '[%s] %s\n' "$ts" "$1"
}

error() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '[%s] [ERROR] %s\n' "$ts" "$1" >&3
    printf '[ERROR] %s\n' "$1" >&2
}

# error + exit
# Usage: die "short notification message" ["detailed log message"]
die() {
    local notification_msg="$1"
    local log_msg="${2:-$1}"
    
    error "$log_msg"
    send_notification "error" "VPS Backup Failed" "$notification_msg"
    close_log_fd
    exit 1
}

warn() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '[%s] [WARNING] %s\n' "$ts" "$1" >&3
    printf '[WARNING] %s\n' "$1" >&2
}

info() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '[%s] [INFO] %s\n' "$ts" "$1" >&3
    printf '[INFO] %s\n' "$1"
}

success() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '[%s] [SUCCESS] %s\n' "$ts" "$1" >&3
    printf '[SUCCESS] %s\n' "$1"
}

section() {
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    [[ "$LOG_FD_OPENED" = true ]] && printf '\n[%s] ═══ %s ═══\n' "$ts" "$1" >&3
    printf '\n═══ %s ═══\n' "$1"
}

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================
check_dependencies() {
    local missing_deps=()

    if ! command -v yq &> /dev/null; then
        missing_deps+=("yq")
    fi

    if ! command -v rsync &> /dev/null; then
        missing_deps+=("rsync")
    fi

    if ! command -v ssh &> /dev/null; then
        missing_deps+=("openssh-clients")
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "[ERROR] Missing required dependencies: ${missing_deps[*]}"
        echo "Installation: sudo dnf install ${missing_deps[*]}"
        exit 1
    fi
}

# ============================================================================
# CONFIG PARSING (YAML)
# ============================================================================
parse_yaml() {
    local key="$1"
    local value
    value=$(yq e ".${key}" "$CONFIG_FILE" 2>/dev/null)
    if [[ "$value" = "null" ]] || [[ -z "$value" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# Expand ~ to $HOME in paths
expand_path() {
    local path="$1"
    echo "${path/#\~/$HOME}"
}

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        echo "[ERROR] Configuration file not found: $config_file"
        echo ""
        echo "Create it with:"
        echo "  cp config.yml ~/.config/backup/vps.yml"
        echo "  # or run: ./install.sh"
        exit 1
    fi

    CONFIG_FILE="$config_file"

    # --- Connection ---
    VPS_HOST=$(parse_yaml "connection.ssh_host")
    VPS_BACKUP_DIR=$(parse_yaml "connection.remote_backup_dir")

    # --- Storage ---
    LOCAL_BACKUP_DIR=$(expand_path "$(parse_yaml "storage.local_backup_dir")")

    # --- Retention ---
    KEEP_DAILY=$(parse_yaml "retention.keep_daily")
    KEEP_WEEKLY=$(parse_yaml "retention.keep_weekly")
    KEEP_MONTHLY=$(parse_yaml "retention.keep_monthly")

    # --- Logging ---
    LOG_FILE=$(expand_path "$(parse_yaml "logging.file")")

    # --- Notifications ---
    NOTIF_ENABLED=$(parse_yaml "notifications.enabled")
    NOTIF_ON_SUCCESS=$(parse_yaml "notifications.on_success")
    NOTIF_ON_ERROR=$(parse_yaml "notifications.on_error")

    # --- Advanced ---
    RSYNC_OPTIONS=$(parse_yaml "advanced.rsync_options")

    # --- Defaults ---
    [[ -z "$VPS_HOST" ]] && VPS_HOST="main-vps"
    [[ -z "$VPS_BACKUP_DIR" ]] && VPS_BACKUP_DIR="/var/backups/vps"
    [[ -z "$LOCAL_BACKUP_DIR" ]] && LOCAL_BACKUP_DIR="$HOME/.backups/vps"
    [[ -z "$KEEP_DAILY" ]] && KEEP_DAILY=7
    [[ -z "$KEEP_WEEKLY" ]] && KEEP_WEEKLY=4
    [[ -z "$KEEP_MONTHLY" ]] && KEEP_MONTHLY=6
    [[ -z "$LOG_FILE" ]] && LOG_FILE="$HOME/.local/log/backup-vps/backup-vps.log"
    [[ -z "$NOTIF_ENABLED" ]] && NOTIF_ENABLED="true"
    [[ -z "$NOTIF_ON_SUCCESS" ]] && NOTIF_ON_SUCCESS="true"
    [[ -z "$NOTIF_ON_ERROR" ]] && NOTIF_ON_ERROR="true"
    [[ -z "$RSYNC_OPTIONS" ]] && RSYNC_OPTIONS="-av --partial --timeout=300"

    # Open log file descriptor
    open_log_fd

    # Validate configuration
    validate_config
}

# ============================================================================
# CONFIG VALIDATION
# ============================================================================
validate_config() {
    local errors=()

    # Required fields
    if [[ -z "$VPS_HOST" ]]; then
        errors+=("connection.ssh_host is required")
    fi

    if [[ -z "$LOCAL_BACKUP_DIR" ]]; then
        errors+=("storage.local_backup_dir is required")
    fi

    if [[ -z "$VPS_BACKUP_DIR" ]]; then
        errors+=("connection.remote_backup_dir is required")
    fi

    # Integer validation
    validate_integer() {
        local key="$1"
        local value="$2"
        if [[ -n "$value" ]] && ! [[ "$value" =~ ^[0-9]+$ ]]; then
            errors+=("$key must be a number (got: '$value')")
        fi
    }

    # Boolean validation
    validate_boolean() {
        local key="$1"
        local value="$2"
        if [[ -n "$value" ]] && [[ "$value" != "true" ]] && [[ "$value" != "false" ]]; then
            errors+=("$key must be 'true' or 'false' (got: '$value')")
        fi
    }

    validate_integer "retention.keep_daily" "$KEEP_DAILY"
    validate_integer "retention.keep_weekly" "$KEEP_WEEKLY"
    validate_integer "retention.keep_monthly" "$KEEP_MONTHLY"

    validate_boolean "notifications.enabled" "$NOTIF_ENABLED"
    validate_boolean "notifications.on_success" "$NOTIF_ON_SUCCESS"
    validate_boolean "notifications.on_error" "$NOTIF_ON_ERROR"

    # Show errors
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo ""
        echo "CONFIGURATION ERRORS:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        echo ""
        echo "Config file: $CONFIG_FILE"
        echo ""
        exit 1
    fi
}

# ============================================================================
# NOTIFICATIONS (via notify-daemon / logger)
# ============================================================================
send_notification() {
    local type="$1"     # "success" or "error"
    local title="$2"
    local message="$3"

    [[ "$NOTIF_ENABLED" != "true" ]] && return 0

    case "$type" in
        success)
            [[ "$NOTIF_ON_SUCCESS" != "true" ]] && return 0
            logger -t "$LOG_TAG" -p user.info "[ICON:emblem-synchronizing] $title: $message" 2>/dev/null || true
            ;;
        error)
            [[ "$NOTIF_ON_ERROR" != "true" ]] && return 0
            logger -t "$LOG_TAG" -p user.err "[ICON:dialog-error] $title: $message" 2>/dev/null || true
            ;;
        warning)
            logger -t "$LOG_TAG" -p user.warning "[ICON:dialog-warning] $title: $message" 2>/dev/null || true
            ;;
    esac
}

# ============================================================================
# GFS ROTATION (Grandfather-Father-Son)
# ============================================================================
gfs_rotate() {
    local backup_dir="$1"
    local seen_w seen_m
    seen_w=$(mktemp); seen_m=$(mktemp)
    local d=0 w=0 m=0 deleted=0

    # shellcheck disable=SC2045,SC2012  # ls -dt needed for time-sorted listing
    for dir in $(ls -dt "$backup_dir"/*_* 2>/dev/null); do
        dir_name=$(basename "$dir")
        # Extract YYYYMMDD from hostname_YYYYMMDD_HHMMSS
        dd=${dir_name#*_}; dd=${dd%%_*}
        [[ -z "$dd" ]] && continue
        ymd="${dd:0:4}-${dd:4:2}-${dd:6:2}"
        local keep=false

        # Daily: keep last N backups
        [[ "$d" -lt "$KEEP_DAILY" ]] && { d=$((d+1)); keep=true; }

        # Weekly: one per ISO week
        wk=$(date -d "$ymd" +%G-W%V 2>/dev/null) || true
        if [[ -n "$wk" ]] && ! grep -qxF "$wk" "$seen_w" 2>/dev/null; then
            echo "$wk" >> "$seen_w"
            [[ "$w" -lt "$KEEP_WEEKLY" ]] && { w=$((w+1)); keep=true; }
        fi

        # Monthly: one per calendar month
        mo="${dd:0:6}"
        if ! grep -qxF "$mo" "$seen_m" 2>/dev/null; then
            echo "$mo" >> "$seen_m"
            [[ "$m" -lt "$KEEP_MONTHLY" ]] && { m=$((m+1)); keep=true; }
        fi

        if ! $keep; then
            if [[ "$DRY_RUN" = true ]]; then
                info "[DRY-RUN] Would delete: $dir"
            else
                rm -rf "$dir"
            fi
            deleted=$((deleted+1))
        fi
    done

    rm -f "$seen_w" "$seen_m"
    echo "$deleted"
}

# ============================================================================
# SSH CONNECTIVITY CHECK
# ============================================================================
check_ssh() {
    info "Checking SSH connectivity to $VPS_HOST..."

    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$VPS_HOST" "echo ok" &>/dev/null; then
        # Detailed debug info in log only
        error "SSH connection to $VPS_HOST failed"
        error "Possible causes:"
        error "  - SSH agent not running or key not loaded (check: ssh-add -l)"
        error "  - gcr-ssh-agent not storing passphrase (save it at next login prompt)"
        error "  - SSH_AUTH_SOCK mismatch (expected: \$XDG_RUNTIME_DIR/gcr/ssh)"
        error "  - VPS is unreachable or network issue"
        error "  - SSH config missing (~/.ssh/config)"
        
        # Concise notification
        send_notification "error" "VPS Backup Failed" "Cannot connect to $VPS_HOST via SSH"
        close_log_fd
        exit 1
    fi

    success "SSH connection to $VPS_HOST OK"
}

# ============================================================================
# HELP
# ============================================================================
show_help() {
    cat << EOF
Backup VPS v${VERSION}

Pull VPS backups to local machine via SSH with GFS rotation.

Usage:
    $SCRIPT_NAME [OPTIONS]

Options:
    -c, --config <file>  Configuration file (default: $DEFAULT_CONFIG_FILE)
    -n, --dry-run        Simulate without modifying files
    -h, --help           Display this help

Configuration:
    Default: $DEFAULT_CONFIG_FILE

    Modify this file to change:
    - SSH host and remote paths
    - Local backup directory
    - GFS retention policy
    - Notifications
    - Rsync options

Examples:
    # Normal pull
    $SCRIPT_NAME

    # Test with dry-run
    $SCRIPT_NAME --dry-run

    # Use custom config
    $SCRIPT_NAME -c /path/to/config.yml

Notifications:
    Uses notify-daemon via logger (tag: backup-vps).
    Registered by install.sh in ~/.config/notify-daemon/

SSH passphrase:
    Save your SSH key passphrase in gcr-ssh-agent for unattended
    execution via systemd timer. Accept the prompt at next SSH login,
    or manually: ssh-add ~/.ssh/id_ed25519

EOF
}

# ============================================================================
# ARGUMENT PARSING
# ============================================================================
CONFIG_FILE="$DEFAULT_CONFIG_FILE"
DRY_RUN=false

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "[ERROR] Unknown option: $1"
                echo "Use --help to see available options"
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    parse_arguments "$@"

    check_dependencies

    load_config "$CONFIG_FILE"

    # Lock file (prevent concurrent runs)
    exec 200>"$LOCK_FILE"
    if ! flock -n 200; then
        die "Another instance is already running (lock: $LOCK_FILE)"
    fi

    # Cleanup on exit
    trap 'close_log_fd; rm -f "$LOCK_FILE"' EXIT INT TERM

    local START_TIME
    START_TIME=$(date +%s)

    section "BACKUP VPS"
    log "Version: $VERSION"
    log "Config: $CONFIG_FILE"
    log "Host: $VPS_HOST"
    log "Remote: $VPS_BACKUP_DIR"
    log "Local: $LOCAL_BACKUP_DIR"
    log "Retention: ${KEEP_DAILY}d / ${KEEP_WEEKLY}w / ${KEEP_MONTHLY}m"
    [[ "$DRY_RUN" = true ]] && warn "DRY-RUN MODE — no changes will be made"

    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_DIR"

    # ========================================================================
    # 1. CHECK SSH
    # ========================================================================
    section "SSH CONNECTIVITY"
    check_ssh

    # ========================================================================
    # 2. PULL BACKUPS VIA RSYNC
    # ========================================================================
    section "SYNC BACKUPS"
    log "Pulling backups from $VPS_HOST:$VPS_BACKUP_DIR/..."

    local TRANSFERRED_SIZE="0"

    if [[ "$DRY_RUN" = true ]]; then
        info "[DRY-RUN] Would run: rsync $RSYNC_OPTIONS -e ssh $VPS_HOST:$VPS_BACKUP_DIR/ $LOCAL_BACKUP_DIR/"
        # Run rsync in dry-run mode for preview
        # shellcheck disable=SC2086
        rsync $RSYNC_OPTIONS --dry-run \
            -e ssh \
            "$VPS_HOST:$VPS_BACKUP_DIR/" \
            "$LOCAL_BACKUP_DIR/" 2>&1 | head -20
    else
        local rsync_exit=0 rsync_output
        # shellcheck disable=SC2086
        rsync_output=$(rsync $RSYNC_OPTIONS \
            --stats --human-readable \
            -e ssh \
            "$VPS_HOST:$VPS_BACKUP_DIR/" \
            "$LOCAL_BACKUP_DIR/" 2>&1) || rsync_exit=$?
        printf '%s\n' "$rsync_output" >> "$LOG_FILE"

        TRANSFERRED_SIZE=$(printf '%s\n' "$rsync_output" \
            | grep "^Total transferred file size:" \
            | sed 's/.*: //' \
            | awk '{print $1}')
        [[ -z "$TRANSFERRED_SIZE" ]] && TRANSFERRED_SIZE="0"

        case $rsync_exit in
            0)
                success "Sync completed"
                ;;
            24)
                warn "Some files vanished during transfer (rsync code 24) — non-fatal"
                ;;
            23)
                warn "Partial transfer (rsync code 23) — check logs"
                ;;
            *)
                die "rsync failed with exit code $rsync_exit"
                ;;
        esac
    fi

    # ========================================================================
    # 3. GFS ROTATION
    # ========================================================================
    section "GFS ROTATION"
    log "Applying GFS rotation (${KEEP_DAILY}d / ${KEEP_WEEKLY}w / ${KEEP_MONTHLY}m)..."

    DELETED=$(gfs_rotate "$LOCAL_BACKUP_DIR")

    if [[ "$DRY_RUN" = true ]]; then
        info "[DRY-RUN] Would remove $DELETED old backups"
    else
        log "Rotation: $DELETED old backup(s) removed"
    fi

    # ========================================================================
    # 4. SUMMARY
    # ========================================================================
    section "SUMMARY"

    local END_TIME
    END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    local DURATION_MIN=$((DURATION / 60))
    local DURATION_SEC=$((DURATION % 60))

    local BACKUP_COUNT
    BACKUP_COUNT=$(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type f -name "*_*" 2>/dev/null | wc -l)
    local TOTAL_SIZE
    TOTAL_SIZE=$(du -sh "$LOCAL_BACKUP_DIR" 2>/dev/null | awk '{print $1}')

    success "Backup pull completed"
    info "Duration: ${DURATION_MIN}m ${DURATION_SEC}s"
    info "Backups: $BACKUP_COUNT"
    info "Transferred: $TRANSFERRED_SIZE"
    info "Total size: $TOTAL_SIZE"
    info "Deleted: $DELETED old backup(s)"
    info "Log: $LOG_FILE"

    # Notification
    if [[ "$DRY_RUN" != true ]]; then
        send_notification "success" \
            "VPS Backup Completed" \
            "${TRANSFERRED_SIZE} transferred, ${BACKUP_COUNT} stored locally, ${DURATION_MIN}m${DURATION_SEC}s"
    fi

    log "========================================================================="
}

# Execute
main "$@"
