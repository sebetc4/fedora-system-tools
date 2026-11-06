#!/bin/bash
# =============================================================================
# UI.SH - User interface with Gum + bash fallback
# =============================================================================
# Complete wrappers around Gum (https://github.com/charmbracelet/gum)
# with automatic fallback to plain bash when Gum is not installed.
#
# Available functions:
#   ui_confirm "Question?"                   # Yes/no confirmation
#   ui_choose "A" "B" "C"                    # Pick from a list
#   ui_input "Prompt" "placeholder"          # Single-line text input
#   ui_password "Prompt"                     # Silent password input
#   ui_press_enter ["message"]               # Pause (skipped when NONINTERACTIVE=1 or no terminal)
#   ui_filter "A" "B" "C"                    # Fuzzy filter a list
#   ui_table "Col1,Col2" "val1,val2" ...     # Table display
#   ui_header "TITLE"                        # Styled header with border
#   ui_banner title lines...                 # Multi-line banner
#   ui_error_banner title lines...           # Error banner
#
# Usage:
#   source "$LIB_DIR/ui.sh"
#   ui_confirm "Start the VPN?" && start_vpn
# =============================================================================

[[ -n "${_LIB_UI_LOADED:-}" ]] && return 0
readonly _LIB_UI_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/color.sh"

# =============================================================================
# CONFIRM — Yes/no confirmation
# =============================================================================
# Usage: ui_confirm "Continue?" && do_thing
# Returns 0 (yes) or 1 (no)
ui_confirm() {
    local prompt="$1"
    if has_gum; then
        gum confirm "$prompt"
    else
        local confirm
        read -r -p "$prompt [y/N] " confirm
        [[ "${confirm,,}" == "y" ]]
    fi
}

# =============================================================================
# PRESS ENTER — Pause for user to read output
# =============================================================================
# Usage: ui_press_enter
# Optional message: ui_press_enter "Review the output above"
# Skipped when NONINTERACTIVE=1, which sudo does not pass on, and when no
# terminal is there to answer, as over ssh without -t.
ui_press_enter() {
    [[ "${NONINTERACTIVE:-0}" == "1" ]] && return 0
    { : < /dev/tty; } 2>/dev/null || return 0
    local msg="${1:-Press Enter to continue...}"
    read -r -p "$msg" < /dev/tty
}

# =============================================================================
# CHOOSE — Pick from a list
# =============================================================================
# Usage: choice=$(ui_choose "Option A" "Option B" "Option C")
# With Gum options: ui_choose --header "Title" --height 10 "A" "B" "C"
ui_choose() {
    if has_gum; then
        gum choose "$@"
    else
        # Strip Gum flags for the fallback
        local items=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --header|--cursor|--cursor-prefix|--selected-prefix|--unselected-prefix|--height) shift 2 ;;
                --no-limit|--ordered) shift ;;
                --limit) shift 2 ;;
                --*) shift ;;
                *) items+=("$1"); shift ;;
            esac
        done
        local i=1 opt
        for opt in "${items[@]}"; do
            echo -e "  ${C_BOLD}$i)${C_NC} $opt" >&2
            i=$((i + 1))
        done
        local choice
        read -r -p "Choice [1-${#items[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#items[@]} ]]; then
            echo "${items[$((choice-1))]}"
        fi
    fi
}

# =============================================================================
# INPUT — Single-line text input
# =============================================================================
# Usage: value=$(ui_input "Enter IP" "192.168.1.1")
ui_input() {
    local prompt="$1" placeholder="${2:-}"
    if has_gum; then
        gum input --placeholder "$placeholder" --header "$prompt"
    else
        local value
        if [[ -n "$placeholder" ]]; then
            read -r -p "$prompt [$placeholder]: " value
            echo "${value:-$placeholder}"
        else
            read -r -p "$prompt: " value
            echo "$value"
        fi
    fi
}

# =============================================================================
# PASSWORD — Silent password input
# =============================================================================
# Usage: pass=$(ui_password "Master password")
ui_password() {
    local prompt="$1"
    if has_gum; then
        gum input --password --header "$prompt"
    else
        local value
        read -rs -p "$prompt: " value
        echo "" >&2
        echo "$value"
    fi
}

# =============================================================================
# FILTER — Fuzzy filter a list
# =============================================================================
# Usage: result=$(echo -e "item1\nitem2\nitem3" | ui_filter)
# Usage: result=$(ui_filter --header "Search:" "item1" "item2" "item3")
ui_filter() {
    # Separate gum flags from items
    local gum_opts=() items=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --header|--placeholder|--prompt|--width|--height) gum_opts+=("$1" "$2"); shift 2 ;;
            --*) gum_opts+=("$1"); shift ;;
            *) items+=("$1"); shift ;;
        esac
    done

    if has_gum; then
        if [[ ${#items[@]} -gt 0 ]]; then
            # Items from args, flags forwarded to gum
            printf '%s\n' "${items[@]}" | gum filter "${gum_opts[@]}"
        else
            # Items from stdin, flags forwarded to gum
            gum filter "${gum_opts[@]}"
        fi
    else
        # Fallback: header as prompt label if provided
        local header=""
        local i=0
        while [[ $i -lt ${#gum_opts[@]} ]]; do
            if [[ "${gum_opts[$i]}" == "--header" ]]; then
                header="${gum_opts[$((i+1))]}"
            fi
            i=$((i + 2))
        done
        local prompt="${header:-Filter}: "

        if [[ ${#items[@]} -gt 0 ]]; then
            local search
            read -r -p "$prompt" search >&2
            if [[ -n "$search" ]]; then
                printf '%s\n' "${items[@]}" | grep -i "$search" | head -1
            else
                echo "${items[0]}"
            fi
        else
            local lines=()
            while IFS= read -r line; do lines+=("$line"); done
            local search
            read -r -p "$prompt" search >&2
            if [[ -n "$search" ]]; then
                printf '%s\n' "${lines[@]}" | grep -i "$search" | head -1
            else
                echo "${lines[0]}"
            fi
        fi
    fi
}

# =============================================================================
# TABLE — Tabular data display
# =============================================================================
# Usage: ui_table "Name,Size,Date" "file1,1.2 GB,2024-01-15" "file2,500 MB,2024-02-01"
# Usage: echo "csv data" | ui_table
# Default separator is comma. Change with ui_table -s "|" ...
ui_table() {
    local separator=","
    local args=()

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--separator) separator="$2"; shift 2 ;;
            *) args+=("$1"); shift ;;
        esac
    done

    if has_gum; then
        if [[ ${#args[@]} -gt 0 ]]; then
            printf '%s\n' "${args[@]}" | gum table --separator "$separator"
        else
            gum table --separator "$separator"
        fi
    else
        # Fallback: column -t
        if [[ ${#args[@]} -gt 0 ]]; then
            # First line = bold header
            local header="${args[0]}"
            echo -e "${C_BOLD}$(echo "$header" | tr "$separator" '\t')${C_NC}"
            echo -e "${C_DIM}$(printf '─%.0s' {1..60})${C_NC}"
            for (( i=1; i<${#args[@]}; i++ )); do
                echo "${args[$i]}" | tr "$separator" '\t'
            done
        else
            # Stdin
            local first=true
            while IFS= read -r line; do
                if $first; then
                    echo -e "${C_BOLD}$(echo "$line" | tr "$separator" '\t')${C_NC}"
                    echo -e "${C_DIM}$(printf '─%.0s' {1..60})${C_NC}"
                    first=false
                else
                    echo "$line" | tr "$separator" '\t'
                fi
            done
        fi | column -t -s $'\t' 2>/dev/null || cat
    fi
}

# =============================================================================
# HEADER — Styled header (shortcut for ui_style with border)
# =============================================================================
# Usage: ui_header "TORRENT STACK READY"
ui_header() {
    local title="$1"
    echo ""
    if has_gum; then
        local hdr_args=(gum style --border rounded --padding "0 2"
            --border-foreground "${COLOR_HEADER:-${COLOR_ACCENT:-6}}")
        [[ -n "${COLOR_HEADER_TEXT:-}" ]] && hdr_args+=(--foreground "${COLOR_HEADER_TEXT}")
        "${hdr_args[@]}" "$title"
    else
        local len=${#title}
        local border_len=$((len + 6))
        local border
        border=$(printf '═%.0s' $(seq 1 "$border_len"))
        echo -e "${C_CYAN}╔${border}╗${C_NC}"
        echo -e "${C_CYAN}║${C_NC}  ${C_BOLD}${title}${C_NC}  ${C_CYAN}║${C_NC}"
        echo -e "${C_CYAN}╚${border}╝${C_NC}"
    fi
    echo ""
}

# =============================================================================
# BANNER — Multi-line banner (success, info)
# =============================================================================
# Usage: ui_banner "TORRENT STACK READY" "VPN IP: 1.2.3.4" "WebUI: http://..."
ui_banner() {
    local title="$1"; shift
    if has_gum; then
        echo ""
        gum style --border rounded --padding "1 2" --border-foreground "${COLOR_ACCENT:-6}" \
            "$(echo -e "${C_BOLD}$title${C_NC}")" "" "$@"
        echo ""
    else
        ui_header "$title"
        for line in "$@"; do
            echo -e "  $line"
        done
        echo ""
    fi
}

# =============================================================================
# ERROR BANNER — Error banner
# =============================================================================
# Usage: ui_error_banner "ERROR" "VPN not connected" "Check logs: torrent logs"
ui_error_banner() {
    local title="$1"; shift
    if has_gum; then
        echo ""
        gum style --border rounded --padding "1 2" --border-foreground "${COLOR_ERROR:-1}" \
            "$(echo -e "${C_RED}${C_BOLD}$title${C_NC}")" "" "$@"
        echo ""
    else
        echo ""
        local len=${#title}
        local border_len=$((len + 6))
        local border
        border=$(printf '═%.0s' $(seq 1 "$border_len"))
        echo -e "${C_RED}╔${border}╗${C_NC}"
        echo -e "${C_RED}║${C_NC}  ${C_BOLD}${title}${C_NC}  ${C_RED}║${C_NC}"
        echo -e "${C_RED}╚${border}╝${C_NC}"
        echo ""
        for line in "$@"; do
            echo -e "  ${C_RED}• ${line}${C_NC}"
        done
        echo ""
    fi
}
