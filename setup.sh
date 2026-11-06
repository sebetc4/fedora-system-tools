#!/bin/bash
# =============================================================================
# FEDORA-SYSTEM-TOOLS SETUP - Interactive system tools management
# =============================================================================
# Main entry point for managing Fedora system tools.
# Provides an interactive menu to install, update, uninstall, and monitor
# modules and submodules. Also supports non-interactive CLI flags, which act
# on a whole module when given one, as the make targets do.
#
# Runs as the user, from a checkout or from /opt/fedora-system-tools, and
# uses sudo for system modules. The shared library is sourced from beside
# this script, so its functions serve before it is installed.
#
# Module: setup
# Requires: core, registry, ui
# Version: 0.2.0
#
# Usage:
#   ./setup.sh                                # Interactive menu
#   ./setup.sh --all                          # Install/upgrade all modules
#   ./setup.sh --list                         # List installed modules + submodules
#   ./setup.sh --upgrade                      # Upgrade already-installed items
#   ./setup.sh --reinstall                    # Interactive reinstallation
#   ./setup.sh --uninstall                    # Interactive uninstallation
#   ./setup.sh --install clamav               # Install all clamav submodules
#   ./setup.sh --install clamav/quarantine    # Install one submodule
#   ./setup.sh --upgrade clamav               # Upgrade the outdated clamav subs
#   ./setup.sh --upgrade clamav/quarantine    # Upgrade one submodule
#   ./setup.sh --reinstall clamav             # Reinstall all installed clamav subs
#   ./setup.sh --reinstall clamav/quarantine  # Reinstall one submodule
#   ./setup.sh --uninstall clamav             # Uninstall all clamav submodules
#   ./setup.sh --uninstall clamav/quarantine  # Uninstall one submodule
#   ./setup.sh --info clamav                  # Show module details
#   ./setup.sh --info clamav/quarantine       # Show submodule details
#   ./setup.sh --self-update                  # Update /opt/fedora-system-tools
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: setup failed at line $LINENO" >&2; exit 1' ERR

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR

source "$SCRIPT_DIR/lib/core.sh"
source "$SCRIPT_DIR/lib/registry.sh"
source "$SCRIPT_DIR/lib/ui.sh"

readonly LIB_DIR="/usr/local/lib/system-scripts"
readonly GITHUB_REPO="sebetc4/fedora-system-tools"
readonly INSTALL_DIR="/opt/fedora-system-tools"
readonly SYMLINK_PATH="/usr/local/bin/system-tools"

# =============================================================================
# MODULE DISCOVERY
# =============================================================================
# Every module is read from its module.yml: nothing is listed here.

declare -gA MODULE_DESC=()
declare -gA MODULE_TYPE=()
declare -gA MODULE_DEPS=()
declare -gA MODULE_STANDALONE=()
declare -gA MODULE_DIR_MAP=()
declare -ga MODULES_ORDER=()

# Record a module from its module.yml
# Args: module_yml
_discover_module() {
    local yml="$1" name
    name=$(yq -r '.name' "$yml")
    MODULE_DIR_MAP[$name]=$(dirname "$yml")
    MODULE_DESC[$name]=$(yq -r '.description // ""' "$yml")
    MODULE_TYPE[$name]=$(yq -r '.type // "system"' "$yml")
    MODULE_STANDALONE[$name]=$(yq -r '.standalone // false' "$yml")
    MODULE_DEPS[$name]=$(yq -r '.module_deps // [] | join(" ")' "$yml")
    MODULES_ORDER+=("$name")
}

_discover_modules() {
    local yml
    for yml in "$SCRIPT_DIR"/modules/*/module.yml; do
        [[ -f "$yml" ]] || continue
        _discover_module "$yml"
    done
}

# =============================================================================
# VERSIONS
# =============================================================================

_module_yml() {
    echo "${MODULE_DIR_MAP[$1]}/module.yml"
}

_is_standalone() {
    [[ "${MODULE_STANDALONE[$1]:-false}" == "true" ]]
}

# Print the installed version of a registry section, a module or
# module/submodule, from the system registry, else the user's; nothing when
# it is not installed
# Args: section
_installed_version() {
    local ver
    ver=$(REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" registry_get_version "$1" 2>/dev/null) || true
    if [[ -z "$ver" ]]; then
        ver=$(REGISTRY_PATH_OVERRIDE="$USER_REGISTRY" registry_get_version "$1" 2>/dev/null) || true
    fi
    echo "$ver"
}

# Args: module
_available_version() {
    yq -r '.version // ""' "$(_module_yml "$1")"
}

# Args: module submodule
_sub_available_version() {
    yq -r ".submodules.\"$2\".version // \"\"" "$(_module_yml "$1")"
}

# Print a module's submodules, one per line
# Args: module [kind], kind "hook" for the hooks alone, "main" for the others
_submodules() {
    local filter=""
    case "${2:-}" in
        hook) filter='| map(select(.value.kind == "hook"))' ;;
        main) filter='| map(select(.value.kind != "hook"))' ;;
    esac
    yq -r ".submodules // {} | to_entries $filter | .[].key" "$(_module_yml "$1")"
}

# Succeed when a module is installed at an older version than available, or
# holds an installed submodule that is
# Args: module
_has_update() {
    local module="$1" iver
    if _is_standalone "$module"; then
        iver=$(_installed_version "$module")
        [[ -n "$iver" && "$(version_compare "$iver" "$(_available_version "$module")")" == "lt" ]]
    else
        [[ -n "$(_candidates upgrade "$module")" ]]
    fi
}

# Print the submodules of a module an action applies to: for install, those
# not installed or outdated; for upgrade, those installed and outdated; for
# reinstall and uninstall, those installed
# Args: action module
_candidates() {
    local action="$1" module="$2" sub iver outdated
    while IFS= read -r sub; do
        iver=$(_installed_version "$module/$sub")
        outdated=false
        if [[ -n "$iver" && "$(version_compare "$iver" "$(_sub_available_version "$module" "$sub")")" == "lt" ]]; then
            outdated=true
        fi
        case "$action" in
            install)
                if [[ -z "$iver" || "$outdated" == "true" ]]; then echo "$sub"; fi ;;
            upgrade)
                if [[ "$outdated" == "true" ]]; then echo "$sub"; fi ;;
            reinstall|uninstall)
                if [[ -n "$iver" ]]; then echo "$sub"; fi ;;
        esac
    done < <(_submodules "$module")
}

# Print the picked submodules, then every installed one depending on them, at
# any depth, each added with a note on stderr: the engine refuses to remove
# a submodule another installed one needs
# Args: module picked...
_with_dependents() {
    local module="$1"
    shift
    local picked=("$@") installed=() sub dep changed=true
    mapfile -t installed < <(_candidates uninstall "$module")
    while [[ "$changed" == "true" ]]; do
        changed=false
        for sub in "${installed[@]}"; do
            printf '%s\n' "${picked[@]}" | grep -qxF -- "$sub" && continue
            while IFS= read -r dep; do
                if printf '%s\n' "${picked[@]}" | grep -qxF -- "$dep"; then
                    picked+=("$sub")
                    echo -e "  ${C_YELLOW}Adding $sub (depends on $dep)${C_NC}" >&2
                    changed=true
                    break
                fi
            done < <(yq -r ".submodules.\"$sub\".deps // [] | .[]" "$(_module_yml "$module")")
        done
    done
    printf '%s\n' "${picked[@]}"
}

# =============================================================================
# INSTALL / UNINSTALL A MODULE
# =============================================================================

# Run a module's installer: every submodule, or the comma-separated list given
# Args: module [submodules]
# Env: INSTALL_FORCE=true reinstalls what is at its version
install_module() {
    local module="$1"
    local only_sub="${2:-}"

    # --- Check inter-module dependencies ---
    local dep missing=()
    for dep in ${MODULE_DEPS[$module]:-}; do
        [[ -n "$(_installed_version "$dep")" ]] || missing+=("$dep")
    done
    if (( ${#missing[@]} > 0 )); then
        warn "Module '$module' requires: ${missing[*]}"
        if [[ "$MODE" == "interactive" ]] \
            && ! ui_confirm "Install missing dependencies (${missing[*]}) before $module?"; then
            info "Installation of '$module' cancelled."
            return 0
        fi
        info "Installing dependencies first..."
        for dep in "${missing[@]}"; do
            install_module "$dep"
        done
    fi

    local installer="${MODULE_DIR_MAP[$module]}/install.sh"
    if [[ ! -f "$installer" ]]; then
        error "Module '$module' has no installer: $installer"
        return 1
    fi

    # --- Check minimum lib version ---
    local min_lib
    min_lib=$(yq -r '.min_lib_version // ""' "$(_module_yml "$module")")
    if [[ -n "$min_lib" && "$(version_compare "$LIB_VERSION" "$min_lib")" == "lt" ]]; then
        error "Module '$module' requires lib >= $min_lib (installed: $LIB_VERSION). Run: make install-lib"
        return 1
    fi

    local cmd_args=()
    if [[ -n "$only_sub" ]]; then
        cmd_args=(--only "$only_sub")
    elif ! _is_standalone "$module"; then
        cmd_args=(--all)
    fi
    if [[ "${INSTALL_FORCE:-false}" == "true" ]]; then
        cmd_args+=(--force)
    fi

    if [[ "${MODULE_TYPE[$module]}" == "system" ]]; then
        sudo "$installer" "${cmd_args[@]}"
    else
        "$installer" "${cmd_args[@]}"
    fi
}

# Run a module's uninstaller: every submodule, or the comma-separated list given
# Args: module [submodules]
uninstall_module() {
    local module="$1"
    local only_sub="${2:-}"

    # --- Block uninstall if another installed module depends on this one ---
    if [[ -z "$only_sub" ]]; then
        local other dependents=()
        for other in "${MODULES_ORDER[@]}"; do
            [[ "$other" == "$module" ]] && continue
            [[ -n "$(_installed_version "$other")" ]] || continue
            if [[ " ${MODULE_DEPS[$other]:-} " == *" $module "* ]]; then
                dependents+=("$other")
            fi
        done
        if (( ${#dependents[@]} > 0 )); then
            error "Cannot uninstall '$module': required by installed module(s): ${dependents[*]}"
            info "Uninstall ${dependents[*]} first."
            return 1
        fi
    fi

    local uninstaller="${MODULE_DIR_MAP[$module]}/uninstall.sh"
    if [[ ! -f "$uninstaller" ]]; then
        error "Module '$module' has no uninstaller: $uninstaller"
        return 1
    fi

    local cmd_args=()
    if [[ -n "$only_sub" ]]; then
        cmd_args=(--only "$only_sub")
    elif ! _is_standalone "$module"; then
        cmd_args=(--all)
    fi

    if [[ "${MODULE_TYPE[$module]}" == "system" ]]; then
        sudo "$uninstaller" "${cmd_args[@]}"
    else
        "$uninstaller" "${cmd_args[@]}"
    fi
}

# Upgrade a module: its outdated submodules alone, or the whole of a
# standalone module
# Args: module
_upgrade_module() {
    local module="$1"
    if _is_standalone "$module"; then
        install_module "$module"
        return
    fi
    local outdated=()
    mapfile -t outdated < <(_candidates upgrade "$module")
    if (( ${#outdated[@]} == 0 )); then
        success "$module: all submodules are up to date"
        return 0
    fi
    install_module "$module" "$(IFS=','; echo "${outdated[*]}")"
}

# Reinstall a module: its installed submodules, or the whole of a standalone module
# Args: module
_reinstall_module() {
    local module="$1"
    if _is_standalone "$module"; then
        INSTALL_FORCE=true install_module "$module"
        return
    fi
    local installed=()
    mapfile -t installed < <(_candidates reinstall "$module")
    if (( ${#installed[@]} == 0 )); then
        error "$module: no installed submodule to reinstall"
        return 1
    fi
    INSTALL_FORCE=true install_module "$module" "$(IFS=','; echo "${installed[*]}")"
}

# =============================================================================
# ENSURE LIBRARY IS INSTALLED
# =============================================================================

ensure_lib() {
    local lib_installed_ver=""
    lib_installed_ver=$(REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" registry_get_version "lib" 2>/dev/null) || true

    if [[ -n "$lib_installed_ver" && -f "$LIB_DIR/core.sh" ]]; then
        if [[ "$(version_compare "$lib_installed_ver" "$LIB_VERSION")" != "lt" ]]; then
            return 0
        fi
        info "Shared library upgrade available: v$lib_installed_ver -> v$LIB_VERSION"
        if [[ "$MODE" == "interactive" ]] && ! ui_confirm "Upgrade shared library?"; then
            return 0
        fi
    else
        info "Installing shared library..."
    fi
    if ! sudo bash "$SCRIPT_DIR/lib/install.sh"; then
        error "Library installation failed" "exit"
    fi
}

# =============================================================================
# SHOW STATUS (with submodule detail)
# =============================================================================

# The color goes in the first field, through %b, which reads its escapes
readonly STATUS_ROW="    %b%-20s %-12s %-12s %s${C_NC}\n"

# Print a status row: the installed version against the available one
# Args: label installed_version available_version
_print_status_row() {
    local label="$1" iver="$2" aver="$3"
    if [[ -z "$iver" ]]; then
        # shellcheck disable=SC2059  # STATUS_ROW is the format
        printf "$STATUS_ROW" "$C_DIM" "$label" "--" "v${aver:-?}" ""
    elif [[ "$(version_compare "$iver" "${aver:-0.0.0}")" == "lt" ]]; then
        # shellcheck disable=SC2059
        printf "$STATUS_ROW" "$C_YELLOW" "$label" "v$iver" "v${aver:-?}" "update available"
    else
        # shellcheck disable=SC2059
        printf "$STATUS_ROW" "$C_GREEN" "$label" "v$iver" "v${aver:-?}" "✓"
    fi
}

# Args: first column title
_print_status_head() {
    # shellcheck disable=SC2059
    printf "$STATUS_ROW" "$C_BOLD" "$1" "INSTALLED" "AVAILABLE" "STATUS"
}

show_status() {
    # --- Lib status ---
    local lib_ver
    lib_ver=$(REGISTRY_PATH_OVERRIDE="$SYSTEM_REGISTRY" registry_get_version "lib" 2>/dev/null) || true
    if [[ -z "$lib_ver" ]]; then
        echo -e "  ${C_BOLD}lib${C_NC}  ${C_RED}not installed${C_NC}"
    elif [[ "$(version_compare "$lib_ver" "$LIB_VERSION")" == "lt" ]]; then
        echo -e "  ${C_BOLD}lib${C_NC}  ${C_YELLOW}v$lib_ver → v$LIB_VERSION (update available)${C_NC}"
    else
        echo -e "  ${C_BOLD}lib${C_NC}  ${C_GREEN}v$lib_ver${C_NC}"
    fi
    echo ""

    # --- Modules grouped ---
    local module sub submodules hooks
    for module in "${MODULES_ORDER[@]}"; do
        echo -e "  ${C_BOLD}${C_CYAN}${module}${C_NC}  ${C_DIM}${MODULE_DESC[$module]:-}${C_NC}"
        echo ""
        _print_status_head "SUB-MODULE"

        if _is_standalone "$module"; then
            _print_status_row "(standalone)" "$(_installed_version "$module")" "$(_available_version "$module")"
        else
            mapfile -t submodules < <(_submodules "$module" main)
            mapfile -t hooks < <(_submodules "$module" hook)
            for sub in "${submodules[@]}"; do
                _print_status_row "$sub" "$(_installed_version "$module/$sub")" \
                    "$(_sub_available_version "$module" "$sub")"
            done
            if (( ${#hooks[@]} > 0 )); then
                echo ""
                _print_status_head "HOOKS"
                for sub in "${hooks[@]}"; do
                    _print_status_row "$sub" "$(_installed_version "$module/$sub")" \
                        "$(_sub_available_version "$module" "$sub")"
                done
            fi
        fi
        echo ""
    done
}

# =============================================================================
# SHOW INFO (detailed module/submodule view)
# =============================================================================

# Print one "Label: value" line when the value is not empty
# Args: label value
_info_line() {
    if [[ -n "$2" ]]; then
        # shellcheck disable=SC2059  # the colors are escapes printf reads
        printf "  ${C_BOLD}%-12s${C_NC} %b\n" "$1:" "$2"
    fi
}

# Print an installed version, or "no"
# Args: version
_installed_label() {
    if [[ -n "$1" ]]; then
        echo "${C_GREEN}v$1${C_NC}"
    else
        echo "${C_DIM}no${C_NC}"
    fi
}

show_info() {
    local target="$1"
    local module="${target%%/*}" sub=""
    [[ "$target" == */* ]] && sub="${target#*/}"
    local yml
    yml=$(_module_yml "$module")
    local mtype
    mtype=$(yq -r '.type // "system"' "$yml")

    if [[ -n "$sub" ]]; then
        # --- Submodule info ---
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}${module}/${sub}${C_NC}"
        echo -e "  $(yq -r ".submodules.\"$sub\".description // \"\"" "$yml")"
        echo ""
        _info_line "Version" "$(_sub_available_version "$module" "$sub")"
        _info_line "Type" "$(yq -r ".submodules.\"$sub\".type // \"$mtype\"" "$yml")"
        _info_line "Installed" "$(_installed_label "$(_installed_version "$module/$sub")")"
        _info_line "Command" "$(yq -r ".submodules.\"$sub\".bin_name // \"\"" "$yml")"
        _info_line "Deps" "$(yq -r ".submodules.\"$sub\".deps // [] | join(\", \")" "$yml")"
        _info_line "System deps" "$(yq -r ".submodules.\"$sub\".system_deps // [] | join(\", \")" "$yml")"
        _info_line "Services" "$(yq -r ".submodules.\"$sub\".services // [] | map(sub(\".*/\"; \"\")) | join(\", \")" "$yml")"
        _info_line "Timers" "$(yq -r ".submodules.\"$sub\".timers // [] | map(sub(\".*/\"; \"\")) | join(\", \")" "$yml")"
        echo ""
        return 0
    fi

    # --- Module info ---
    echo ""
    echo -e "  ${C_BOLD}${C_CYAN}${module}${C_NC}"
    echo -e "  ${MODULE_DESC[$module]:-}"
    echo ""
    _info_line "Version" "$(_available_version "$module")"
    _info_line "Type" "$mtype"
    _info_line "Installed" "$(_installed_label "$(_installed_version "$module")")"
    _info_line "Module deps" "$(yq -r '.module_deps // [] | join(", ")' "$yml")"
    echo ""

    local key detail
    if _is_standalone "$module"; then
        echo -e "  ${C_BOLD}Scripts:${C_NC}"
        while IFS= read -r key; do
            echo -e "    ${C_BOLD}$key${C_NC} — $(yq -r ".scripts.\"$key\".description // \"\"" "$yml")"
        done < <(yq -r '.scripts // {} | keys | .[]' "$yml")
    else
        echo -e "  ${C_BOLD}Submodules:${C_NC}"
        while IFS= read -r key; do
            detail="v$(_sub_available_version "$module" "$key") — $(yq -r ".submodules.\"$key\".description // \"\"" "$yml")"
            local bin type
            bin=$(yq -r ".submodules.\"$key\".bin_name // \"\"" "$yml")
            type=$(yq -r ".submodules.\"$key\".type // \"\"" "$yml")
            [[ -n "$bin" ]] && detail="$detail  ${C_DIM}→ $bin${C_NC}"
            [[ -n "$type" ]] && detail="$detail ${C_DIM}[$type]${C_NC}"
            if [[ -n "$(_installed_version "$module/$key")" ]]; then
                echo -e "    ${C_GREEN}● $key${C_NC} $detail"
            else
                echo -e "    ${C_DIM}○ $key${C_NC} $detail"
            fi
        done < <(_submodules "$module")
        echo ""
        echo -e "  ${C_DIM}● installed  ○ not installed${C_NC}"
    fi
    echo ""
}

action_info() {
    echo ""
    info "Available modules:"
    echo ""
    local module
    for module in "${MODULES_ORDER[@]}"; do
        echo -e "  ${C_BOLD}$module${C_NC} — ${MODULE_DESC[$module]}"
    done
    echo ""

    local choice
    choice="$(ui_choose --header "Select module to inspect:" "${MODULES_ORDER[@]}" "Back")"
    case "$choice" in
        "Back"|"") return 0 ;;
        *)
            show_info "$choice"
            ui_press_enter
            ;;
    esac
}

# =============================================================================
# INTERACTIVE SUBMODULE SELECTION (runs without root)
# =============================================================================
# Displays a module's submodules and lets the user pick those an action
# applies to BEFORE requesting sudo. Sets SUBMODULE_SELECTION to the
# comma-separated list picked; returns 1 when there is nothing to pick or the
# user picked nothing. A single installed submodule is taken without asking.

_select_submodules() {
    local action="$1" module="$2"
    SUBMODULE_SELECTION=""
    local candidates=() picked=() sub iver aver desc yml
    yml=$(_module_yml "$module")
    mapfile -t candidates < <(_candidates "$action" "$module")

    info "Module: $module v$(_available_version "$module")"
    echo ""
    while IFS= read -r sub; do
        iver=$(_installed_version "$module/$sub")
        aver=$(_sub_available_version "$module" "$sub")
        desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$yml")
        if [[ -z "$iver" ]]; then
            echo -e "  ${C_DIM}[available v$aver]${C_NC} $sub — $desc"
        elif [[ "$(version_compare "$iver" "$aver")" == "lt" ]]; then
            echo -e "  ${C_YELLOW}[installed v$iver → v$aver]${C_NC} $sub — $desc"
        else
            echo -e "  ${C_GREEN}[installed v$iver]${C_NC} $sub — $desc"
        fi
    done < <(_submodules "$module")
    echo ""

    if (( ${#candidates[@]} == 0 )); then
        info "No submodule of $module to $action"
        return 1
    fi
    if (( ${#candidates[@]} == 1 )) && [[ "$action" != "install" ]]; then
        picked=("${candidates[@]}")
    else
        mapfile -t picked < <(ui_choose_many "Select submodules to $action:" "${candidates[@]}")
    fi
    (( ${#picked[@]} > 0 )) || return 1

    if [[ "$action" == "uninstall" ]]; then
        mapfile -t picked < <(_with_dependents "$module" "${picked[@]}")
    fi
    SUBMODULE_SELECTION=$(IFS=','; echo "${picked[*]}")
}

# =============================================================================
# MENU ACTIONS
# =============================================================================

# Print the modules installed, each with its installed submodules
_print_installed() {
    local module sub
    for module in "$@"; do
        echo -e "  ${C_GREEN}$module${C_NC} v$(_installed_version "$module") — ${MODULE_DESC[$module]}"
        if ! _is_standalone "$module"; then
            while IFS= read -r sub; do
                echo -e "    ${C_DIM}├─ $sub v$(_installed_version "$module/$sub")${C_NC}"
            done < <(_candidates reinstall "$module")
        fi
    done
    echo ""
}

# Print the installed modules
_installed_modules() {
    local module
    for module in "${MODULES_ORDER[@]}"; do
        if [[ -n "$(_installed_version "$module")" ]]; then
            echo "$module"
        fi
    done
}

action_install() {
    local module available=()
    for module in "${MODULES_ORDER[@]}"; do
        if [[ -z "$(_installed_version "$module")" ]] \
            || { ! _is_standalone "$module" && [[ -n "$(_candidates install "$module")" ]]; }; then
            available+=("$module")
        fi
    done

    if (( ${#available[@]} == 0 )); then
        echo ""
        success "All modules are installed and up to date"
        echo ""
        ui_press_enter
        return 0
    fi

    echo ""
    info "Modules available for installation:"
    echo ""
    for module in "${available[@]}"; do
        echo -e "  ${C_BOLD}$module${C_NC} v$(_available_version "$module") — ${MODULE_DESC[$module]}"
    done
    echo ""

    local choice
    choice="$(ui_choose --header "Select module to install:" "All (install everything)" "${available[@]}" "Back")"
    case "$choice" in
        "All (install everything)")
            echo ""
            for module in "${available[@]}"; do
                info "Installing $module..."
                install_module "$module"
                echo ""
            done
            success "All modules installed"
            ;;
        "Back"|"") return 0 ;;
        *)
            echo ""
            if _is_standalone "$choice"; then
                install_module "$choice"
            elif _select_submodules install "$choice"; then
                install_module "$choice" "$SUBMODULE_SELECTION"
            fi
            echo ""
            ;;
    esac
}

action_update() {
    # --- Step 1: the suite, when it runs from /opt/fedora-system-tools ---
    echo ""
    if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        info "Running from a checkout ($SCRIPT_DIR): update it with git pull"
    else
        info "Checking for suite updates..."
        local rc=0
        check_remote_version || rc=$?
        case $rc in
            0)
                echo ""
                echo -e "  ${C_YELLOW}Suite update available:${C_NC} v${SELF_UPDATE_CURRENT} → v${SELF_UPDATE_LATEST}"
                echo ""
                if ui_confirm "Update suite to v${SELF_UPDATE_LATEST}?"; then
                    if apply_self_update; then
                        echo ""
                        info "Relaunching with updated version..."
                        exec "${INSTALL_DIR}/setup.sh" --post-update
                    fi
                    error "Suite update failed, continuing with module updates..."
                fi
                ;;
            1) success "Suite is up to date (v${SELF_UPDATE_CURRENT})" ;;
        esac
    fi
    echo ""

    # --- Step 2: Module updates (local) ---
    action_update_modules
}

# Check and upgrade installed modules/submodules (local version comparison)
action_update_modules() {
    local module sub updatable=()
    for module in "${MODULES_ORDER[@]}"; do
        if [[ -n "$(_installed_version "$module")" ]] && _has_update "$module"; then
            updatable+=("$module")
        fi
    done

    if (( ${#updatable[@]} == 0 )); then
        echo ""
        success "All modules are up to date"
        echo ""
        ui_press_enter
        return 0
    fi

    echo ""
    info "Modules with updates available:"
    echo ""
    for module in "${updatable[@]}"; do
        if _is_standalone "$module"; then
            echo -e "  ${C_YELLOW}$module${C_NC}  v$(_installed_version "$module") -> v$(_available_version "$module")"
        else
            echo -e "  ${C_YELLOW}$module${C_NC}"
            while IFS= read -r sub; do
                echo -e "    ${C_YELLOW}$sub${C_NC}  v$(_installed_version "$module/$sub") -> v$(_sub_available_version "$module" "$sub")"
            done < <(_candidates upgrade "$module")
        fi
    done
    echo ""

    local choice
    choice="$(ui_choose --header "Select module to update:" "All (update everything)" "${updatable[@]}" "Back")"
    case "$choice" in
        "All (update everything)")
            echo ""
            for module in "${updatable[@]}"; do
                info "Updating $module..."
                _upgrade_module "$module"
                echo ""
            done
            success "All modules updated"
            ;;
        "Back"|"") return 0 ;;
        *)
            echo ""
            _upgrade_module "$choice"
            echo ""
            ;;
    esac
}

action_uninstall() {
    local installed=() module
    mapfile -t installed < <(_installed_modules)
    if (( ${#installed[@]} == 0 )); then
        echo ""
        info "No modules installed"
        echo ""
        return 0
    fi

    echo ""
    info "Installed modules:"
    echo ""
    _print_installed "${installed[@]}"

    local choice
    choice="$(ui_choose --header "Select module to uninstall:" "All (uninstall everything)" "${installed[@]}" "Back")"
    case "$choice" in
        "All (uninstall everything)")
            echo ""
            if ui_confirm "Uninstall ALL modules? This cannot be undone."; then
                for module in "${installed[@]}"; do
                    info "Uninstalling $module..."
                    uninstall_module "$module"
                    echo ""
                done
                success "All modules uninstalled"
            fi
            ;;
        "Back"|"") return 0 ;;
        *)
            echo ""
            if _is_standalone "$choice"; then
                if ui_confirm "Uninstall $choice?"; then
                    uninstall_module "$choice"
                fi
            elif _select_submodules uninstall "$choice" \
                && ui_confirm "Uninstall $choice submodule(s): ${SUBMODULE_SELECTION//,/, }?"; then
                uninstall_module "$choice" "$SUBMODULE_SELECTION"
            fi
            echo ""
            ;;
    esac
}

action_reinstall() {
    local installed=()
    mapfile -t installed < <(_installed_modules)
    if (( ${#installed[@]} == 0 )); then
        echo ""
        info "No modules installed to reinstall"
        echo ""
        return 0
    fi

    echo ""
    info "Installed modules:"
    echo ""
    _print_installed "${installed[@]}"

    local choice
    choice="$(ui_choose --header "Select module to reinstall:" "${installed[@]}" "Back")"
    case "$choice" in
        "Back"|"") return 0 ;;
        *)
            echo ""
            if _is_standalone "$choice"; then
                if ui_confirm "Reinstall $choice?"; then
                    INSTALL_FORCE=true install_module "$choice"
                fi
            elif _select_submodules reinstall "$choice" \
                && ui_confirm "Reinstall $choice submodule(s): ${SUBMODULE_SELECTION//,/, }?"; then
                INSTALL_FORCE=true install_module "$choice" "$SUBMODULE_SELECTION"
            fi
            echo ""
            ;;
    esac
}

# =============================================================================
# ACTION: COLORS
# =============================================================================
# The user's choices go to ~/.config/system-scripts/color.conf, over the
# system's /etc/system-scripts/color.conf; color_reload applies both.

readonly USER_COLOR_CONF="$HOME/.config/system-scripts/color.conf"

# Each setting: color.conf keys (space-separated)|menu label|variable holding
# its value|what an empty value means, nothing when a value is required
readonly COLOR_SETTINGS=(
    "accent|Accent color|COLOR_ACCENT|"
    "header_border|Header border color|COLOR_HEADER|accent"
    "header_text|Header text color|COLOR_HEADER_TEXT|default"
    "selection_title|Selection title color|COLOR_SELECTION_TITLE|default"
    "choose_cursor_foreground choose_selected_foreground|Selection color|_CLR_CHOOSE_CURSOR_FG|accent"
    "error|Error color|COLOR_ERROR|"
)

_color_valid() {
    local value="$1"
    # ANSI 0-255, or hex #RRGGBB or #RGB
    if [[ "$value" =~ ^[0-9]{1,3}$ ]] && (( 10#$value <= 255 )); then
        return 0
    fi
    [[ "$value" =~ ^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$ ]]
}

# Write one key of the user's color.conf
# Args: key value
_set_user_color() {
    local key="$1" value="$2"
    mkdir -p "$(dirname "$USER_COLOR_CONF")"
    if [[ -f "$USER_COLOR_CONF" ]] && grep -q "^${key}=" "$USER_COLOR_CONF"; then
        # The value is validated, safe for sed
        sed -i "s/^${key}=.*/${key}=${value}/" "$USER_COLOR_CONF"
    else
        echo "${key}=${value}" >> "$USER_COLOR_CONF"
    fi
}

_color_preview() {
    local header="${COLOR_HEADER:-$COLOR_ACCENT}"
    local selection="${_CLR_CHOOSE_CURSOR_FG:-$COLOR_ACCENT}"
    echo ""
    if has_gum; then
        local hdr_args=(gum style --border rounded --padding "0 1" --border-foreground "$header")
        [[ -n "${COLOR_HEADER_TEXT:-}" ]] && hdr_args+=(--foreground "$COLOR_HEADER_TEXT")
        "${hdr_args[@]}" "Header border: ${COLOR_HEADER:-(= accent)}, text: ${COLOR_HEADER_TEXT:-(default)}"
        gum style --border rounded --padding "0 1" --border-foreground "$COLOR_ACCENT" "Accent: $COLOR_ACCENT"
        if [[ -n "${COLOR_SELECTION_TITLE:-}" ]]; then
            gum style --foreground "$COLOR_SELECTION_TITLE" "Selection title: $COLOR_SELECTION_TITLE"
        else
            echo "  Selection title: (default)"
        fi
        gum style --foreground "$selection" "  > Selection: ${_CLR_CHOOSE_CURSOR_FG:-(= accent)}"
        gum style --border rounded --padding "0 1" --border-foreground "$COLOR_ERROR" "Error: $COLOR_ERROR"
    else
        echo -e "  Header border: ${C_BOLD}${COLOR_HEADER:-(= accent)}${C_NC}"
        echo -e "  Header text:   ${C_BOLD}${COLOR_HEADER_TEXT:-(default)}${C_NC}"
        echo -e "  Accent:        ${C_BOLD}$COLOR_ACCENT${C_NC}"
        echo -e "  Sel. title:    ${C_BOLD}${COLOR_SELECTION_TITLE:-(default)}${C_NC}"
        echo -e "  Selection:     ${C_BOLD}${_CLR_CHOOSE_CURSOR_FG:-(= accent)}${C_NC}"
        echo -e "  Error:         ${C_BOLD}$COLOR_ERROR${C_NC}"
    fi
    echo ""
}

# Ask for one setting's color and save it
# Args: setting (an entry of COLOR_SETTINGS)
_ask_color() {
    local keys label var empty
    IFS='|' read -r keys label var empty <<< "$1"
    local current="${!var:-}" hint="${empty:+, empty = $empty}" new_val key
    if has_gum; then
        new_val=$(gum input --header "$label (0-255 or #hex$hint)" --value "$current") || return 0
    else
        read -rp "$label (0-255 or #hex$hint) [${current:-$empty}]: " new_val
        [[ -n "$new_val" || -n "$empty" ]] || new_val="$current"
    fi
    if [[ -z "$new_val" && -z "$empty" ]] || { [[ -n "$new_val" ]] && ! _color_valid "$new_val"; }; then
        warn "Invalid color value"
        return 0
    fi
    for key in $keys; do
        _set_user_color "$key" "$new_val"
    done
    color_reload
    success "$label: ${new_val:-$empty}"
}

action_colors() {
    local setting choice labels=()
    for setting in "${COLOR_SETTINGS[@]}"; do
        labels+=("Set $(cut -d'|' -f2 <<< "$setting" | tr '[:upper:]' '[:lower:]')")
    done
    while true; do
        echo ""
        info "Current theme:"
        _color_preview

        choice="$(ui_choose --header "Color options:" "${labels[@]}" "Reset to defaults" "Back")" || return 0
        case "$choice" in
            "Back"|"") return 0 ;;
            "Reset to defaults")
                if [[ -f "$USER_COLOR_CONF" ]]; then
                    rm -f "$USER_COLOR_CONF"
                    color_reload
                    success "Colors reset to defaults"
                else
                    info "Already using defaults"
                fi
                ;;
            *)
                for setting in "${COLOR_SETTINGS[@]}"; do
                    if [[ "Set $(cut -d'|' -f2 <<< "$setting" | tr '[:upper:]' '[:lower:]')" == "$choice" ]]; then
                        _ask_color "$setting"
                    fi
                done
                ;;
        esac
    done
}

# =============================================================================
# MAIN MENU (interactive loop)
# =============================================================================

main_menu() {
    local choice
    while true; do
        ui_header "Fedora System Scripts - Setup"

        choice="$(ui_choose --header "What would you like to do?" \
            "Status      View system status + submodules" \
            "Install     Install new modules" \
            "Update      Check for updates (suite + modules)" \
            "Uninstall   Remove installed modules" \
            "Info        Show module details" \
            "Reinstall   Force reinstall a module" \
            "Colors      Customize UI theme" \
            "Quit")"

        case "${choice%% *}" in
            Status)
                ui_header "System Status"
                show_status
                ui_press_enter
                ;;
            Install)   action_install ;;
            Update)    action_update ;;
            Uninstall) action_uninstall ;;
            Info)      action_info ;;
            Reinstall) action_reinstall ;;
            Colors)    action_colors ;;
            Quit|"")   echo ""; success "Bye!"; echo ""; return 0 ;;
        esac
    done
}

# =============================================================================
# SELF-UPDATE
# =============================================================================
# Only an install under /opt/fedora-system-tools updates itself: a checkout
# is updated with git.

# Print the newest project release tag (vX.Y.Z) of a GitHub releases list read
# on stdin, without jq. Module tags (clamav-v0.2.0) and pre-releases
# (v1.0.0-rc1) are skipped: releases/latest may be either. install.sh holds the
# same function, which tests/unit/install.bats keeps identical.
latest_project_tag() {
    grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' \
        | sort -V | tail -n 1 | grep .
}

# Download a release's tarball into a folder and check that it reads as an
# archive, before anything installed is touched. install.sh holds the same
# function, which tests/unit/install.bats keeps identical.
# Args: tag dir
# Output: the tarball's path
download_release() {
    local tag="$1" dir="$2"
    local tarball="fedora-system-tools-${tag#v}.tar.gz"
    curl -fsSL -o "$dir/$tarball" "https://github.com/${GITHUB_REPO}/releases/download/${tag}/${tarball}" \
        || return 1
    tar -tzf "$dir/$tarball" > /dev/null || return 1
    echo "$dir/$tarball"
}

# Check if a newer release is available on GitHub
# Sets SELF_UPDATE_TAG, SELF_UPDATE_LATEST and SELF_UPDATE_CURRENT
# Returns: 0 = update available, 1 = up to date, 2 = error
check_remote_version() {
    local response
    response=$(curl -fsSL --max-time 10 "https://api.github.com/repos/${GITHUB_REPO}/releases?per_page=100" 2>/dev/null) || {
        warn "Could not reach GitHub API (network issue?)"
        return 2
    }

    local tag
    tag=$(latest_project_tag <<< "$response") || true
    if [[ -z "$tag" ]]; then
        warn "Could not determine latest release"
        return 2
    fi

    local current_version=""
    if [[ -f "${INSTALL_DIR}/.version" ]]; then
        current_version=$(cat "${INSTALL_DIR}/.version")
    fi

    SELF_UPDATE_TAG="$tag"
    SELF_UPDATE_LATEST="${tag#v}"
    SELF_UPDATE_CURRENT="${current_version:-unknown}"
    [[ "$current_version" != "$SELF_UPDATE_LATEST" ]] || return 1
}

# Download and apply the update (uses SELF_UPDATE_TAG/SELF_UPDATE_LATEST)
SELF_UPDATE_TMP=""
apply_self_update() {
    SELF_UPDATE_TMP=$(mktemp -d)
    trap 'rm -rf "$SELF_UPDATE_TMP"' EXIT

    info "Downloading v${SELF_UPDATE_LATEST}..."
    local tarball
    if ! tarball=$(download_release "$SELF_UPDATE_TAG" "$SELF_UPDATE_TMP"); then
        error "Failed to download release ${SELF_UPDATE_TAG}: ${INSTALL_DIR} is left as it was"
        rm -rf "$SELF_UPDATE_TMP"
        return 1
    fi

    info "Updating ${INSTALL_DIR}..."
    sudo rm -rf "${INSTALL_DIR:?}/lib" "${INSTALL_DIR:?}/modules" "${INSTALL_DIR:?}/setup.sh" "${INSTALL_DIR:?}/Makefile"
    sudo tar xzf "$tarball" -C "$INSTALL_DIR" --strip-components=1
    echo "$SELF_UPDATE_LATEST" | sudo tee "${INSTALL_DIR}/.version" > /dev/null
    sudo chmod +x "${INSTALL_DIR}/setup.sh"
    rm -rf "$SELF_UPDATE_TMP"

    info "Updating shared library..."
    sudo "${INSTALL_DIR}/lib/install.sh"
    sudo ln -sf "${INSTALL_DIR}/setup.sh" "$SYMLINK_PATH"
    success "Updated to v${SELF_UPDATE_LATEST}"
}

# CLI self-update: check + apply + hint
self_update() {
    if [[ "$SCRIPT_DIR" != "$INSTALL_DIR" ]]; then
        error "Running from a checkout ($SCRIPT_DIR): update it with git pull"
        return 1
    fi
    info "Checking for updates..."
    local rc=0
    check_remote_version || rc=$?
    case $rc in
        1) success "Already up to date (v${SELF_UPDATE_CURRENT})"; return 0 ;;
        2) return 1 ;;
    esac
    info "Current: v${SELF_UPDATE_CURRENT} → Latest: v${SELF_UPDATE_LATEST}"
    apply_self_update || return 1
    echo ""
    info "Run 'system-tools --upgrade' to upgrade installed modules"
}

# =============================================================================
# CLI
# =============================================================================

show_help() {
    echo "Usage: $(basename "$0") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)                        Interactive menu"
    echo "  --all                         Install/upgrade all modules"
    echo "  --list                        List installed modules + submodules"
    echo "  --install <module[/sub]>      Install a module's submodules, or one"
    echo "  --upgrade [module[/sub]]      Upgrade installed items"
    echo "  --reinstall [module[/sub]]    Force reinstall installed items (menu without target)"
    echo "  --uninstall [module[/sub]]    Uninstall items (menu without target)"
    echo "  --info <module[/sub]>         Show module or submodule details"
    echo "  --self-update                 Update /opt/fedora-system-tools to the latest release"
    echo "  -h, --help                    Show this help"
}

# Parse the options into MODE and CLI_TARGET
parse_args() {
    MODE="interactive"
    CLI_TARGET=""
    while (( $# > 0 )); do
        case "$1" in
            --all) MODE="install-all" ;;
            --list) MODE="list" ;;
            --self-update) MODE="self-update" ;;
            --post-update) MODE="post-update" ;;
            --install|--info|--upgrade|--reinstall|--uninstall)
                MODE="${1#--}"
                if [[ -n "${2:-}" && "$2" != -* ]]; then
                    CLI_TARGET="$2"
                    shift
                elif [[ "$MODE" == "install" || "$MODE" == "info" ]]; then
                    error "$1 requires a module or module/submodule argument"
                    return 1
                fi
                ;;
            -h|--help) MODE="help" ;;
            *)
                error "Unknown option: $1 (see --help)"
                return 1
                ;;
        esac
        shift
    done
}

# Check that a target names a known module, and a submodule of it
# Args: target
validate_target() {
    local module="${1%%/*}" sub=""
    [[ "$1" == */* ]] && sub="${1#*/}"
    if [[ -z "${MODULE_DIR_MAP[$module]:-}" ]]; then
        error "Unknown module: $module"
        info "Available modules: ${MODULES_ORDER[*]}"
        return 1
    fi
    if [[ -n "$sub" ]] && ! _submodules "$module" | grep -qxF -- "$sub"; then
        error "Unknown submodule: $module/$sub"
        return 1
    fi
}

# Upgrade from the CLI: everything installed, a module, or one submodule
# Args: [target]
cli_upgrade() {
    local target="${1:-}" module sub upgraded=0
    if [[ "$target" == */* ]]; then
        module="${target%%/*}" sub="${target#*/}"
        if [[ -z "$(_installed_version "$target")" ]]; then
            error "$target is not installed: use --install $target"
            return 1
        fi
        if ! _candidates upgrade "$module" | grep -qxF -- "$sub"; then
            success "$target is up to date"
            return 0
        fi
        install_module "$module" "$sub"
    elif [[ -n "$target" ]]; then
        if [[ -z "$(_installed_version "$target")" ]]; then
            error "$target is not installed: use --install $target"
            return 1
        fi
        _upgrade_module "$target"
    else
        info "Checking for upgrades..."
        echo ""
        while IFS= read -r module; do
            if _has_update "$module"; then
                _upgrade_module "$module"
                echo ""
                upgraded=$((upgraded + 1))
            else
                echo -e "  ${C_DIM}$module v$(_installed_version "$module") (up to date)${C_NC}"
            fi
        done < <(_installed_modules)
        echo ""
        if (( upgraded == 0 )); then
            success "All modules are up to date"
        else
            success "$upgraded module(s) upgraded"
        fi
    fi
}

# Reinstall from the CLI: a module's installed submodules, or one submodule
# Args: target
cli_reinstall() {
    local target="$1"
    if [[ "$target" == */* ]]; then
        if [[ -z "$(_installed_version "$target")" ]]; then
            error "$target is not installed: use --install $target"
            return 1
        fi
        INSTALL_FORCE=true install_module "${target%%/*}" "${target#*/}"
    else
        _reinstall_module "$target"
    fi
}

main() {
    if [[ "$EUID" -eq 0 ]]; then
        error "Do not run this script as root."
        info "The script will use sudo when needed."
        exit 1
    fi

    parse_args "$@" || exit 1
    if [[ "$MODE" == "help" ]]; then
        show_help
        exit 0
    fi

    # Every mode but --list installs the library first, yq with it
    if [[ "$MODE" != "list" ]]; then
        ensure_lib
    fi
    command -v yq &>/dev/null || error "yq is required: run $(basename "$0") without --list once, which installs it" "exit"
    _discover_modules

    if [[ -n "$CLI_TARGET" ]]; then
        validate_target "$CLI_TARGET" || exit 1
    fi

    case "$MODE" in
        self-update) self_update || exit 1 ;;
        post-update)
            # Relaunched after self-update: go straight to module upgrades
            success "Suite updated successfully"
            echo ""
            action_update_modules
            ;;
        list)
            ui_header "Fedora System Scripts - Status"
            show_status
            ;;
        info) show_info "$CLI_TARGET" ;;
        install-all)
            info "Installing all modules..."
            echo ""
            local module
            for module in "${MODULES_ORDER[@]}"; do
                install_module "$module"
                echo ""
            done
            success "All modules installed"
            ;;
        install)
            if [[ "$CLI_TARGET" == */* ]]; then
                install_module "${CLI_TARGET%%/*}" "${CLI_TARGET#*/}"
            else
                install_module "$CLI_TARGET"
            fi
            ;;
        upgrade) cli_upgrade "$CLI_TARGET" ;;
        reinstall)
            if [[ -n "$CLI_TARGET" ]]; then
                cli_reinstall "$CLI_TARGET"
            else
                action_reinstall
            fi
            ;;
        uninstall)
            if [[ "$CLI_TARGET" == */* ]]; then
                uninstall_module "${CLI_TARGET%%/*}" "${CLI_TARGET#*/}"
            elif [[ -n "$CLI_TARGET" ]]; then
                uninstall_module "$CLI_TARGET"
            else
                action_uninstall
            fi
            ;;
        interactive) main_menu ;;
    esac
}

# Sourced by the tests, which call its functions alone
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
