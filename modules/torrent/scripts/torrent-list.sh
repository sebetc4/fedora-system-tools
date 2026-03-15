#!/bin/bash
# =============================================================================
# TORRENT-LIST - List downloaded torrent files with status
# =============================================================================
# Lists files in the torrent download directory with their scan status.
#
# Module: torrent
# Requires: core, config, format, ui
# Version: 0.1.0
#
# Usage:
#   torrent-list [options]
# =============================================================================

set -euo pipefail

# ===================
# Load shared library
# ===================
readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/format.sh"
source "$LIB_DIR/ui.sh"

# ===================
# Configuration
# ===================
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME

check_root
load_config
# shellcheck disable=SC2153  # DOWNLOAD_DIR sourced from paths.conf via load_config
TORRENT_DIR="$DOWNLOAD_DIR/torrents"
DOWNLOADS_DIR="$TORRENT_DIR"
readonly DOWNLOADS_DIR
readonly PENDING_DIR="/var/quarantine/pending"
readonly QUARANTINE_DIR="/var/quarantine/confirmed"

# ===================
# Functions
# ===================
show_help() {
    cat << EOF
Usage: $SCRIPT_NAME [options]

List torrent downloads with their scan status.

OPTIONS:
  -a, --all       Include files in pending review and quarantine
  -p, --pending   Show only files pending review
  -s, --simple    Simple output (for scripting)
  -h, --help      Show this help message

STATUS ICONS:
  ✅  Clean (scanned, no threats)
  ⚠️  Pending review (needs user decision)
  🔒  Quarantined (confirmed threat)
  ❓  Unknown (not yet scanned)

EXAMPLES:
  $SCRIPT_NAME              # List downloads
  $SCRIPT_NAME --all        # Include pending and quarantined
  $SCRIPT_NAME --pending    # Only pending files

EOF
}

get_status() {
    local name="$1"

    if [[ -d "$PENDING_DIR" && -f "$PENDING_DIR/$name" ]]; then
        echo "pending"
        return
    fi

    if [[ -d "$QUARANTINE_DIR" && -f "$QUARANTINE_DIR/$name" ]]; then
        echo "quarantine"
        return
    fi

    # Without clamav, we can't determine scan status
    if [[ ! -d "$PENDING_DIR" && ! -d "$QUARANTINE_DIR" ]]; then
        echo "unknown"
        return
    fi

    echo "clean"
}

list_downloads() {
    local show_all="$1"
    local show_pending="$2"
    local simple="$3"

    local total_files=0
    local total_size=0

    # Collect all files
    declare -A files_data

    # Downloads directory
    if [[ -d "$DOWNLOADS_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            if [[ -e "$entry" ]]; then
                local name size date status
                name=$(basename "$entry")

                if [[ -d "$entry" ]]; then
                    size=$(du -sb "$entry" 2>/dev/null | cut -f1)
                    name="$name/"
                else
                    size=$(stat -c %s "$entry" 2>/dev/null || echo "0")
                fi

                date=$(stat -c %Y "$entry" 2>/dev/null || echo "0")
                status=$(get_status "$name")

                if [[ "$show_pending" == "true" && "$status" != "pending" ]]; then
                    continue
                fi

                files_data["$name"]="$size|$date|$status|downloads"
                ((total_files++)) || true
                ((total_size+=size)) || true
            fi
        done < <(find "$DOWNLOADS_DIR" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
    fi

    # Pending directory (if --all)
    if [[ "$show_all" == "true" || "$show_pending" == "true" ]] && [[ -d "$PENDING_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            if [[ -f "$entry" && "${entry,,}" == *.iso ]]; then
                local name size date
                name=$(basename "$entry")
                size=$(stat -c %s "$entry" 2>/dev/null || echo "0")
                date=$(stat -c %Y "$entry" 2>/dev/null || echo "0")
                files_data["$name"]="$size|$date|pending|pending_dir"
                ((total_files++)) || true
                ((total_size+=size)) || true
            fi
        done < <(find "$PENDING_DIR" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
    fi

    # Quarantine directory (if --all)
    if [[ "$show_all" == "true" ]] && [[ -d "$QUARANTINE_DIR" ]]; then
        while IFS= read -r -d '' entry; do
            if [[ -f "$entry" ]]; then
                local name size date
                name=$(basename "$entry")
                size=$(stat -c %s "$entry" 2>/dev/null || echo "0")
                date=$(stat -c %Y "$entry" 2>/dev/null || echo "0")
                files_data["$name"]="$size|$date|quarantine|quarantine_dir"
                ((total_files++)) || true
                ((total_size+=size)) || true
            fi
        done < <(find "$QUARANTINE_DIR" -maxdepth 1 -type f -print0 2>/dev/null | sort -z)
    fi

    if [[ ${#files_data[@]} -eq 0 ]]; then
        if [[ "$simple" != "true" ]]; then
            echo ""
            warn "Aucun fichier trouvé dans $DOWNLOADS_DIR"
            echo ""
        fi
        return 0
    fi

    # Simple output
    if [[ "$simple" == "true" ]]; then
        local i=1
        for name in "${!files_data[@]}"; do
            IFS='|' read -r size date status location <<< "${files_data[$name]}"
            echo "$i|$name|$size|$status|$location"
            ((i++)) || true
        done
        return 0
    fi

    # Pretty output
    echo ""
    ui_header "📁 FICHIERS TÉLÉCHARGÉS"

    printf "  %b%-3s %-40s %10s %12s %s%b\n" "$C_BOLD" "#" "Nom" "Taille" "Date" "État" "$C_NC"
    printf "  %b─────────────────────────────────────────────────────────────────%b\n" "$C_DIM" "$C_NC"

    local i=1
    # Sort by date (most recent first) — use while read to handle spaces in filenames
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        IFS='|' read -r size date status location <<< "${files_data[$name]}"

        local status_icon size_fmt date_fmt
        case "$status" in
            clean)      status_icon="${C_GREEN}✅${C_NC}" ;;
            pending)    status_icon="${C_YELLOW}⚠️${C_NC} " ;;
            quarantine) status_icon="${C_RED}🔒${C_NC}" ;;
            *)          status_icon="${C_DIM}❓${C_NC}" ;;
        esac

        size_fmt=$(format_size "$size")
        date_fmt=$(format_date "$date")

        local display_name
        display_name=$(truncate_name "$name" 38)

        printf "  %b%-3s%b %-40s %10s %12s %b\n" "$C_BOLD" "$i" "$C_NC" "$display_name" "$size_fmt" "$date_fmt" "$status_icon"
        ((i++)) || true
    done < <(for k in "${!files_data[@]}"; do echo "$k|${files_data[$k]}"; done | sort -t'|' -k3 -rn | cut -d'|' -f1)

    echo ""
    echo -e "  ${C_DIM}Total: $total_files fichier(s), $(format_size $total_size)${C_NC}"
    echo ""
    local cmds="${C_CYAN}torrent move <#>${C_NC} | ${C_CYAN}torrent export${C_NC}"
    if command -v quarantine &>/dev/null; then
        cmds+=" | ${C_CYAN}sudo quarantine${C_NC}"
    fi
    echo -e "  ${C_DIM}Commandes: ${cmds}${C_NC}"
    echo ""
}

# ===================
# Main
# ===================
main() {
    local show_all=false
    local show_pending=false
    local simple=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -a|--all)
                show_all=true
                shift
                ;;
            -p|--pending)
                show_pending=true
                shift
                ;;
            -s|--simple)
                simple=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for more information."
                exit 1
                ;;
        esac
    done

    list_downloads "$show_all" "$show_pending" "$simple"
}

main "$@"
