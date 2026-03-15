#!/bin/bash
# =============================================================================
# COLOR.SH - Customizable UI color theme
# =============================================================================
# Loads color configuration and exports GUM_* environment variables for
# consistent theming across all interactive scripts.
#
# Config lookup order:
#   1. ~/.config/system-scripts/color.conf  (user override)
#   2. /etc/system-scripts/color.conf       (system default)
#
# Env override: COLOR_CONF=/path/to/color.conf (skips lookup, uses only this)
#
# Usage: source "$LIB_DIR/color.sh"
#
# Requires: core
# Version: 0.1.0
# =============================================================================

[[ -n "${_LIB_COLOR_LOADED:-}" ]] && return 0
readonly _LIB_COLOR_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"

# ===================
# Defaults
# ===================

# Primary accent color (cursors, selections, banners)
# shellcheck disable=SC2034  # COLOR_* vars used by ui.sh
COLOR_ACCENT="${COLOR_ACCENT:-"#4f9872"}"
# Header border color (empty = inherit from accent)
# shellcheck disable=SC2034
COLOR_HEADER="#4f9872"
# Header text color (empty = gum/terminal default)
# shellcheck disable=SC2034
COLOR_HEADER_TEXT="#ECEEEC"
# Selection title color (gum choose --header text, empty = terminal default)
# shellcheck disable=SC2034
COLOR_SELECTION_TITLE="#4f9872"
# Error accent color (error borders)
# shellcheck disable=SC2034
COLOR_ERROR="${COLOR_ERROR:-1}"

# Per-component overrides (empty = inherit from accent)
_CLR_CHOOSE_CURSOR_FG="#CBB99F"
_CLR_CHOOSE_SELECTED_FG="#CBB99F"
_CLR_INPUT_PROMPT_FG=""
_CLR_INPUT_CURSOR_FG=""
_CLR_FILTER_INDICATOR_FG=""
_CLR_FILTER_MATCH_FG=""
_CLR_CONFIRM_SELECTED_FG=""
_CLR_SPIN_SPINNER_FG=""

# Terminal color overrides (empty = keep core.sh defaults)
_CLR_TERM_RED=""
_CLR_TERM_GREEN=""
_CLR_TERM_YELLOW=""
_CLR_TERM_CYAN=""
_CLR_TERM_BLUE=""
_CLR_TERM_MAGENTA=""

# ===================
# Config loader
# ===================

_color_load_conf() {
    local conf_file="$1"
    [[ ! -f "$conf_file" ]] && return 0

    local line key value
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        # Parse KEY=VALUE
        key="${line%%=*}"
        value="${line#*=}"
        key="${key## }"; key="${key%% }"
        value="${value## }"; value="${value%% }"

        case "$key" in
            accent)                      COLOR_ACCENT="$value" ;;
            header_border)               COLOR_HEADER="$value" ;;
            header_text)                 COLOR_HEADER_TEXT="$value" ;;
            selection_title)              COLOR_SELECTION_TITLE="$value" ;;
            error)                       COLOR_ERROR="$value" ;;
            choose_cursor_foreground)    _CLR_CHOOSE_CURSOR_FG="$value" ;;
            choose_selected_foreground)  _CLR_CHOOSE_SELECTED_FG="$value" ;;
            input_prompt_foreground)     _CLR_INPUT_PROMPT_FG="$value" ;;
            input_cursor_foreground)     _CLR_INPUT_CURSOR_FG="$value" ;;
            filter_indicator_foreground) _CLR_FILTER_INDICATOR_FG="$value" ;;
            filter_match_foreground)     _CLR_FILTER_MATCH_FG="$value" ;;
            confirm_selected_foreground) _CLR_CONFIRM_SELECTED_FG="$value" ;;
            spin_spinner_foreground)     _CLR_SPIN_SPINNER_FG="$value" ;;
            term_red)                    _CLR_TERM_RED="$value" ;;
            term_green)                  _CLR_TERM_GREEN="$value" ;;
            term_yellow)                 _CLR_TERM_YELLOW="$value" ;;
            term_cyan)                   _CLR_TERM_CYAN="$value" ;;
            term_blue)                   _CLR_TERM_BLUE="$value" ;;
            term_magenta)                _CLR_TERM_MAGENTA="$value" ;;
        esac
    done < "$conf_file"
}

# Resolve user config path (accounts for sudo)
_color_user_conf() {
    local home="$HOME"
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
        home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 2>/dev/null)" || home="$HOME"
    fi
    echo "$home/.config/system-scripts/color.conf"
}

# Load system config, then user overrides
if [[ -n "${COLOR_CONF:-}" ]]; then
    _color_load_conf "$COLOR_CONF"
else
    _color_load_conf "/etc/system-scripts/color.conf"
    _color_load_conf "$(_color_user_conf)"
fi

# ===================
# Export GUM env vars
# ===================

_color_apply_gum() {
    has_gum || return 0

    [[ -n "${COLOR_SELECTION_TITLE:-}" ]] && export GUM_CHOOSE_HEADER_FOREGROUND="$COLOR_SELECTION_TITLE"
    export GUM_CHOOSE_CURSOR_FOREGROUND="${_CLR_CHOOSE_CURSOR_FG:-$COLOR_ACCENT}"
    export GUM_CHOOSE_SELECTED_FOREGROUND="${_CLR_CHOOSE_SELECTED_FG:-$COLOR_ACCENT}"
    export GUM_INPUT_PROMPT_FOREGROUND="${_CLR_INPUT_PROMPT_FG:-$COLOR_ACCENT}"
    export GUM_INPUT_CURSOR_FOREGROUND="${_CLR_INPUT_CURSOR_FG:-$COLOR_ACCENT}"
    export GUM_FILTER_INDICATOR_FOREGROUND="${_CLR_FILTER_INDICATOR_FG:-$COLOR_ACCENT}"
    export GUM_FILTER_MATCH_FOREGROUND="${_CLR_FILTER_MATCH_FG:-$COLOR_ACCENT}"
    export GUM_CONFIRM_SELECTED_FOREGROUND="${_CLR_CONFIRM_SELECTED_FG:-$COLOR_ACCENT}"
    export GUM_SPIN_SPINNER_FOREGROUND="${_CLR_SPIN_SPINNER_FG:-$COLOR_ACCENT}"
}

_color_apply_gum

# ===================
# Apply terminal color overrides
# ===================

if [[ -t 1 ]]; then
    # shellcheck disable=SC2034  # C_* vars used by scripts sourcing this lib
    [[ -n "$_CLR_TERM_RED" ]]     && C_RED="$_CLR_TERM_RED"
    # shellcheck disable=SC2034
    [[ -n "$_CLR_TERM_GREEN" ]]   && C_GREEN="$_CLR_TERM_GREEN"
    # shellcheck disable=SC2034
    [[ -n "$_CLR_TERM_YELLOW" ]]  && C_YELLOW="$_CLR_TERM_YELLOW"
    # shellcheck disable=SC2034
    [[ -n "$_CLR_TERM_CYAN" ]]    && C_CYAN="$_CLR_TERM_CYAN"
    # shellcheck disable=SC2034
    [[ -n "$_CLR_TERM_BLUE" ]]    && C_BLUE="$_CLR_TERM_BLUE"
    # shellcheck disable=SC2034
    [[ -n "$_CLR_TERM_MAGENTA" ]] && C_MAGENTA="$_CLR_TERM_MAGENTA"
fi

# ===================
# Reload function
# ===================
# Call after modifying color.conf to re-apply theme in current session.

color_reload() {
    # Reset defaults
    # shellcheck disable=SC2034  # COLOR_* vars used by scripts sourcing this lib
    COLOR_ACCENT="#4f9872"
    # shellcheck disable=SC2034
    COLOR_HEADER="#4f9872"
    # shellcheck disable=SC2034
    COLOR_HEADER_TEXT="#ECEEEC"
    # shellcheck disable=SC2034
    COLOR_SELECTION_TITLE="#4f9872"
    COLOR_ERROR=1
    _CLR_CHOOSE_CURSOR_FG="#CBB99F"
    _CLR_CHOOSE_SELECTED_FG="#CBB99F"
    _CLR_INPUT_PROMPT_FG=""
    _CLR_INPUT_CURSOR_FG=""
    _CLR_FILTER_INDICATOR_FG=""
    _CLR_FILTER_MATCH_FG=""
    _CLR_CONFIRM_SELECTED_FG=""
    _CLR_SPIN_SPINNER_FG=""
    _CLR_TERM_RED=""
    _CLR_TERM_GREEN=""
    _CLR_TERM_YELLOW=""
    _CLR_TERM_CYAN=""
    _CLR_TERM_BLUE=""
    _CLR_TERM_MAGENTA=""

    # Reload config
    if [[ -n "${COLOR_CONF:-}" ]]; then
        _color_load_conf "$COLOR_CONF"
    else
        _color_load_conf "/etc/system-scripts/color.conf"
        _color_load_conf "$(_color_user_conf)"
    fi

    # Clear conditional GUM vars before re-apply
    unset GUM_CHOOSE_HEADER_FOREGROUND 2>/dev/null || true

    # Re-apply GUM vars
    _color_apply_gum

    # Re-apply terminal colors
    if [[ -t 1 ]]; then
        # shellcheck disable=SC2034  # C_* vars used by scripts sourcing this lib
        [[ -n "$_CLR_TERM_RED" ]]     && C_RED="$_CLR_TERM_RED"
        # shellcheck disable=SC2034
        [[ -n "$_CLR_TERM_GREEN" ]]   && C_GREEN="$_CLR_TERM_GREEN"
        # shellcheck disable=SC2034
        [[ -n "$_CLR_TERM_YELLOW" ]]  && C_YELLOW="$_CLR_TERM_YELLOW"
        # shellcheck disable=SC2034
        [[ -n "$_CLR_TERM_CYAN" ]]    && C_CYAN="$_CLR_TERM_CYAN"
        # shellcheck disable=SC2034
        [[ -n "$_CLR_TERM_BLUE" ]]    && C_BLUE="$_CLR_TERM_BLUE"
        # shellcheck disable=SC2034
        [[ -n "$_CLR_TERM_MAGENTA" ]] && C_MAGENTA="$_CLR_TERM_MAGENTA"
    fi

    return 0
}
