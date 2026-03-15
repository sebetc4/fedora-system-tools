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
#   ui_write "Prompt" "placeholder"          # Multi-line text input
#   ui_file "/path/to/dir"                   # File picker
#   ui_filter "A" "B" "C"                    # Fuzzy filter a list
#   ui_spin "Title..." cmd args              # Spinner while running a command
#   ui_table "Col1,Col2" "val1,val2" ...     # Table display
#   ui_pager "content" or cmd | ui_pager     # Scrollable pager
#   ui_log "level" "message"                 # Styled log with level
#   ui_format "text"                         # Text formatting (markdown, etc.)
#   ui_join "horizontal|vertical" args...    # Join text blocks
#   ui_style "text"                          # Style text
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
ui_press_enter() {
    [[ "${NONINTERACTIVE:-0}" == "1" ]] && return 0
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
        local i=1
        for opt in "${items[@]}"; do
            echo -e "  ${C_BOLD}$i)${C_NC} $opt" >&2
            ((i++))
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
# WRITE — Multi-line text input
# =============================================================================
# Usage: text=$(ui_write "Enter a description")
# Usage: text=$(ui_write "Notes" "Placeholder..." 5)
ui_write() {
    local prompt="${1:-}" placeholder="${2:-}" height="${3:-5}"
    if has_gum; then
        local args=(gum write)
        [[ -n "$prompt" ]] && args+=(--header "$prompt")
        [[ -n "$placeholder" ]] && args+=(--placeholder "$placeholder")
        args+=(--height "$height")
        "${args[@]}"
    else
        [[ -n "$prompt" ]] && echo -e "${C_BOLD}$prompt${C_NC} (Ctrl+D to finish):" >&2
        local text=""
        while IFS= read -r line; do
            text+="$line"$'\n'
        done
        echo "$text"
    fi
}

# =============================================================================
# FILE — Pick a file from a directory
# =============================================================================
# Usage: file=$(ui_file "/path/to/dir")
# Usage: file=$(ui_file "/path/to/dir" "*.iso")
ui_file() {
    local dir="${1:-.}" filter="${2:-}"
    if has_gum; then
        local args=(gum file "$dir")
        [[ -n "$filter" ]] && args+=(--file)
        "${args[@]}"
    else
        # Fallback: numbered file list
        local files=()
        if [[ -n "$filter" ]]; then
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$dir" -maxdepth 3 -name "$filter" -print0 2>/dev/null | sort -z)
        else
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$dir" -maxdepth 1 -mindepth 1 -print0 2>/dev/null | sort -z)
        fi

        if [[ ${#files[@]} -eq 0 ]]; then
            echo "" >&2
            return 1
        fi

        local i=1
        for f in "${files[@]}"; do
            local name
            name=$(basename "$f")
            [[ -d "$f" ]] && name="$name/"
            echo -e "  ${C_BOLD}$i)${C_NC} $name" >&2
            ((i++))
        done

        local choice
        read -r -p "File [1-${#files[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#files[@]} ]]; then
            echo "${files[$((choice-1))]}"
        fi
    fi
}

# =============================================================================
# FILTER — Fuzzy filter a list
# =============================================================================
# Usage: result=$(echo -e "item1\nitem2\nitem3" | ui_filter)
# Usage: result=$(ui_filter --header "Search:" "item1" "item2" "item3")
ui_filter() {
    if has_gum; then
        if [[ $# -gt 0 ]]; then
            # Args passed directly
            printf '%s\n' "$@" | gum filter
        else
            # Stdin (pipe)
            gum filter
        fi
    else
        if [[ $# -gt 0 ]]; then
            # Strip Gum flags
            local items=()
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --header|--placeholder|--prompt|--width|--height) shift 2 ;;
                    --*) shift ;;
                    *) items+=("$1"); shift ;;
                esac
            done
            local search
            read -r -p "Filter: " search >&2
            if [[ -n "$search" ]]; then
                printf '%s\n' "${items[@]}" | grep -i "$search" | head -1
            else
                echo "${items[0]}"
            fi
        else
            # Stdin
            local lines=()
            while IFS= read -r line; do
                lines+=("$line")
            done
            local search
            read -r -p "Filter: " search >&2
            if [[ -n "$search" ]]; then
                printf '%s\n' "${lines[@]}" | grep -i "$search" | head -1
            else
                echo "${lines[0]}"
            fi
        fi
    fi
}

# =============================================================================
# SPIN — Spinner while running a command
# =============================================================================
# Usage: ui_spin "Connecting to VPN..." wait_vpn_ready
# The command runs in a subprocess while the spinner displays
ui_spin() {
    local title="$1"; shift
    if has_gum; then
        gum spin --spinner dot --title "$title" -- "$@"
    else
        echo -n "$title "
        "$@" &
        local pid=$!
        local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        while kill -0 "$pid" 2>/dev/null; do
            for (( i=0; i<${#chars}; i++ )); do
                echo -ne "\r$title ${chars:$i:1} "
                sleep 0.1
                kill -0 "$pid" 2>/dev/null || break
            done
        done
        wait "$pid"
        local rc=$?
        echo -e "\r$title done."
        return $rc
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
# PAGER — Scrollable content display
# =============================================================================
# Usage: ui_pager "long content..."
# Usage: cmd_with_long_output | ui_pager
# Usage: ui_pager --file /path/to/file
ui_pager() {
    if has_gum; then
        if [[ "${1:-}" == "--file" && -f "${2:-}" ]]; then
            gum pager < "$2"
        elif [[ $# -gt 0 && "$1" != "--"* ]]; then
            echo "$1" | gum pager
        else
            gum pager
        fi
    else
        # Fallback: less if available, then more, then cat
        local pager_cmd="cat"
        command -v less &>/dev/null && pager_cmd="less -R"
        command -v more &>/dev/null && [[ "$pager_cmd" == "cat" ]] && pager_cmd="more"

        if [[ "${1:-}" == "--file" && -f "${2:-}" ]]; then
            $pager_cmd "$2"
        elif [[ $# -gt 0 && "$1" != "--"* ]]; then
            echo "$1" | $pager_cmd
        else
            $pager_cmd
        fi
    fi
}

# =============================================================================
# LOG — Styled log messages with level
# =============================================================================
# Usage: ui_log info "Operation started"
# Usage: ui_log warn "Low disk space"
# Usage: ui_log error "Connection failed"
# Usage: ui_log debug "Variable=$var"
# Levels: debug, info, warn, error, fatal
ui_log() {
    local level="$1"; shift
    local message="$*"
    local time_str
    time_str=$(date '+%H:%M:%S')

    if has_gum; then
        gum log --time datetime --level "$level" "$message"
    else
        local prefix
        case "$level" in
            debug) prefix="${C_DIM}DBG${C_NC}" ;;
            info)  prefix="${C_BLUE}INF${C_NC}" ;;
            warn)  prefix="${C_YELLOW}WRN${C_NC}" ;;
            error) prefix="${C_RED}ERR${C_NC}" ;;
            fatal) prefix="${C_RED}${C_BOLD}FTL${C_NC}" ;;
            *)     prefix="${C_DIM}???${C_NC}" ;;
        esac
        echo -e "$time_str $prefix $message"
    fi
}

# =============================================================================
# FORMAT — Text formatting (markdown, template, emoji, code)
# =============================================================================
# Usage: ui_format "# Title\n\nText with **bold** and *italic*"
# Usage: ui_format --type code "echo hello world"
# Types: markdown (default), code, template, emoji
ui_format() {
    local type="markdown"
    local text=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type|-t) type="$2"; shift 2 ;;
            *) text="$1"; shift ;;
        esac
    done

    if has_gum; then
        echo -e "$text" | gum format --type "$type"
    else
        case "$type" in
            code)
                # Fallback: indentation + dim
                echo -e "${C_DIM}"
                echo -e "$text" | while IFS= read -r line; do
                    echo "  $line"
                done
                echo -e "${C_NC}"
                ;;
            emoji)
                # No conversion, print as-is
                echo -e "$text"
                ;;
            *)
                # Markdown fallback: basic bold with ** and headers with #
                echo -e "$text" | while IFS= read -r line; do
                    if [[ "$line" =~ ^###\  ]]; then
                        echo -e "${C_BOLD}${line#### }${C_NC}"
                    elif [[ "$line" =~ ^##\  ]]; then
                        echo -e "${C_BOLD}${line### }${C_NC}"
                    elif [[ "$line" =~ ^#\  ]]; then
                        echo -e "${C_BOLD}${C_CYAN}${line## }${C_NC}"  # H1 → section style (cyan bold)
                    else
                        echo "$line"
                    fi
                done
                ;;
        esac
    fi
}

# =============================================================================
# JOIN — Join text blocks
# =============================================================================
# Usage: ui_join horizontal "$(cmd1)" "$(cmd2)"
# Usage: ui_join vertical "block1" "block2"
ui_join() {
    local direction="${1:-vertical}"; shift
    if has_gum; then
        local args=()
        case "$direction" in
            horizontal|h) args+=(--horizontal) ;;
            vertical|v)   args+=(--vertical) ;;
        esac
        gum join "${args[@]}" "$@"
    else
        case "$direction" in
            horizontal|h)
                # Fallback: side-by-side with paste
                if [[ $# -eq 2 ]]; then
                    paste <(echo "$1") <(echo "$2")
                else
                    # More than 2: concatenate with tab
                    local first=true
                    for block in "$@"; do
                        if $first; then
                            echo -n "$block"
                            first=false
                        else
                            echo -n "  $block"
                        fi
                    done
                    echo ""
                fi
                ;;
            *)
                # Vertical: just concatenate
                for block in "$@"; do
                    echo "$block"
                done
                ;;
        esac
    fi
}

# =============================================================================
# STYLE — Style text with borders, colors, padding
# =============================================================================
# Usage: ui_style "Important text"
# Usage: ui_style --border rounded --foreground 6 --bold "Message"
# Passes args directly to gum style, basic fallback in bash
ui_style() {
    if has_gum; then
        gum style "$@"
    else
        # Extract text (last arg without --)
        # shellcheck disable=SC2034  # fg is parsed for API compat but unused in fallback
        local text="" bold=false fg=""
        local has_border=false
        # shellcheck disable=SC2034
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --border) has_border=true; shift 2 ;;
                --border-foreground|--border-background) shift 2 ;;
                --padding|--margin|--width|--height|--align) shift 2 ;;
                --foreground) fg="$2"; shift 2 ;;
                --background) shift 2 ;;
                --bold) bold=true; shift ;;
                --italic|--strikethrough|--underline|--faint) shift ;;
                *) text="$1"; shift ;;
            esac
        done

        local out="$text"
        $bold && out="${C_BOLD}${out}${C_NC}"

        if $has_border; then
            local len=${#text}
            local border_len=$((len + 4))
            local border
            border=$(printf '─%.0s' $(seq 1 "$border_len"))
            echo "╭${border}╮"
            echo "│  ${out}  │"
            echo "╰${border}╯"
        else
            echo -e "$out"
        fi
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
        local body=""
        for line in "$@"; do
            body+="$line\n"
        done
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
