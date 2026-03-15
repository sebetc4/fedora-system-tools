#!/bin/bash
# =============================================================================
# CONFIGURE-CLAMAV - Config-driven ClamAV daemon configuration
# =============================================================================
# Reads /etc/system-scripts/clamav.conf and applies settings to
# /etc/clamd.d/scan.conf. Supports detection profiles (standard,
# paranoid, minimal) with per-option overrides.
#
# Module: clamav
# Requires: core
# Version: 0.1.0
#
# Usage:
#   ./configure-clamav.sh    (called by setup-clamav.sh during install)
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: configure-clamav failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"

# =============================================================================
# CONFIGURATION
# =============================================================================

readonly CLAMAV_CONF="${CLAMAV_CONF:-/etc/system-scripts/clamav.conf}"
readonly CLAMD_CONF="/etc/clamd.d/scan.conf"

# =============================================================================
# PROFILE DEFAULTS
# =============================================================================

# Profile variables — set by load_profile()
P_DETECT_PUA=""
P_EXCLUDE_PUA=()
P_HEURISTIC_SCAN_PRECEDENCE=""
P_ALERT_ENCRYPTED=""
P_ALERT_ENCRYPTED_ARCHIVE=""
P_ALERT_ENCRYPTED_DOC=""
P_ALERT_OLE2_MACROS=""
P_ALERT_PHISHING_SSL=""
P_ALERT_PHISHING_CLOAK=""
P_ALERT_EXCEEDS_MAX=""

load_profile() {
    local profile="$1"
    case "$profile" in
        standard)
            P_DETECT_PUA="no"
            P_EXCLUDE_PUA=()
            P_HEURISTIC_SCAN_PRECEDENCE="yes"
            P_ALERT_ENCRYPTED="no"
            P_ALERT_ENCRYPTED_ARCHIVE="no"
            P_ALERT_ENCRYPTED_DOC="no"
            P_ALERT_OLE2_MACROS="no"
            P_ALERT_PHISHING_SSL="yes"
            P_ALERT_PHISHING_CLOAK="yes"
            P_ALERT_EXCEEDS_MAX="no"
            ;;
        paranoid)
            P_DETECT_PUA="yes"
            P_EXCLUDE_PUA=(Packed Win Andr)
            P_HEURISTIC_SCAN_PRECEDENCE="yes"
            P_ALERT_ENCRYPTED="yes"
            P_ALERT_ENCRYPTED_ARCHIVE="yes"
            P_ALERT_ENCRYPTED_DOC="yes"
            P_ALERT_OLE2_MACROS="yes"
            P_ALERT_PHISHING_SSL="yes"
            P_ALERT_PHISHING_CLOAK="yes"
            P_ALERT_EXCEEDS_MAX="yes"
            ;;
        minimal)
            P_DETECT_PUA="no"
            P_EXCLUDE_PUA=()
            P_HEURISTIC_SCAN_PRECEDENCE="no"
            P_ALERT_ENCRYPTED="no"
            P_ALERT_ENCRYPTED_ARCHIVE="no"
            P_ALERT_ENCRYPTED_DOC="no"
            P_ALERT_OLE2_MACROS="no"
            P_ALERT_PHISHING_SSL="no"
            P_ALERT_PHISHING_CLOAK="no"
            P_ALERT_EXCEEDS_MAX="no"
            ;;
        *)
            error "Unknown scan profile: $profile (use: standard, paranoid, minimal)" "exit"
            ;;
    esac
}

# Return override if non-empty, otherwise profile default
resolve() {
    local override="$1"
    local default="$2"
    if [[ -n "$override" ]]; then
        echo "$override"
    else
        echo "$default"
    fi
}

# =============================================================================
# CLAMD.CONF HELPERS
# =============================================================================

set_option() {
    local option="$1"
    local value="$2"
    sed -i "/^#*${option}/d" "$CLAMD_CONF"
    echo "${option} ${value}" >> "$CLAMD_CONF"
}

# =============================================================================
# PRE-FLIGHT
# =============================================================================

if [[ ! -f "$CLAMAV_CONF" ]]; then
    error "Config file not found: $CLAMAV_CONF" "exit"
fi

if [[ ! -f "$CLAMD_CONF" ]]; then
    error "ClamAV daemon config not found: $CLAMD_CONF" "exit"
fi

# =============================================================================
# LOAD CONFIG
# =============================================================================

# Defaults before sourcing
SCAN_PROFILE="standard"
DETECT_PUA=""
EXCLUDE_PUA=()
HEURISTIC_SCAN_PRECEDENCE=""
ALERT_ENCRYPTED=""
ALERT_ENCRYPTED_ARCHIVE=""
ALERT_ENCRYPTED_DOC=""
ALERT_OLE2_MACROS=""
ALERT_PHISHING_SSL=""
ALERT_PHISHING_CLOAK=""
ALERT_EXCEEDS_MAX=""
MAX_THREADS="auto"
MAX_QUEUE="200"
IDLE_TIMEOUT="30"
CONCURRENT_DB_RELOAD="yes"
MAX_SCAN_SIZE="400M"
MAX_FILE_SIZE="100M"
MAX_RECURSION="20"
MAX_FILES="15000"
MAX_DIRECTORY_RECURSION="20"
LOG_FILE="/var/log/clamav/clamd.log"
LOG_FILE_MAX_SIZE="50M"

# shellcheck source=/dev/null
source "$CLAMAV_CONF"

# =============================================================================
# RESOLVE PROFILE + OVERRIDES
# =============================================================================

load_profile "$SCAN_PROFILE"

R_DETECT_PUA="$(resolve "$DETECT_PUA" "$P_DETECT_PUA")"
R_HEURISTIC_SCAN_PRECEDENCE="$(resolve "$HEURISTIC_SCAN_PRECEDENCE" "$P_HEURISTIC_SCAN_PRECEDENCE")"
R_ALERT_ENCRYPTED="$(resolve "$ALERT_ENCRYPTED" "$P_ALERT_ENCRYPTED")"
R_ALERT_ENCRYPTED_ARCHIVE="$(resolve "$ALERT_ENCRYPTED_ARCHIVE" "$P_ALERT_ENCRYPTED_ARCHIVE")"
R_ALERT_ENCRYPTED_DOC="$(resolve "$ALERT_ENCRYPTED_DOC" "$P_ALERT_ENCRYPTED_DOC")"
R_ALERT_OLE2_MACROS="$(resolve "$ALERT_OLE2_MACROS" "$P_ALERT_OLE2_MACROS")"
R_ALERT_PHISHING_SSL="$(resolve "$ALERT_PHISHING_SSL" "$P_ALERT_PHISHING_SSL")"
R_ALERT_PHISHING_CLOAK="$(resolve "$ALERT_PHISHING_CLOAK" "$P_ALERT_PHISHING_CLOAK")"
R_ALERT_EXCEEDS_MAX="$(resolve "$ALERT_EXCEEDS_MAX" "$P_ALERT_EXCEEDS_MAX")"

# ExcludePUA: use override if non-empty array, otherwise profile default
if [[ ${#EXCLUDE_PUA[@]} -gt 0 ]]; then
    R_EXCLUDE_PUA=("${EXCLUDE_PUA[@]}")
else
    R_EXCLUDE_PUA=("${P_EXCLUDE_PUA[@]}")
fi

# =============================================================================
# CALCULATE THREADS
# =============================================================================

if [[ "$MAX_THREADS" == "auto" ]]; then
    MAX_THREADS=$(( $(nproc) / 2 ))
    [[ $MAX_THREADS -lt 4 ]] && MAX_THREADS=4
    [[ $MAX_THREADS -gt 16 ]] && MAX_THREADS=16
fi

# =============================================================================
# BACKUP
# =============================================================================

BACKUP="${CLAMD_CONF}.backup-$(date +%Y%m%d-%H%M%S)"
cp "$CLAMD_CONF" "$BACKUP"
info "Backup: $BACKUP"

# Disable Example line
sed -i '/^Example$/d' "$CLAMD_CONF"

# =============================================================================
# DETECT CLAMAV USER/GROUP
# =============================================================================

CLAM_USER=$(grep "^User " "$CLAMD_CONF" 2>/dev/null | awk '{print $2}')
if [[ -z "$CLAM_USER" ]]; then
    CLAM_USER="clamscan"
fi

CLAM_GROUP="virusgroup"

if ! id "$CLAM_USER" &>/dev/null; then
    error "ClamAV user '$CLAM_USER' not found. Install ClamAV first." "exit"
fi

if ! getent group "$CLAM_GROUP" &>/dev/null; then
    if getent group "clamav" &>/dev/null; then
        CLAM_GROUP="clamav"
    elif getent group "clamupdate" &>/dev/null; then
        CLAM_GROUP="clamupdate"
    else
        error "No ClamAV group found. Install ClamAV first." "exit"
    fi
fi

info "User: $CLAM_USER, Group: $CLAM_GROUP"

# =============================================================================
# APPLY CONFIGURATION
# =============================================================================

echo ""
echo -e "${C_BOLD}${C_CYAN}=== ClamAV Configuration (profile: $SCAN_PROFILE) ===${C_NC}"
echo ""

# --- Socket ---
mkdir -p /run/clamd.scan
chown "$CLAM_USER:$CLAM_GROUP" /run/clamd.scan

set_option "LocalSocket" "/run/clamd.scan/clamd.sock"
set_option "LocalSocketGroup" "$CLAM_GROUP"
set_option "LocalSocketMode" "666"

# --- Performance ---
echo -e "${C_BOLD}Performance${C_NC}"
echo -e "  MaxThreads: $MAX_THREADS, MaxQueue: $MAX_QUEUE"
set_option "MaxThreads" "$MAX_THREADS"
set_option "MaxQueue" "$MAX_QUEUE"
set_option "IdleTimeout" "$IDLE_TIMEOUT"

# --- Database ---
set_option "ConcurrentDatabaseReload" "$CONCURRENT_DB_RELOAD"
set_option "SelfCheck" "600"
set_option "DatabaseDirectory" "/var/lib/clamav"
set_option "OfficialDatabaseOnly" "no"

# --- Logging ---
set_option "LogFile" "$LOG_FILE"
set_option "LogTime" "yes"
set_option "LogFileMaxSize" "$LOG_FILE_MAX_SIZE"

# --- File type scanning (always enabled) ---
set_option "ScanArchive" "yes"
set_option "ScanPDF" "yes"
set_option "ScanOLE2" "yes"
set_option "ScanHTML" "yes"
set_option "ScanPE" "yes"
set_option "ScanMail" "yes"
set_option "ScanELF" "yes"
set_option "ScanSWF" "yes"

# --- Heuristic analysis ---
echo -e "${C_BOLD}Detection${C_NC}"
echo -e "  DetectPUA: $R_DETECT_PUA, HeuristicScanPrecedence: $R_HEURISTIC_SCAN_PRECEDENCE"
set_option "DetectPUA" "$R_DETECT_PUA"
set_option "HeuristicAlerts" "yes"
set_option "HeuristicScanPrecedence" "$R_HEURISTIC_SCAN_PRECEDENCE"

# --- PUA exclusions (only when DetectPUA is enabled) ---
# Remove all existing ExcludePUA lines first
sed -i '/^#*ExcludePUA/d' "$CLAMD_CONF"
if [[ "$R_DETECT_PUA" == "yes" && ${#R_EXCLUDE_PUA[@]} -gt 0 ]]; then
    echo -e "  ExcludePUA: ${R_EXCLUDE_PUA[*]}"
    for category in "${R_EXCLUDE_PUA[@]}"; do
        echo "ExcludePUA $category" >> "$CLAMD_CONF"
    done
fi

# --- Phishing ---
set_option "PhishingSignatures" "yes"
set_option "PhishingScanURLs" "yes"
set_option "AlertPhishingSSLMismatch" "$R_ALERT_PHISHING_SSL"
set_option "AlertPhishingCloak" "$R_ALERT_PHISHING_CLOAK"

# --- Alerts ---
echo -e "  Alerts: Encrypted=$R_ALERT_ENCRYPTED, OLE2Macros=$R_ALERT_OLE2_MACROS, ExceedsMax=$R_ALERT_EXCEEDS_MAX"
set_option "AlertEncrypted" "$R_ALERT_ENCRYPTED"
set_option "AlertEncryptedArchive" "$R_ALERT_ENCRYPTED_ARCHIVE"
set_option "AlertEncryptedDoc" "$R_ALERT_ENCRYPTED_DOC"
set_option "AlertOLE2Macros" "$R_ALERT_OLE2_MACROS"
set_option "AlertExceedsMax" "$R_ALERT_EXCEEDS_MAX"

# --- Scan limits ---
set_option "CrossFilesystems" "yes"
set_option "MaxDirectoryRecursion" "$MAX_DIRECTORY_RECURSION"
set_option "MaxScanSize" "$MAX_SCAN_SIZE"
set_option "MaxFileSize" "$MAX_FILE_SIZE"
set_option "MaxRecursion" "$MAX_RECURSION"
set_option "MaxFiles" "$MAX_FILES"

# =============================================================================
# TMPFILES.D
# =============================================================================

sed -e "s|__CLAM_USER__|$CLAM_USER|g" -e "s|__CLAM_GROUP__|$CLAM_GROUP|g" \
    "$SCRIPT_DIR/../../templates/clamd-tmpfiles.conf.tpl" \
    > /etc/tmpfiles.d/clamd.scan.conf

systemd-tmpfiles --create /etc/tmpfiles.d/clamd.scan.conf 2>/dev/null || true

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo -e "${C_BOLD}${C_CYAN}=== Configuration applied ===${C_NC}"
echo ""
echo -e "  Profile:     ${C_BOLD}$SCAN_PROFILE${C_NC}"
echo -e "  User/Group:  $CLAM_USER:$CLAM_GROUP"
echo -e "  MaxThreads:  $MAX_THREADS"
echo -e "  Socket:      /run/clamd.scan/clamd.sock"
echo -e "  Config from: $CLAMAV_CONF"
echo ""
