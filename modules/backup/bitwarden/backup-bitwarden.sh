#!/bin/bash
# =============================================================================
# BACKUP-BITWARDEN - Bitwarden vault backup
# =============================================================================
# Exports and encrypts Bitwarden vault for offline backup.
# Output depends on export_mode config (default: both):
#   - bitwarden-TIMESTAMP.json.age      (JSON cleartext encrypted with age)
#   - bitwarden-TIMESTAMP.encrypted.json (Bitwarden encrypted format)
#
# Module: backup
# Requires: core, log, ui, yaml, validate, backup
# Version: 0.1.0
#
# Usage:
#   backup-bitwarden [OPTIONS]
# =============================================================================

set -euo pipefail

# =============================================================================
# LIB LOADING
# =============================================================================
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/ui.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"
source "$LIB_DIR/backup.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================
readonly VERSION="0.1.0"
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

detect_real_user
readonly DEFAULT_CONFIG_FILE="$REAL_HOME/.config/backup/bitwarden.yml"

# shellcheck disable=SC2034  # used by log.sh
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"

# Config variables (set by load_config)
BW_API_KEY_PATH=""
BW_BACKUP_PATH=""
BW_RETENTION=3
BW_EXPORT_MODE=""
DRY_RUN=false

# State tracking for cleanup
_BW_LOGGED_IN=false
_BW_UNLOCKED=false
_BW_SESSION=""
_TMP_API_KEY=""
_TMP_EXPORT_JSON=""
_TMP_EXPORT_ENC=""
_MASTER_PASSWORD=""

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
${C_BOLD}Bitwarden Backup Script v${VERSION}${C_NC}

Export and encrypt Bitwarden vault for offline backup.
Standalone script callable directly or via backup-system hooks.

${C_GREEN}Usage:${C_NC}
    $SCRIPT_NAME [options]

${C_GREEN}Options:${C_NC}
    -c, --config <file>    Config file (default: ~/.config/backup/bitwarden.yml)
    -n, --dry-run          Simulate without making changes
    -h, --help             Show this help

${C_GREEN}Output files (depends on export_mode config):${C_NC}
    bitwarden-TIMESTAMP.json.age         JSON export encrypted with age
    bitwarden-TIMESTAMP.encrypted.json   Bitwarden encrypted export (re-importable)

${C_GREEN}Export modes (set in config.yml):${C_NC}
    both             Both file types (default)
    age_json         Only .json.age
    encrypted_json   Only .encrypted.json

${C_GREEN}Examples:${C_NC}
    $SCRIPT_NAME                    # Interactive backup
    $SCRIPT_NAME -n                 # Dry run (test config)
    $SCRIPT_NAME -c /path/to.yml   # Custom config

EOF
    exit 0
}

# =============================================================================
# CONFIG
# =============================================================================
load_config() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        error "Config file not found: $config_file" "exit"
    fi

    YAML_FILE="$config_file"

    # Bitwarden config
    BW_API_KEY_PATH=$(parse_yaml "bitwarden.api_key_path")
    BW_BACKUP_PATH=$(parse_yaml "bitwarden.backup_path")
    BW_RETENTION=$(parse_yaml "bitwarden.retention")
    BW_EXPORT_MODE=$(parse_yaml "bitwarden.export_mode")

    # Logging (reuse backup-system log if available)
    LOG_FILE=$(parse_yaml "logging.file")

    # Defaults
    [[ -z "$BW_RETENTION" ]] && BW_RETENTION=3
    [[ -z "$BW_EXPORT_MODE" ]] && BW_EXPORT_MODE="both"
    [[ -z "$LOG_FILE" ]] && LOG_FILE="$REAL_HOME/.local/log/backup-bitwarden/backup-bitwarden.log"
    mkdir -p "$(dirname "$LOG_FILE")"

    # Validate
    validate_config
}

validate_config() {
    validation_reset

    validate_required "bitwarden.api_key_path" "$BW_API_KEY_PATH"
    validate_required "bitwarden.backup_path" "$BW_BACKUP_PATH"
    validate_path "bitwarden.api_key_path" "$BW_API_KEY_PATH"
    validate_path "bitwarden.backup_path" "$BW_BACKUP_PATH"
    validate_integer "bitwarden.retention" "$BW_RETENTION"
    validate_pattern "bitwarden.export_mode" "$BW_EXPORT_MODE" \
        "^(both|age_json|encrypted_json)$" \
        "must be 'both', 'age_json', or 'encrypted_json'"

    if [[ "$BW_RETENTION" -lt 1 ]] 2>/dev/null; then
        validation_add_error "bitwarden.retention must be at least 1"
    fi

    validation_check "$YAML_FILE"
}

# =============================================================================
# CLEANUP (trap handler)
# =============================================================================
cleanup() {
    # Shred temporary cleartext files
    if [[ -n "$_TMP_API_KEY" ]] && [[ -f "$_TMP_API_KEY" ]]; then
        shred -u "$_TMP_API_KEY" 2>/dev/null || rm -f "$_TMP_API_KEY"
    fi
    if [[ -n "$_TMP_EXPORT_JSON" ]] && [[ -f "$_TMP_EXPORT_JSON" ]]; then
        shred -u "$_TMP_EXPORT_JSON" 2>/dev/null || rm -f "$_TMP_EXPORT_JSON"
    fi
    if [[ -n "$_TMP_EXPORT_ENC" ]] && [[ -f "$_TMP_EXPORT_ENC" ]]; then
        rm -f "$_TMP_EXPORT_ENC" 2>/dev/null || true
    fi

    # Lock and logout Bitwarden
    if [[ "$_BW_UNLOCKED" == "true" ]]; then
        BW_SESSION="$_BW_SESSION" bw lock 2>/dev/null || true
    fi
    if [[ "$_BW_LOGGED_IN" == "true" ]]; then
        bw logout 2>/dev/null || true
    fi

    # Unset all sensitive variables
    _MASTER_PASSWORD=""
    _BW_SESSION=""
    unset _MASTER_PASSWORD _BW_SESSION
    unset BW_CLIENTID BW_CLIENTSECRET BW_SESSION
}

# =============================================================================
# ROTATION
# =============================================================================
rotate_backups() {
    local backup_dir="$1"
    local pattern="$2"
    local keep="$3"

    local count
    count=$(find "$backup_dir" -maxdepth 1 -name "$pattern" 2>/dev/null | wc -l)

    if [[ "$count" -gt "$keep" ]]; then
        local to_delete=$((count - keep))
        log "Rotating: deleting $to_delete old backup(s) matching $pattern"

        find "$backup_dir" -maxdepth 1 -name "$pattern" -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2- | tail -n +"$((keep + 1))" | while read -r old; do
            log "  Deleting: $(basename "$old")"
            rm -f "$old"
        done
    fi
}

# =============================================================================
# MAIN BACKUP LOGIC
# =============================================================================
run_backup() {
    local config_file="$1"
    # Load and validate config
    load_config "$config_file"

    # Resolve export mode flags
    local do_age_json=false do_encrypted=false
    case "$BW_EXPORT_MODE" in
        both)            do_age_json=true; do_encrypted=true ;;
        age_json)        do_age_json=true ;;
        encrypted_json)  do_encrypted=true ;;
    esac

    # Verify API key file exists
    if [[ ! -f "$BW_API_KEY_PATH" ]]; then
        error "API key file not found: $BW_API_KEY_PATH"
        error "Create it with: age -p -o $BW_API_KEY_PATH bw-api-key.json"
        return 1
    fi

    # Create backup directory if needed
    mkdir -p "$BW_BACKUP_PATH"

    local timestamp
    timestamp=$(date +%Y-%m-%d-%H%M%S)

    # Dry run: show what would happen and exit
    if [[ "$DRY_RUN" == "true" ]]; then
        log_section "BITWARDEN BACKUP (DRY RUN)"
        info "Config file:    $YAML_FILE"
        info "API key:        $BW_API_KEY_PATH"
        info "Backup path:    $BW_BACKUP_PATH"
        info "Retention:      $BW_RETENTION"
        info "Export mode:    $BW_EXPORT_MODE"
        info ""
        info "Would create:"
        if [[ "$do_age_json" == "true" ]]; then
            info "  $BW_BACKUP_PATH/bitwarden-$timestamp.json.age"
        fi
        if [[ "$do_encrypted" == "true" ]]; then
            info "  $BW_BACKUP_PATH/bitwarden-$timestamp.encrypted.json"
        fi
        info ""
        local existing
        existing=$(find "$BW_BACKUP_PATH" -maxdepth 1 \( -name "bitwarden-*.json.age" -o -name "bitwarden-*.encrypted.json" \) 2>/dev/null | wc -l)
        info "Existing backups: $existing"
        log_success "Dry run complete (no changes made)"
        return 0
    fi

    log_section "BITWARDEN BACKUP"

    # ---- Step 1: Decrypt API key ----
    log_step "Decrypting API key..."

    _TMP_API_KEY=$(mktemp /tmp/bw-api-key-XXXXXX.json)
    chmod 600 "$_TMP_API_KEY"

    if ! age -d -o "$_TMP_API_KEY" "$BW_API_KEY_PATH"; then
        error "Failed to decrypt API key file"
        return 1
    fi

    local client_id client_secret
    client_id=$(jq -r '.client_id' "$_TMP_API_KEY" 2>/dev/null)
    client_secret=$(jq -r '.client_secret' "$_TMP_API_KEY" 2>/dev/null)

    # Shred API key immediately
    shred -u "$_TMP_API_KEY" 2>/dev/null || rm -f "$_TMP_API_KEY"
    _TMP_API_KEY=""

    if [[ -z "$client_id" ]] || [[ "$client_id" == "null" ]] || \
       [[ -z "$client_secret" ]] || [[ "$client_secret" == "null" ]]; then
        error "Invalid API key file (missing client_id or client_secret)"
        return 1
    fi

    log_success "API key decrypted"

    # ---- Step 2: Master password input ----
    log_step "Master password required..."

    _MASTER_PASSWORD=$(ui_password "Bitwarden master password")

    if [[ -z "$_MASTER_PASSWORD" ]]; then
        error "Master password cannot be empty"
        return 1
    fi

    # ---- Step 3: Login to Bitwarden ----
    log_step "Logging in to Bitwarden..."

    # Ensure clean state (previous session may linger after interrupted run)
    bw logout 2>/dev/null || true

    if ! BW_CLIENTID="$client_id" BW_CLIENTSECRET="$client_secret" bw login --apikey 2>/dev/null; then
        error "Bitwarden login failed (invalid API key?)"
        unset client_id client_secret
        return 1
    fi

    _BW_LOGGED_IN=true
    unset client_id client_secret

    log_success "Logged in"

    # ---- Step 4: Unlock vault ----
    log_step "Unlocking vault..."

    _BW_SESSION=$(echo "$_MASTER_PASSWORD" | bw unlock --raw 2>/dev/null) || true

    if [[ -z "$_BW_SESSION" ]]; then
        error "Failed to unlock vault (wrong master password?)"
        return 1
    fi

    _BW_UNLOCKED=true
    export BW_SESSION="$_BW_SESSION"

    log_success "Vault unlocked"

    # ---- Step 5+7: Export JSON cleartext + encrypt with age ----
    if [[ "$do_age_json" == "true" ]]; then
        log_step "Exporting vault (JSON)..."

        _TMP_EXPORT_JSON=$(mktemp /tmp/bw-export-XXXXXX.json)
        chmod 600 "$_TMP_EXPORT_JSON"

        if ! bw export --format json --output "$_TMP_EXPORT_JSON" 2>/dev/null; then
            error "JSON export failed"
            return 1
        fi

        if [[ ! -s "$_TMP_EXPORT_JSON" ]]; then
            error "JSON export is empty"
            return 1
        fi

        log_success "JSON export completed"

        # Encrypt JSON with age
        log_step "Encrypting JSON export with age..."

        local output_age="$BW_BACKUP_PATH/bitwarden-${timestamp}.json.age"

        if ! echo "$_MASTER_PASSWORD" | age -p -o "$output_age" "$_TMP_EXPORT_JSON"; then
            error "age encryption failed"
            return 1
        fi

        if [[ ! -s "$output_age" ]]; then
            error "age encrypted file is empty"
            return 1
        fi

        log_success "Encrypted: $(basename "$output_age")"

        # Shred JSON cleartext immediately
        shred -u "$_TMP_EXPORT_JSON" 2>/dev/null || rm -f "$_TMP_EXPORT_JSON"
        _TMP_EXPORT_JSON=""
    fi

    # ---- Step 6+9: Export encrypted (Bitwarden format) ----
    if [[ "$do_encrypted" == "true" ]]; then
        log_step "Exporting vault (encrypted)..."

        _TMP_EXPORT_ENC=$(mktemp /tmp/bw-export-XXXXXX.encrypted.json)
        chmod 600 "$_TMP_EXPORT_ENC"

        if ! bw export --format encrypted_json --output "$_TMP_EXPORT_ENC" 2>/dev/null; then
            error "Encrypted export failed"
            return 1
        fi

        if [[ ! -s "$_TMP_EXPORT_ENC" ]]; then
            error "Encrypted export is empty"
            return 1
        fi

        log_success "Encrypted export completed"

        # Move encrypted export to backup path
        local output_enc="$BW_BACKUP_PATH/bitwarden-${timestamp}.encrypted.json"
        mv "$_TMP_EXPORT_ENC" "$output_enc"
        _TMP_EXPORT_ENC=""

        log_success "Saved: $(basename "$output_enc")"
    fi

    # Clear master password from memory
    _MASTER_PASSWORD=""
    unset _MASTER_PASSWORD

    # ---- Rotation ----
    log_step "Rotating old backups (retention: $BW_RETENTION)..."

    if [[ "$do_age_json" == "true" ]]; then
        rotate_backups "$BW_BACKUP_PATH" "bitwarden-*.json.age" "$BW_RETENTION"
    fi
    if [[ "$do_encrypted" == "true" ]]; then
        rotate_backups "$BW_BACKUP_PATH" "bitwarden-*.encrypted.json" "$BW_RETENTION"
    fi

    # ---- Summary ----
    echo ""
    log_success "Bitwarden backup completed"

    if [[ "$do_age_json" == "true" ]]; then
        local total_age
        total_age=$(find "$BW_BACKUP_PATH" -maxdepth 1 -name "bitwarden-*.json.age" 2>/dev/null | wc -l)
        info "  JSON+age exports:       $total_age"
    fi
    if [[ "$do_encrypted" == "true" ]]; then
        local total_enc
        total_enc=$(find "$BW_BACKUP_PATH" -maxdepth 1 -name "bitwarden-*.encrypted.json" 2>/dev/null | wc -l)
        info "  Encrypted exports:      $total_enc"
    fi

    info "  Export mode: $BW_EXPORT_MODE"
    info "  Latest: bitwarden-${timestamp}"
    info "  Path: $BW_BACKUP_PATH"

    return 0
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    local config_file="$DEFAULT_CONFIG_FILE"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                config_file="$2"
                shift 2
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                error "Unknown option: $1" "exit"
                ;;
        esac
    done

    # Check dependencies
    check_deps "bw" "age" "shred" "jq"

    # Setup cleanup trap
    trap 'cleanup' EXIT INT TERM

    # Run backup
    run_backup "$config_file"
}

main "$@"
