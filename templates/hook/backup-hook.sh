#!/bin/bash
# =============================================================================
# <HOOK-NAME> - <Phase> hook for <description>
# =============================================================================
# <Multi-line description of what this hook does.>
#
# Module: backup (hook)
# Requires: core, log, yaml, validate
# Version: 0.1.0
#
# Usage (standalone):
#   sudo <hook-name>.sh [--dry-run] [-c <custom-config>]
#
# Usage (as hook):
#   Called automatically by backup-system via hooks.<phase>[]
#   Receives BACKUP_ROOT, BACKUP_MOUNT, DRY_RUN via environment
#   Uses config: ~/.config/backup/hooks/<hook-name>.yml
#
# Options:
#   -c, --config <file>  Override default config path (optional)
#   --dry-run            Simulate (no changes made)
#   -y, --yes            Accept silently (hook engine compatibility)
#   -h, --help           Display this help
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: <hook-name> failed at line $LINENO" >&2; exit 1' ERR

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"

# Detect real user (when invoked via sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

# Default config path (hook manages its own config internally)
readonly DEFAULT_CONFIG="$REAL_HOME/.config/backup/hooks/<hook-name>.yml"

# Inherit from parent script (backup-system exports these)
BACKUP_ROOT="${BACKUP_ROOT:-}"
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << EOF
${C_CYAN}<Hook Name> v${VERSION}${C_NC}

<Short description>.

${C_GREEN}Usage:${C_NC}
    sudo $0 [--dry-run] [-c <custom-config>]

${C_GREEN}Options:${C_NC}
    -c, --config <file>  Override default config (optional)
                         Default: ~/.config/backup/hooks/<hook-name>.yml
    --dry-run            Simulate without making changes
    -h, --help           Display this help

${C_GREEN}Environment (set by backup-system):${C_NC}
    BACKUP_ROOT          Backup destination root path
    BACKUP_MOUNT         HDD mount point
    DRY_RUN              true/false
    LOG_FILE             Shared log file path

EOF
}

# =============================================================================
# CONFIG
# =============================================================================
# Declare hook-specific variables here
# MY_SETTING=""

load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Hook config not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    # Parse config values
    # MY_SETTING=$(parse_yaml "my_setting")

    # Defaults — use : "${VAR:=default}" (NOT [[ -z ]] && ... which breaks set -e)
    # : "${MY_SETTING:=default_value}"
}

validate_hook_config() {
    validation_reset

    validate_required "BACKUP_ROOT (env)" "$BACKUP_ROOT"
    # validate_required "my_setting" "$MY_SETTING"
    # validate_path "my_path" "$MY_PATH"
    # validate_integer "my_count" "$MY_COUNT"

    validation_check "$YAML_FILE"
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
HOOK_CONFIG="$DEFAULT_CONFIG"

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--config)
                HOOK_CONFIG="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                # Accept silently (compatibility with hook engine)
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1" "exit"
                ;;
        esac
    done
}

# =============================================================================
# HOOK LOGIC
# =============================================================================
run_hook() {
    log_section "<HOOK NAME>"

    if [[ "$DRY_RUN" == "true" ]]; then
        info "[DRY RUN] Would perform <action>"
        return 0
    fi

    # Hook logic here
    log "Performing <action>..."

    log_success "<Action> completed"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_arguments "$@"
    load_config "$HOOK_CONFIG"
    validate_hook_config

    run_hook
}

main "$@"
