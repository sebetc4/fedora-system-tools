#!/bin/bash
# =============================================================================
# FEDORA-SYSTEM-TOOLS SETUP - Interactive system tools management
# =============================================================================
# Main entry point for managing Fedora system tools.
# Provides an interactive menu to install, update, uninstall, and monitor
# modules and submodules. Also supports non-interactive CLI flags.
#
# Version: 0.1.0
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
#   ./setup.sh --upgrade clamav/quarantine    # Upgrade one submodule
#   ./setup.sh --reinstall clamav             # Reinstall all installed clamav subs
#   ./setup.sh --reinstall clamav/quarantine  # Reinstall one submodule
#   ./setup.sh --uninstall clamav/quarantine  # Uninstall one submodule
#   ./setup.sh --info clamav                  # Show module details
#   ./setup.sh --info clamav/quarantine       # Show submodule details
#   ./setup.sh --self-update                  # Update to latest release
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
readonly SCRIPT_DIR

# =============================================================================
# PRE-LIB FALLBACK UI
# =============================================================================
# setup.sh cannot source the shared lib before installing it, so it provides
# local UI helpers with the same conventions (colors + typed messages).

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_NC='\033[0m'

if [[ ! -t 1 ]]; then
    C_RED='' C_GREEN='' C_YELLOW='' C_CYAN='' C_BLUE='' C_BOLD='' C_DIM='' C_NC=''
fi

has_gum() { command -v gum &>/dev/null; }

warn()    { echo -e "${C_YELLOW}Warning: $1${C_NC}" >&2; }
error()   { echo -e "${C_RED}Error: $1${C_NC}" >&2; }
success() { echo -e "${C_GREEN}✓ $1${C_NC}"; }
info()    { echo -e "${C_BLUE}$1${C_NC}"; }

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

ui_header() {
    local title="$1"
    echo ""
    if has_gum; then
        gum style --border rounded --padding "0 2" --border-foreground 6 "$title"
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

# Fallback ui_choose (before lib is loaded)
ui_choose() {
    if has_gum; then
        gum choose "$@"
    else
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
# VERSION COMPARE
# =============================================================================

_version_compare() {
    local v1="$1" v2="$2"
    if [[ "$v1" == "$v2" ]]; then echo "eq"; return; fi

    local IFS='.'
    local -a V1 V2
    read -ra V1 <<< "$v1"
    read -ra V2 <<< "$v2"

    local i
    for i in 0 1 2; do
        local n1="${V1[$i]:-0}"
        local n2="${V2[$i]:-0}"
        if (( n1 < n2 )); then echo "lt"; return; fi
        if (( n1 > n2 )); then echo "gt"; return; fi
    done
    echo "eq"
}

# =============================================================================
# PRE-FLIGHT CHECKS
# =============================================================================

if [[ "$EUID" -eq 0 ]]; then
    error "Do not run this script as root."
    info "The script will use sudo when needed."
    exit 1
fi

# =============================================================================
# PARSE CLI ARGUMENTS
# =============================================================================

MODE="interactive"
CLI_TARGET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all) MODE="install-all"; shift ;;
        --list) MODE="list"; shift ;;
        --upgrade)
            MODE="upgrade"
            shift
            # Optional target: module or module/submodule
            if [[ $# -gt 0 && "$1" != --* ]]; then
                CLI_TARGET="$1"; shift
            fi
            ;;
        --install)
            MODE="install-target"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                CLI_TARGET="$1"; shift
            else
                error "--install requires a module or module/submodule argument"
                exit 1
            fi
            ;;
        --info)
            MODE="info"
            shift
            if [[ $# -gt 0 && "$1" != --* ]]; then
                CLI_TARGET="$1"; shift
            else
                error "--info requires a module or module/submodule argument"
                exit 1
            fi
            ;;
        --reinstall)
            MODE="reinstall"
            shift
            # Optional target: module or module/submodule
            if [[ $# -gt 0 && "$1" != --* ]]; then
                CLI_TARGET="$1"; shift
            fi
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            # Optional target
            if [[ $# -gt 0 && "$1" != --* ]]; then
                CLI_TARGET="$1"; shift
            fi
            ;;
        --self-update) MODE="self-update"; shift ;;
        --post-update) MODE="post-update"; shift ;;
        -h|--help)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  (none)                        Interactive menu"
            echo "  --all                         Install/upgrade all modules"
            echo "  --list                        List installed modules + submodules"
            echo "  --install <module[/sub]>      Install a module or submodule"
            echo "  --upgrade [module[/sub]]      Upgrade installed items"
            echo "  --reinstall [module[/sub]]    Force reinstall items"
            echo "  --uninstall [module[/sub]]    Uninstall items"
            echo "  --info <module[/sub]>         Show module or submodule details"
            echo "  --self-update                 Update to latest release"
            echo "  -h, --help                    Show this help"
            exit 0
            ;;
        *) shift ;;
    esac
done

# =============================================================================
# MODULE DISCOVERY
# =============================================================================
# Instead of hardcoding module metadata, discover from module.yml files.

declare -A MODULE_DESC
declare -A MODULE_TYPE
declare -A MODULE_DEPS
declare -A MODULE_STANDALONE
MODULES_ORDER=()

# Map module directory paths
declare -A MODULE_DIR_MAP

_discover_modules() {
    local yml_files=()

    # Standard module paths
    for dir in "$SCRIPT_DIR"/modules/*/; do
        [[ -f "$dir/module.yml" ]] && yml_files+=("$dir/module.yml")
    done
    # Nested modules (if any module.yml lives one level deeper)
    for dir in "$SCRIPT_DIR"/modules/*/*/; do
        [[ -f "$dir/module.yml" ]] && yml_files+=("$dir/module.yml")
    done

    for yml in "${yml_files[@]}"; do
        local name desc mtype standalone deps_str module_dir
        if command -v yq &>/dev/null; then
            name=$(yq -r '.name' "$yml")
            desc=$(yq -r '.description // ""' "$yml")
            mtype=$(yq -r '.type // "system"' "$yml")
            standalone=$(yq -r '.standalone // false' "$yml")
            deps_str=$(yq -r '.module_deps // [] | join(" ")' "$yml")
        else
            name=$(grep -oP '^name:\s*\K\S+' "$yml" 2>/dev/null) || continue
            desc=$(grep -oP '^description:\s*"\K[^"]+' "$yml" 2>/dev/null || echo "")
            mtype=$(grep -oP '^type:\s*\K\S+' "$yml" 2>/dev/null || echo "system")
            standalone="false"
            deps_str=""
        fi

        module_dir=$(dirname "$yml")
        MODULE_DIR_MAP[$name]="$module_dir"
        MODULE_DESC[$name]="$desc"
        MODULE_TYPE[$name]="$mtype"
        MODULE_DEPS[$name]="$deps_str"
        MODULE_STANDALONE[$name]="$standalone"
        MODULES_ORDER+=("$name")
    done
}

_discover_modules

# =============================================================================
# HELPERS
# =============================================================================

readonly LIB_DIR="/usr/local/lib/system-scripts"
readonly SYSTEM_REGISTRY="/etc/system-scripts/registry"
readonly USER_REGISTRY="$HOME/.config/system-scripts/registry"

get_installer() {
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    [[ -n "$mdir" ]] && echo "$mdir/install.sh" || echo ""
}

get_uninstaller() {
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    [[ -n "$mdir" ]] && echo "$mdir/uninstall.sh" || echo ""
}

get_available_version() {
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    if [[ -n "$mdir" && -f "$mdir/module.yml" ]] && command -v yq &>/dev/null; then
        yq -r '.version' "$mdir/module.yml" 2>/dev/null || echo "0.0.0"
    else
        local installer
        installer="$(get_installer "$module")"
        grep -oP '^(?:readonly )?MODULE_VERSION="\K[^"]+' "$installer" 2>/dev/null || echo "0.0.0"
    fi
}

get_installed_version() {
    local module="$1" registry="$2"
    [[ ! -f "$registry" ]] && return 1
    awk -v mod="[$module]" '
        BEGIN { found = 0 }
        /^\[/ { found = ($0 == mod) ? 1 : 0; next }
        found && /^version=/ { sub(/^version=/, ""); print; exit }
    ' "$registry"
}

get_install_date() {
    local module="$1" registry="$2"
    [[ ! -f "$registry" ]] && return 1
    awk -v mod="[$module]" '
        BEGIN { found = 0 }
        /^\[/ { found = ($0 == mod) ? 1 : 0; next }
        found && /^installed=/ { sub(/^installed=/, ""); print; exit }
    ' "$registry"
}

get_module_installed_version() {
    local module="$1"
    local ver=""
    ver="$(get_installed_version "$module" "$SYSTEM_REGISTRY" 2>/dev/null || echo "")"
    if [[ -z "$ver" ]]; then
        ver="$(get_installed_version "$module" "$USER_REGISTRY" 2>/dev/null || echo "")"
    fi
    echo "$ver"
}

get_module_install_date() {
    local module="$1"
    local date_val=""
    date_val="$(get_install_date "$module" "$SYSTEM_REGISTRY" 2>/dev/null || echo "")"
    if [[ -z "$date_val" ]]; then
        date_val="$(get_install_date "$module" "$USER_REGISTRY" 2>/dev/null || echo "")"
    fi
    echo "$date_val"
}

# Get submodule version from registry (inline — no lib dependency)
_get_submodule_installed_version() {
    local module="$1" submodule="$2"
    local ver=""
    ver="$(get_installed_version "${module}/${submodule}" "$SYSTEM_REGISTRY" 2>/dev/null || true)"
    if [[ -z "$ver" ]]; then
        ver="$(get_installed_version "${module}/${submodule}" "$USER_REGISTRY" 2>/dev/null || true)"
    fi
    echo "$ver"
}

# List installed submodules from registry
_list_installed_submodules() {
    local module="$1"
    for reg in "$SYSTEM_REGISTRY" "$USER_REGISTRY"; do
        [[ -f "$reg" ]] && grep -oP "^\[${module}/\K[^\]]+" "$reg" 2>/dev/null
    done
}

# Count total submodules defined in module.yml
_count_total_submodules() {
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    local module_yml="$mdir/module.yml"
    if command -v yq &>/dev/null && [[ -f "$module_yml" ]]; then
        yq -r '.submodules | keys | length' "$module_yml" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Count installed submodules for a module
_count_installed_submodules() {
    local module="$1"
    { _list_installed_submodules "$module" || true; } | wc -l
}

install_module() {
    local module="$1"
    local only_sub="${2:-}"

    # --- Check inter-module dependencies ---
    local deps="${MODULE_DEPS[$module]:-}"
    if [[ -n "$deps" ]]; then
        local missing=()
        for dep in $deps; do
            local dep_ver
            dep_ver="$(get_module_installed_version "$dep")"
            [[ -z "$dep_ver" ]] && missing+=("$dep")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            warn "Module '$module' requires: ${missing[*]}"
            if [[ "$MODE" == "interactive" ]]; then
                if ! ui_confirm "Install missing dependencies (${missing[*]}) before $module?"; then
                    info "Installation of '$module' cancelled."
                    return 0
                fi
            fi
            info "Installing dependencies first..."
            for dep in "${missing[@]}"; do
                install_module "$dep"
            done
        fi
    fi

    local installer
    installer="$(get_installer "$module")"

    if [[ -z "$installer" || ! -f "$installer" ]]; then
        warn "Module '$module' installer not found, skipping"
        return 0
    fi

    # --- Check minimum lib version ---
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    if [[ -n "$mdir" && -f "$mdir/module.yml" ]] && command -v yq &>/dev/null; then
        local min_lib
        min_lib=$(yq -r '.min_lib_version // ""' "$mdir/module.yml" 2>/dev/null)
        if [[ -n "$min_lib" && -n "${LIB_VERSION:-}" ]]; then
            local lib_cmp
            lib_cmp=$(_version_compare "${LIB_VERSION}" "$min_lib")
            if [[ "$lib_cmp" == "lt" ]]; then
                error "Module '$module' requires lib >= $min_lib (installed: $LIB_VERSION). Run: make install-lib" "exit"
            fi
        fi
    fi

    local cmd_args=()
    if [[ -n "$only_sub" ]]; then
        cmd_args=(--only "$only_sub")
    else
        cmd_args=(--all)
    fi
    [[ "${INSTALL_FORCE:-false}" == "true" ]] && cmd_args+=(--force)

    if [[ "${MODULE_TYPE[$module]}" == "system" ]]; then
        sudo "$installer" "${cmd_args[@]}"
    else
        "$installer" "${cmd_args[@]}"
    fi
}

uninstall_module() {
    local module="$1"
    local only_sub="${2:-}"

    # --- Check inter-module reverse dependencies ---
    # Block uninstall if another installed module depends on this one
    if [[ -z "$only_sub" ]]; then
        local dependents=()
        for other in "${MODULES_ORDER[@]}"; do
            [[ "$other" == "$module" ]] && continue
            local other_deps="${MODULE_DEPS[$other]:-}"
            [[ -z "$other_deps" ]] && continue
            local other_ver
            other_ver="$(get_module_installed_version "$other")"
            [[ -z "$other_ver" ]] && continue
            for dep in $other_deps; do
                if [[ "$dep" == "$module" ]]; then
                    dependents+=("$other")
                    break
                fi
            done
        done
        if [[ ${#dependents[@]} -gt 0 ]]; then
            error "Cannot uninstall '$module': required by installed module(s): ${dependents[*]}"
            info "Uninstall ${dependents[*]} first, or use --uninstall ${dependents[0]} to remove them."
            return 1
        fi
    fi

    local uninstaller
    uninstaller="$(get_uninstaller "$module")"

    if [[ -z "$uninstaller" || ! -f "$uninstaller" ]]; then
        warn "Module '$module' uninstaller not found"
        return 1
    fi

    local cmd_args=()
    if [[ -n "$only_sub" ]]; then
        cmd_args=(--only "$only_sub")
    else
        cmd_args=(--all)
    fi

    if [[ "${MODULE_TYPE[$module]}" == "system" ]]; then
        sudo "$uninstaller" "${cmd_args[@]}"
    else
        "$uninstaller" "${cmd_args[@]}"
    fi
}

# =============================================================================
# ENSURE LIBRARY IS INSTALLED
# =============================================================================

ensure_lib() {
    local lib_installed_ver=""
    if [[ -f "$SYSTEM_REGISTRY" ]]; then
        lib_installed_ver="$(get_installed_version "lib" "$SYSTEM_REGISTRY" || echo "")"
    fi

    local lib_available_ver
    lib_available_ver="$(grep -oP '^readonly LIB_VERSION="\K[^"]+' "$SCRIPT_DIR/lib/core.sh" 2>/dev/null || echo "0.1.0")"

    if [[ -n "$lib_installed_ver" ]]; then
        local cmp
        cmp="$(_version_compare "$lib_installed_ver" "$lib_available_ver")"
        if [[ "$cmp" == "lt" ]]; then
            info "Shared library upgrade available: v$lib_installed_ver -> v$lib_available_ver"
            if [[ "$MODE" == "interactive" ]]; then
                if ui_confirm "Upgrade shared library?"; then
                    if ! sudo bash "$SCRIPT_DIR/lib/install.sh"; then
                        error "Library upgrade failed"
                        exit 1
                    fi
                fi
            else
                if ! sudo bash "$SCRIPT_DIR/lib/install.sh"; then
                    error "Library upgrade failed"
                    exit 1
                fi
            fi
        fi
    elif [[ ! -f "$LIB_DIR/core.sh" ]] || [[ ! -d /etc/system-scripts ]]; then
        info "Installing shared library..."
        if ! sudo bash "$SCRIPT_DIR/lib/install.sh"; then
            error "Library installation failed"
            exit 1
        fi
    fi

    # Source lib for this script
    if [[ -f "$LIB_DIR/core.sh" ]]; then
        source "$LIB_DIR/core.sh"
        [[ -f "$LIB_DIR/ui.sh" ]] && source "$LIB_DIR/ui.sh"
    fi
}

# =============================================================================
# SHOW STATUS (with submodule detail)
# =============================================================================

show_status() {
    # --- Lib status ---
    local lib_ver=""
    if [[ -f "$SYSTEM_REGISTRY" ]]; then
        lib_ver="$(get_installed_version "lib" "$SYSTEM_REGISTRY" || echo "")"
    fi
    local lib_available
    lib_available="$(grep -oP '^readonly LIB_VERSION="\K[^"]+' "$SCRIPT_DIR/lib/core.sh" 2>/dev/null || echo "0.1.0")"

    if [[ -n "$lib_ver" ]]; then
        local lib_cmp
        lib_cmp="$(_version_compare "$lib_ver" "$lib_available")"
        if [[ "$lib_cmp" == "lt" ]]; then
            echo -e "  ${C_BOLD}lib${C_NC}  ${C_YELLOW}v$lib_ver → v$lib_available (update available)${C_NC}"
        else
            echo -e "  ${C_BOLD}lib${C_NC}  ${C_GREEN}v$lib_ver${C_NC}"
        fi
    elif [[ -f "$LIB_DIR/core.sh" ]]; then
        echo -e "  ${C_BOLD}lib${C_NC}  ${C_DIM}installed (pre-registry)${C_NC}"
    else
        echo -e "  ${C_BOLD}lib${C_NC}  ${C_RED}not installed${C_NC}"
    fi
    echo ""

    # --- Modules grouped ---
    for module in "${MODULES_ORDER[@]}"; do
        local mdir="${MODULE_DIR_MAP[$module]:-}"
        local is_standalone="${MODULE_STANDALONE[$module]:-false}"
        local module_yml="$mdir/module.yml"
        local desc="${MODULE_DESC[$module]:-}"

        # Module header
        echo -e "  ${C_BOLD}${C_CYAN}${module}${C_NC}  ${C_DIM}${desc}${C_NC}"
        echo ""

        if [[ "$is_standalone" == "true" ]]; then
            # Standalone module — table format
            local iver aver sub_status
            iver="$(get_module_installed_version "$module")"
            aver="$(get_available_version "$module")"

            printf "    ${C_BOLD}%-20s %-12s %-12s %s${C_NC}\n" "SUB-MODULE" "INSTALLED" "AVAILABLE" "STATUS"
            
            if [[ -n "$iver" ]]; then
                local cmp
                cmp="$(_version_compare "$iver" "${aver:-0.0.0}")"
                if [[ "$cmp" == "lt" ]]; then
                    sub_status="update available"
                    printf "    ${C_YELLOW}%-20s %-12s %-12s %s${C_NC}\n" "(standalone)" "v$iver" "v${aver:-?}" "$sub_status"
                else
                    printf "    ${C_GREEN}%-20s %-12s %-12s %s${C_NC}\n" "(standalone)" "v$iver" "v${aver:-?}" "✓"
                fi
            else
                printf "    ${C_DIM}%-20s %-12s %-12s %s${C_NC}\n" "(standalone)" "--" "v${aver:-?}" ""
            fi
        else
            # Module with submodules — table
            local submodules=() hooks_subs=()
            if command -v yq &>/dev/null && [[ -f "$module_yml" ]]; then
                mapfile -t submodules < <(
                    yq -r '.submodules | to_entries | map(select(.value.kind != "hook")) | .[].key' \
                        "$module_yml" 2>/dev/null)
                mapfile -t hooks_subs < <(
                    yq -r '.submodules | to_entries | map(select(.value.kind == "hook")) | .[].key' \
                        "$module_yml" 2>/dev/null)
            fi

            # Helper: print one submodule row
            _print_sub_row() {
                local sub="$1"
                local sub_iver sub_aver sub_status sub_color
                sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
                if command -v yq &>/dev/null; then
                    sub_aver=$(yq -r ".submodules.\"$sub\".version // \"?\"" "$module_yml")
                else
                    sub_aver="?"
                fi
                if [[ -n "$sub_iver" ]]; then
                    local cmp
                    cmp="$(_version_compare "$sub_iver" "${sub_aver:-0.0.0}")"
                    if [[ "$cmp" == "lt" ]]; then
                        sub_status="update available"
                        sub_color="$C_YELLOW"
                    else
                        sub_status="✓"
                        sub_color="$C_GREEN"
                    fi
                    printf "    ${sub_color}%-20s %-12s %-12s %s${C_NC}\n" \
                        "$sub" "v$sub_iver" "v$sub_aver" "$sub_status"
                else
                    printf "    ${C_DIM}%-20s %-12s %-12s %s${C_NC}\n" \
                        "$sub" "--" "v$sub_aver" ""
                fi
            }

            if [[ ${#submodules[@]} -gt 0 ]]; then
                printf "    ${C_BOLD}%-20s %-12s %-12s %s${C_NC}\n" "SUB-MODULE" "INSTALLED" "AVAILABLE" "STATUS"
                for sub in "${submodules[@]}"; do
                    _print_sub_row "$sub"
                done
            else
                # Fallback for modules without submodules
                local iver aver
                iver="$(get_module_installed_version "$module")"
                aver="$(get_available_version "$module")"
                printf "    ${C_BOLD}%-20s %-12s %-12s %s${C_NC}\n" "SUB-MODULE" "INSTALLED" "AVAILABLE" "STATUS"
                if [[ -n "$iver" ]]; then
                    printf "    ${C_GREEN}%-20s %-12s %-12s %s${C_NC}\n" "(all)" "v$iver" "v${aver:-?}" "✓"
                else
                    printf "    ${C_DIM}%-20s %-12s %-12s %s${C_NC}\n" "(all)" "--" "v${aver:-?}" ""
                fi
            fi

            if [[ ${#hooks_subs[@]} -gt 0 ]]; then
                echo ""
                printf "    ${C_BOLD}%-20s %-12s %-12s %s${C_NC}\n" "HOOKS" "INSTALLED" "AVAILABLE" "STATUS"
                for sub in "${hooks_subs[@]}"; do
                    _print_sub_row "$sub"
                done
            fi
        fi
        echo ""
    done
}

# =============================================================================
# SHOW INFO (detailed module/submodule view)
# =============================================================================

show_info() {
    local target="$1"
    local target_module target_sub=""

    if [[ "$target" == */* ]]; then
        target_module="${target%%/*}"
        target_sub="${target##*/}"
    else
        target_module="$target"
    fi

    local mdir="${MODULE_DIR_MAP[$target_module]:-}"
    if [[ -z "$mdir" ]]; then
        error "Unknown module: $target_module"
        return 1
    fi

    local module_yml="$mdir/module.yml"
    if [[ ! -f "$module_yml" ]] || ! command -v yq &>/dev/null; then
        error "Cannot read module.yml (yq required)"
        return 1
    fi

    local desc mtype mver standalone mdeps
    desc=$(yq -r '.description // ""' "$module_yml")
    mtype=$(yq -r '.type // "system"' "$module_yml")
    mver=$(yq -r '.version // "?"' "$module_yml")
    standalone=$(yq -r '.standalone // false' "$module_yml")
    mdeps=$(yq -r '.module_deps // [] | join(", ")' "$module_yml")

    if [[ -n "$target_sub" ]]; then
        # --- Submodule info ---
        local sub_ver sub_desc sub_type
        sub_ver=$(yq -r ".submodules.\"$target_sub\".version // \"\"" "$module_yml")
        if [[ -z "$sub_ver" ]]; then
            error "Unknown submodule: $target_module/$target_sub"
            return 1
        fi
        sub_desc=$(yq -r ".submodules.\"$target_sub\".description // \"\"" "$module_yml")
        sub_type=$(yq -r ".submodules.\"$target_sub\".type // \"$mtype\"" "$module_yml")

        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}${target_module}/${target_sub}${C_NC}"
        echo -e "  ${sub_desc}"
        echo ""
        echo -e "  ${C_BOLD}Version:${C_NC}     $sub_ver"
        echo -e "  ${C_BOLD}Type:${C_NC}        $sub_type"

        local sub_iver
        sub_iver="$(_get_submodule_installed_version "$target_module" "$target_sub")"
        if [[ -n "$sub_iver" ]]; then
            echo -e "  ${C_BOLD}Installed:${C_NC}   ${C_GREEN}v$sub_iver${C_NC}"
        else
            echo -e "  ${C_BOLD}Installed:${C_NC}   ${C_DIM}no${C_NC}"
        fi

        local bin_name
        bin_name=$(yq -r ".submodules.\"$target_sub\".bin_name // \"\"" "$module_yml")
        [[ -n "$bin_name" ]] && echo -e "  ${C_BOLD}Command:${C_NC}     $bin_name"

        local deps_str
        deps_str=$(yq -r ".submodules.\"$target_sub\".deps // [] | join(\", \")" "$module_yml")
        [[ -n "$deps_str" ]] && echo -e "  ${C_BOLD}Deps:${C_NC}        $deps_str"

        local sys_deps_str
        sys_deps_str=$(yq -r ".submodules.\"$target_sub\".system_deps // [] | join(\", \")" "$module_yml")
        [[ -n "$sys_deps_str" ]] && echo -e "  ${C_BOLD}System deps:${C_NC} $sys_deps_str"

        local services_str
        services_str=$(yq -r ".submodules.\"$target_sub\".services // [] | .[] | sub(\".*/\"; \"\")" "$module_yml" 2>/dev/null | paste -sd ", ")
        [[ -n "$services_str" ]] && echo -e "  ${C_BOLD}Services:${C_NC}    $services_str"

        local timers_str
        timers_str=$(yq -r ".submodules.\"$target_sub\".timers // [] | .[] | sub(\".*/\"; \"\")" "$module_yml" 2>/dev/null | paste -sd ", ")
        [[ -n "$timers_str" ]] && echo -e "  ${C_BOLD}Timers:${C_NC}      $timers_str"
        echo ""
    else
        # --- Module info ---
        echo ""
        echo -e "  ${C_BOLD}${C_CYAN}${target_module}${C_NC}"
        echo -e "  ${desc}"
        echo ""
        echo -e "  ${C_BOLD}Version:${C_NC}     $mver"
        echo -e "  ${C_BOLD}Type:${C_NC}        $mtype"

        local iver
        iver="$(get_module_installed_version "$target_module")"
        if [[ -n "$iver" ]]; then
            echo -e "  ${C_BOLD}Installed:${C_NC}   ${C_GREEN}v$iver${C_NC}"
        else
            echo -e "  ${C_BOLD}Installed:${C_NC}   ${C_DIM}no${C_NC}"
        fi

        [[ -n "$mdeps" ]] && echo -e "  ${C_BOLD}Module deps:${C_NC} $mdeps"

        if [[ "$standalone" == "true" ]]; then
            # --- Standalone: show scripts ---
            local script_keys=()
            mapfile -t script_keys < <(yq -r '.scripts // {} | keys | .[]' "$module_yml" 2>/dev/null)
            if [[ ${#script_keys[@]} -gt 0 ]]; then
                echo ""
                echo -e "  ${C_BOLD}Scripts:${C_NC}"
                for skey in "${script_keys[@]}"; do
                    local sdesc
                    sdesc=$(yq -r ".scripts.\"$skey\".description // \"\"" "$module_yml")
                    echo -e "    ${C_BOLD}$skey${C_NC} — $sdesc"
                done
            fi
        else
            # --- Submodule module: show submodules with details ---
            echo ""
            echo -e "  ${C_BOLD}Submodules:${C_NC}"
            local submodules=()
            mapfile -t submodules < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)
            for sub in "${submodules[@]}"; do
                local sv sd sub_iver sub_bin sub_type_override
                sv=$(yq -r ".submodules.\"$sub\".version // \"?\"" "$module_yml")
                sd=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
                sub_iver="$(_get_submodule_installed_version "$target_module" "$sub")"
                sub_bin=$(yq -r ".submodules.\"$sub\".bin_name // \"\"" "$module_yml")
                sub_type_override=$(yq -r ".submodules.\"$sub\".type // \"\"" "$module_yml")

                local status_icon sub_label
                if [[ -n "$sub_iver" ]]; then
                    status_icon="${C_GREEN}●${C_NC}"
                    sub_label="${C_GREEN}$sub${C_NC}"
                else
                    status_icon="${C_DIM}○${C_NC}"
                    sub_label="${C_DIM}$sub${C_NC}"
                fi

                local detail="v$sv — $sd"
                [[ -n "$sub_bin" ]] && detail="v$sv — $sd  ${C_DIM}→ $sub_bin${C_NC}"
                [[ -n "$sub_type_override" ]] && detail="$detail ${C_DIM}[$sub_type_override]${C_NC}"

                echo -e "    $status_icon $sub_label $detail"
            done

            echo ""
            echo -e "  ${C_DIM}● installed  ○ not installed${C_NC}"
        fi
        echo ""
    fi
}

action_info() {
    echo ""
    info "Available modules:"
    echo ""
    for module in "${MODULES_ORDER[@]}"; do
        echo -e "  ${C_BOLD}$module${C_NC} — ${MODULE_DESC[$module]}"
    done
    echo ""

    local choices=("${MODULES_ORDER[@]}" "Back")
    local choice
    choice="$(ui_choose --header "Select module to inspect:" "${choices[@]}")"

    case "$choice" in
        "Back"|"") return ;;
        *)
            show_info "$choice"
            ui_press_enter
            ;;
    esac
}

# =============================================================================
# INTERACTIVE SUBMODULE SELECTION (runs without root)
# =============================================================================
# For non-standalone modules, displays submodule status and lets the user
# select which to install BEFORE requesting sudo. Sets SUBMODULE_SELECTION
# to a comma-separated list of selected submodules.
# Returns 0 if selection was made, 1 if nothing to install or user cancelled.

_interactive_select_submodules() {
    SUBMODULE_SELECTION=""
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    local module_yml="$mdir/module.yml"
    local is_standalone="${MODULE_STANDALONE[$module]:-false}"

    # Standalone modules or no yq — skip selection, install everything
    if [[ "$is_standalone" == "true" ]] || ! command -v yq &>/dev/null || [[ ! -f "$module_yml" ]]; then
        return 0
    fi

    local module_version
    module_version=$(yq -r '.version // "?"' "$module_yml")

    # Read submodules
    local submodules=()
    mapfile -t submodules < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)

    [[ ${#submodules[@]} -eq 0 ]] && return 0

    info "Module: $module v$module_version"
    echo ""

    # Display submodule status and build available list
    local available=()
    for sub in "${submodules[@]}"; do
        local sub_desc sub_ver sub_iver
        sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
        sub_ver=$(yq -r ".submodules.\"$sub\".version // \"?\"" "$module_yml")
        sub_iver="$(_get_submodule_installed_version "$module" "$sub")"

        if [[ -n "$sub_iver" ]]; then
            local sub_cmp
            sub_cmp="$(_version_compare "$sub_iver" "$sub_ver")"
            if [[ "$sub_cmp" == "lt" ]]; then
                echo -e "  ${C_YELLOW}[installed v$sub_iver → v$sub_ver]${C_NC} $sub — $sub_desc"
                available+=("$sub")
            else
                echo -e "  ${C_GREEN}[installed v$sub_iver]${C_NC} $sub — $sub_desc"
            fi
        else
            echo -e "  ${C_DIM}[available v$sub_ver]${C_NC} $sub — $sub_desc"
            available+=("$sub")
        fi
    done
    echo ""

    if [[ ${#available[@]} -eq 0 ]]; then
        success "All submodules are up to date"
        ui_press_enter
        return 1
    fi

    # Interactive selection
    local selected=()
    local select_options=("All (install everything)" "${available[@]}")

    if has_gum; then
        mapfile -t selected < <(
            printf '%s\n' "${select_options[@]}" | \
            gum choose --no-limit --header "Select submodules to install:"
        )
    else
        echo -e "${C_BOLD}Select submodules to install:${C_NC}"
        echo "  Enter numbers separated by spaces, or 'all' for everything"
        echo ""
        local i=1
        echo -e "  ${C_BOLD}1)${C_NC} All (install everything)"
        ((i++))
        for sub in "${available[@]}"; do
            local sub_desc
            sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
            echo -e "  ${C_BOLD}$i)${C_NC} $sub — $sub_desc"
            ((i++))
        done
        echo ""
        local selection
        read -rp "Selection: " selection

        if [[ "$selection" == "all" || "$selection" == "1" ]]; then
            selected=("All (install everything)")
        else
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 2 && num <= ${#available[@]} + 1 )); then
                    selected+=("${available[$((num-2))]}")
                fi
            done
        fi
    fi

    [[ ${#selected[@]} -eq 0 ]] && return 1

    # Check if "All" was selected
    for s in "${selected[@]}"; do
        if [[ "$s" == "All (install everything)" ]]; then
            SUBMODULE_SELECTION=""
            return 0
        fi
    done

    local IFS=','
    SUBMODULE_SELECTION="${selected[*]}"
    return 0
}

# Select submodules to uninstall (interactive, pre-sudo)
# Sets SUBMODULE_SELECTION (comma-separated) or empty string for "all"
# Returns 1 if user cancels or nothing to uninstall
_interactive_select_submodules_uninstall() {
    SUBMODULE_SELECTION=""
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    local module_yml="$mdir/module.yml"
    local is_standalone="${MODULE_STANDALONE[$module]:-false}"

    # Standalone modules or no yq — uninstall everything
    if [[ "$is_standalone" == "true" ]] || ! command -v yq &>/dev/null || [[ ! -f "$module_yml" ]]; then
        return 0
    fi

    # Build list of installed submodules
    local submodules=()
    mapfile -t submodules < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)

    [[ ${#submodules[@]} -eq 0 ]] && return 0

    local installed=()
    for sub in "${submodules[@]}"; do
        local sub_iver
        sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
        [[ -n "$sub_iver" ]] && installed+=("$sub")
    done

    [[ ${#installed[@]} -eq 0 ]] && return 1

    # If only one submodule installed, no need for selection
    if [[ ${#installed[@]} -eq 1 ]]; then
        SUBMODULE_SELECTION="${installed[0]}"
        return 0
    fi

    info "Installed submodules for $module:"
    echo ""
    for sub in "${installed[@]}"; do
        local sub_desc sub_iver
        sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
        sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
        echo -e "  ${C_GREEN}$sub${C_NC} v$sub_iver — $sub_desc"
    done
    echo ""

    # Interactive selection
    local selected=()
    local select_options=("All (uninstall everything)" "${installed[@]}")

    if has_gum; then
        mapfile -t selected < <(
            printf '%s\n' "${select_options[@]}" | \
            gum choose --no-limit --header "Select submodules to uninstall:"
        )
    else
        echo -e "${C_BOLD}Select submodules to uninstall:${C_NC}"
        echo "  Enter numbers separated by spaces, or 'all' for everything"
        echo ""
        local i=1
        echo -e "  ${C_BOLD}1)${C_NC} All (uninstall everything)"
        ((i++))
        for sub in "${installed[@]}"; do
            local sub_desc
            sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
            echo -e "  ${C_BOLD}$i)${C_NC} $sub — $sub_desc"
            ((i++))
        done
        echo ""
        local selection
        read -rp "Selection: " selection

        if [[ "$selection" == "all" || "$selection" == "1" ]]; then
            selected=("All (uninstall everything)")
        else
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 2 && num <= ${#installed[@]} + 1 )); then
                    selected+=("${installed[$((num-2))]}")
                fi
            done
        fi
    fi

    [[ ${#selected[@]} -eq 0 ]] && return 1

    # Check if "All" was selected
    for s in "${selected[@]}"; do
        if [[ "$s" == "All (uninstall everything)" ]]; then
            SUBMODULE_SELECTION=""
            return 0
        fi
    done

    # --- Auto-add dependents ---
    # If a dependency is selected, auto-add submodules that depend on it
    local changed=true
    while [[ "$changed" == "true" ]]; do
        changed=false
        for sub in "${installed[@]}"; do
            # Skip if already selected
            local already=false
            for s in "${selected[@]}"; do
                [[ "$s" == "$sub" ]] && already=true && break
            done
            [[ "$already" == "true" ]] && continue

            # Check if any of this submodule's deps are in the selection
            local deps_str
            deps_str=$(yq -r ".submodules.\"$sub\".deps // [] | .[]" "$module_yml" 2>/dev/null)
            for dep in $deps_str; do
                for s in "${selected[@]}"; do
                    if [[ "$s" == "$dep" ]]; then
                        selected+=("$sub")
                        echo -e "  ${C_YELLOW}Adding $sub (depends on $dep)${C_NC}"
                        changed=true
                        break 3
                    fi
                done
            done
        done
    done

    # If all installed submodules are now selected, treat as "all"
    if [[ ${#selected[@]} -eq ${#installed[@]} ]]; then
        SUBMODULE_SELECTION=""
        return 0
    fi

    local IFS=','
    SUBMODULE_SELECTION="${selected[*]}"
    return 0
}

# Select submodules to reinstall (interactive, pre-sudo)
# Sets SUBMODULE_SELECTION (comma-separated) or empty string for "all"
# Returns 1 if user cancels or nothing to reinstall
_interactive_select_submodules_reinstall() {
    SUBMODULE_SELECTION=""
    local module="$1"
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    local module_yml="$mdir/module.yml"
    local is_standalone="${MODULE_STANDALONE[$module]:-false}"

    # Standalone modules or no yq — reinstall everything
    if [[ "$is_standalone" == "true" ]] || ! command -v yq &>/dev/null || [[ ! -f "$module_yml" ]]; then
        return 0
    fi

    # Build list of installed submodules
    local submodules=()
    mapfile -t submodules < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)

    [[ ${#submodules[@]} -eq 0 ]] && return 0

    local installed=()
    for sub in "${submodules[@]}"; do
        local sub_iver
        sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
        [[ -n "$sub_iver" ]] && installed+=("$sub")
    done

    [[ ${#installed[@]} -eq 0 ]] && return 1

    # If only one submodule installed, no need for selection
    if [[ ${#installed[@]} -eq 1 ]]; then
        SUBMODULE_SELECTION="${installed[0]}"
        return 0
    fi

    info "Installed submodules for $module:"
    echo ""
    for sub in "${installed[@]}"; do
        local sub_desc sub_iver
        sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
        sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
        echo -e "  ${C_GREEN}$sub${C_NC} v$sub_iver — $sub_desc"
    done
    echo ""

    # Interactive selection
    local selected=()
    local select_options=("All (reinstall everything)" "${installed[@]}")

    if has_gum; then
        mapfile -t selected < <(
            printf '%s\n' "${select_options[@]}" | \
            gum choose --no-limit --header "Select submodules to reinstall:"
        )
    else
        echo -e "${C_BOLD}Select submodules to reinstall:${C_NC}"
        echo "  Enter numbers separated by spaces, or 'all' for everything"
        echo ""
        local i=1
        echo -e "  ${C_BOLD}1)${C_NC} All (reinstall everything)"
        ((i++))
        for sub in "${installed[@]}"; do
            local sub_desc
            sub_desc=$(yq -r ".submodules.\"$sub\".description // \"\"" "$module_yml")
            echo -e "  ${C_BOLD}$i)${C_NC} $sub — $sub_desc"
            ((i++))
        done
        echo ""
        local selection
        read -rp "Selection: " selection

        if [[ "$selection" == "all" || "$selection" == "1" ]]; then
            selected=("All (reinstall everything)")
        else
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 2 && num <= ${#installed[@]} + 1 )); then
                    selected+=("${installed[$((num-2))]}")
                fi
            done
        fi
    fi

    [[ ${#selected[@]} -eq 0 ]] && return 1

    # Check if "All" was selected
    for s in "${selected[@]}"; do
        if [[ "$s" == "All (reinstall everything)" ]]; then
            SUBMODULE_SELECTION=""
            return 0
        fi
    done

    # If all installed submodules are now selected, treat as "all"
    if [[ ${#selected[@]} -eq ${#installed[@]} ]]; then
        SUBMODULE_SELECTION=""
        return 0
    fi

    local IFS=','
    SUBMODULE_SELECTION="${selected[*]}"
    return 0
}

# =============================================================================
# ACTION: INSTALL
# =============================================================================

action_install() {
    local available=()
    for module in "${MODULES_ORDER[@]}"; do
        local iver is_standalone
        iver="$(get_module_installed_version "$module")"
        is_standalone="${MODULE_STANDALONE[$module]:-false}"

        if [[ -z "$iver" ]]; then
            # Not installed at all
            available+=("$module")
        elif [[ "$is_standalone" != "true" ]]; then
            # Submodule-based: check if some submodules are still uninstalled
            local installed_count total_count
            installed_count="$(_count_installed_submodules "$module")"
            total_count="$(_count_total_submodules "$module")"
            if [[ "$total_count" -gt 0 && "$installed_count" -lt "$total_count" ]]; then
                available+=("$module")
            fi
        fi
    done

    if [[ ${#available[@]} -eq 0 ]]; then
        echo ""
        success "All modules are already installed"
        echo ""
        ui_press_enter
        return
    fi

    echo ""
    info "Modules available for installation:"
    echo ""
    for module in "${available[@]}"; do
        local aver iver is_standalone
        aver="$(get_available_version "$module")"
        iver="$(get_module_installed_version "$module")"
        is_standalone="${MODULE_STANDALONE[$module]:-false}"

        if [[ -n "$iver" && "$is_standalone" != "true" ]]; then
            local installed_count total_count
            installed_count="$(_count_installed_submodules "$module")"
            total_count="$(_count_total_submodules "$module")"
            echo -e "  ${C_BOLD}$module${C_NC} v${aver:-?} — ${MODULE_DESC[$module]} ${C_YELLOW}(${installed_count}/${total_count} submodules)${C_NC}"
        else
            echo -e "  ${C_BOLD}$module${C_NC} v${aver:-?} — ${MODULE_DESC[$module]}"
        fi
    done
    echo ""

    local choices=("All (install everything)" "${available[@]}" "Back")
    local choice
    choice="$(ui_choose --header "Select module to install:" "${choices[@]}")"

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
        "Back"|"")
            return
            ;;
        *)
            echo ""
            local is_standalone="${MODULE_STANDALONE[$choice]:-false}"
            if [[ "$is_standalone" != "true" ]]; then
                # Submodule selection BEFORE sudo prompt
                if _interactive_select_submodules "$choice"; then
                    if [[ -n "$SUBMODULE_SELECTION" ]]; then
                        install_module "$choice" "$SUBMODULE_SELECTION"
                    else
                        install_module "$choice"
                    fi
                fi
            else
                install_module "$choice"
            fi
            echo ""
            ;;
    esac
}

# =============================================================================
# ACTION: UPDATE
# =============================================================================

action_update() {
    # --- Step 1: Check for suite update (remote) ---
    echo ""
    info "Checking for suite updates..."
    local rc=0
    check_remote_version || rc=$?

    case $rc in
        0)
            # Update available
            echo ""
            echo -e "  ${C_YELLOW}Suite update available:${C_NC} v${SELF_UPDATE_CURRENT} → v${SELF_UPDATE_LATEST}"
            echo ""
            if ui_confirm "Update suite to v${SELF_UPDATE_LATEST}?"; then
                apply_self_update || {
                    error "Suite update failed, continuing with module updates..."
                }
                # Relaunch with updated script to upgrade modules
                echo ""
                info "Relaunching with updated version..."
                exec "${INSTALL_DIR}/setup.sh" --post-update
            fi
            ;;
        1)
            success "Suite is up to date (v${SELF_UPDATE_CURRENT})"
            ;;
        2)
            # Network error — skip silently, already warned in check_remote_version
            ;;
    esac

    echo ""

    # --- Step 2: Module updates (local) ---
    action_update_modules
}

# Check if a module has any update available (module-level or submodule-level)
# Returns: 0 = update available, 1 = up to date
_has_module_update() {
    local module="$1"
    local is_standalone="${MODULE_STANDALONE[$module]:-false}"

    if [[ "$is_standalone" != "true" ]]; then
        local mdir="${MODULE_DIR_MAP[$module]:-}"
        local module_yml="$mdir/module.yml"
        if command -v yq &>/dev/null && [[ -f "$module_yml" ]]; then
            local subs=()
            mapfile -t subs < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)
            for sub in "${subs[@]}"; do
                local sub_iver sub_aver
                sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
                [[ -z "$sub_iver" ]] && continue
                sub_aver=$(yq -r ".submodules.\"$sub\".version // \"0.0.0\"" "$module_yml")
                local cmp
                cmp="$(_version_compare "$sub_iver" "$sub_aver")"
                [[ "$cmp" == "lt" ]] && return 0
            done
        fi
    else
        local iver aver
        iver="$(get_module_installed_version "$module")"
        aver="$(get_available_version "$module")"
        local cmp
        cmp="$(_version_compare "$iver" "$aver")"
        [[ "$cmp" == "lt" ]] && return 0
    fi
    return 1
}

# Check and upgrade installed modules/submodules (local version comparison)
action_update_modules() {
    local updatable=()
    for module in "${MODULES_ORDER[@]}"; do
        local iver
        iver="$(get_module_installed_version "$module")"
        [[ -z "$iver" ]] && continue
        _has_module_update "$module" && updatable+=("$module")
    done

    if [[ ${#updatable[@]} -eq 0 ]]; then
        echo ""
        success "All modules are up to date"
        echo ""
        ui_press_enter
        return
    fi

    echo ""
    info "Modules with updates available:"
    echo ""
    for module in "${updatable[@]}"; do
        local is_standalone="${MODULE_STANDALONE[$module]:-false}"
        if [[ "$is_standalone" == "true" ]]; then
            local iver aver
            iver="$(get_module_installed_version "$module")"
            aver="$(get_available_version "$module")"
            echo -e "  ${C_YELLOW}$module${C_NC}  v$iver -> v$aver"
        else
            echo -e "  ${C_YELLOW}$module${C_NC}"
            local mdir="${MODULE_DIR_MAP[$module]:-}"
            local module_yml="$mdir/module.yml"
            local subs=()
            mapfile -t subs < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)
            for sub in "${subs[@]}"; do
                local sub_iver sub_aver
                sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
                [[ -z "$sub_iver" ]] && continue
                sub_aver=$(yq -r ".submodules.\"$sub\".version // \"0.0.0\"" "$module_yml")
                local cmp
                cmp="$(_version_compare "$sub_iver" "$sub_aver")"
                if [[ "$cmp" == "lt" ]]; then
                    echo -e "    ${C_YELLOW}$sub${C_NC}  v$sub_iver -> v$sub_aver"
                fi
            done
        fi
    done
    echo ""

    local choices=("All (update everything)" "${updatable[@]}" "Back")
    local choice
    choice="$(ui_choose --header "Select module to update:" "${choices[@]}")"

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
        "Back"|"")
            return
            ;;
        *)
            echo ""
            _upgrade_module "$choice"
            echo ""
            ;;
    esac
}

# Upgrade a single module: install only outdated submodules (or full module for standalone)
_upgrade_module() {
    local module="$1"
    local is_standalone="${MODULE_STANDALONE[$module]:-false}"

    if [[ "$is_standalone" == "true" ]]; then
        install_module "$module"
        return
    fi

    # Collect outdated submodules
    local mdir="${MODULE_DIR_MAP[$module]:-}"
    local module_yml="$mdir/module.yml"
    local outdated=()

    if command -v yq &>/dev/null && [[ -f "$module_yml" ]]; then
        local subs=()
        mapfile -t subs < <(yq -r '.submodules | keys | .[]' "$module_yml" 2>/dev/null)
        for sub in "${subs[@]}"; do
            local sub_iver sub_aver
            sub_iver="$(_get_submodule_installed_version "$module" "$sub")"
            [[ -z "$sub_iver" ]] && continue
            sub_aver=$(yq -r ".submodules.\"$sub\".version // \"0.0.0\"" "$module_yml")
            local cmp
            cmp="$(_version_compare "$sub_iver" "$sub_aver")"
            if [[ "$cmp" == "lt" ]]; then
                outdated+=("$sub")
            fi
        done
    fi

    if [[ ${#outdated[@]} -eq 0 ]]; then
        success "$module: all submodules are up to date"
        return
    fi

    # Install only the outdated submodules (comma-separated for --only)
    local only_list
    only_list=$(IFS=','; echo "${outdated[*]}")
    install_module "$module" "$only_list"
}

# =============================================================================
# ACTION: UNINSTALL
# =============================================================================

action_uninstall() {
    local installed=()
    for module in "${MODULES_ORDER[@]}"; do
        local iver
        iver="$(get_module_installed_version "$module")"
        [[ -n "$iver" ]] && installed+=("$module")
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo ""
        info "No modules installed"
        echo ""
        return
    fi

    echo ""
    info "Installed modules:"
    echo ""
    for module in "${installed[@]}"; do
        local iver
        iver="$(get_module_installed_version "$module")"
        echo -e "  ${C_GREEN}$module${C_NC} v$iver — ${MODULE_DESC[$module]}"

        # Show submodules
        local subs
        mapfile -t subs < <(_list_installed_submodules "$module")
        for sub in "${subs[@]}"; do
            [[ -z "$sub" ]] && continue
            local sub_ver
            sub_ver="$(_get_submodule_installed_version "$module" "$sub")"
            echo -e "    ${C_DIM}├─ $sub v${sub_ver:-?}${C_NC}"
        done
    done
    echo ""

    local choices=("All (uninstall everything)" "${installed[@]}" "Back")
    local choice
    choice="$(ui_choose --header "Select module to uninstall:" "${choices[@]}")"

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
        "Back"|"")
            return
            ;;
        *)
            echo ""
            local is_standalone="${MODULE_STANDALONE[$choice]:-false}"
            if [[ "$is_standalone" != "true" ]]; then
                if _interactive_select_submodules_uninstall "$choice"; then
                    if [[ -z "$SUBMODULE_SELECTION" ]]; then
                        # "All" selected
                        if ui_confirm "Uninstall all submodules of $choice?"; then
                            uninstall_module "$choice"
                        fi
                    else
                        if ui_confirm "Uninstall $choice submodule(s): ${SUBMODULE_SELECTION//,/, }?"; then
                            uninstall_module "$choice" "$SUBMODULE_SELECTION"
                        fi
                    fi
                fi
            else
                if ui_confirm "Uninstall $choice?"; then
                    uninstall_module "$choice"
                fi
            fi
            echo ""
            ;;
    esac
}

# =============================================================================
# ACTION: REINSTALL
# =============================================================================

action_reinstall() {
    local installed=()
    for module in "${MODULES_ORDER[@]}"; do
        local iver
        iver="$(get_module_installed_version "$module")"
        [[ -n "$iver" ]] && installed+=("$module")
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        echo ""
        info "No modules installed to reinstall"
        echo ""
        return
    fi

    echo ""
    info "Installed modules:"
    echo ""
    for module in "${installed[@]}"; do
        local iver
        iver="$(get_module_installed_version "$module")"
        echo -e "  ${C_GREEN}$module${C_NC} v$iver — ${MODULE_DESC[$module]}"

        # Show submodules
        local subs
        mapfile -t subs < <(_list_installed_submodules "$module")
        for sub in "${subs[@]}"; do
            [[ -z "$sub" ]] && continue
            local sub_ver
            sub_ver="$(_get_submodule_installed_version "$module" "$sub")"
            echo -e "    ${C_DIM}├─ $sub v${sub_ver:-?}${C_NC}"
        done
    done
    echo ""

    local choices=("${installed[@]}" "Back")
    local choice
    choice="$(ui_choose --header "Select module to reinstall:" "${choices[@]}")"

    case "$choice" in
        "Back"|"")
            return
            ;;
        *)
            echo ""
            local is_standalone="${MODULE_STANDALONE[$choice]:-false}"
            if [[ "$is_standalone" != "true" ]]; then
                if _interactive_select_submodules_reinstall "$choice"; then
                    if [[ -z "$SUBMODULE_SELECTION" ]]; then
                        # "All" selected
                        if ui_confirm "Reinstall all submodules of $choice?"; then
                            INSTALL_FORCE=true install_module "$choice"
                        fi
                    else
                        if ui_confirm "Reinstall $choice submodule(s): ${SUBMODULE_SELECTION//,/, }?"; then
                            INSTALL_FORCE=true install_module "$choice" "$SUBMODULE_SELECTION"
                        fi
                    fi
                fi
            else
                if ui_confirm "Reinstall $choice?"; then
                    INSTALL_FORCE=true install_module "$choice"
                fi
            fi
            echo ""
            ;;
    esac
}

# =============================================================================
# ACTION: COLORS
# =============================================================================

_color_valid() {
    local value="$1"
    # ANSI 0-255
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= 0 && value <= 255 )); then
        return 0
    fi
    # Hex #RRGGBB or #RGB
    if [[ "$value" =~ ^#[0-9a-fA-F]{3,6}$ ]]; then
        return 0
    fi
    return 1
}

_set_user_color() {
    local key="$1" value="$2"
    local conf="$HOME/.config/system-scripts/color.conf"
    mkdir -p "$(dirname "$conf")"

    if [[ -f "$conf" ]] && grep -q "^${key}=" "$conf" 2>/dev/null; then
        # Update existing key (value is validated, safe for sed)
        sed -i "s/^${key}=.*/${key}=${value}/" "$conf"
    else
        echo "${key}=${value}" >> "$conf"
    fi
}

_color_preview() {
    local eff_accent="${COLOR_ACCENT:-6}"
    local eff_error="${COLOR_ERROR:-1}"
    local eff_hdr_border="${COLOR_HEADER:-$eff_accent}"
    local eff_hdr_text="${COLOR_HEADER_TEXT:-}"
    local eff_sel_title="${COLOR_SELECTION_TITLE:-}"
    local eff_selection="${_CLR_CHOOSE_CURSOR_FG:-$eff_accent}"

    echo ""
    if has_gum; then
        local hdr_args=(gum style --border rounded --padding "0 1"
            --border-foreground "$eff_hdr_border")
        [[ -n "$eff_hdr_text" ]] && hdr_args+=(--foreground "$eff_hdr_text")
        "${hdr_args[@]}" "Header${COLOR_HEADER:+" border: $COLOR_HEADER"}${COLOR_HEADER:-" border (= accent)"}${eff_hdr_text:+", text: $eff_hdr_text"}"
        gum style --border rounded --padding "0 1" --border-foreground "$eff_accent" \
            "Accent: $eff_accent"
        if [[ -n "$eff_sel_title" ]]; then
            gum style --foreground "$eff_sel_title" \
                "Selection title: $eff_sel_title"
        else
            echo "  Selection title: (default)"
        fi
        gum style --foreground "$eff_selection" \
            "  > Selection: ${_CLR_CHOOSE_CURSOR_FG:-"(= accent)"}"
        gum style --border rounded --padding "0 1" --border-foreground "$eff_error" \
            "Error: $eff_error"
    else
        echo -e "  Header border: ${C_BOLD}${COLOR_HEADER:-"(= accent)"}${C_NC}"
        echo -e "  Header text:   ${C_BOLD}${eff_hdr_text:-"(default)"}${C_NC}"
        echo -e "  Accent:        ${C_BOLD}$eff_accent${C_NC}"
        echo -e "  Sel. title:    ${C_BOLD}${eff_sel_title:-"(default)"}${C_NC}"
        echo -e "  Selection:     ${C_BOLD}${_CLR_CHOOSE_CURSOR_FG:-"(= accent)"}${C_NC}"
        echo -e "  Error:         ${C_BOLD}$eff_error${C_NC}"
    fi
    echo ""
}

action_colors() {
    while true; do
        echo ""
        info "Current theme:"
        _color_preview

        local choices=(
            "Set accent color"
            "Set header border color"
            "Set header text color"
            "Set selection title color"
            "Set selection color"
            "Set error color"
            "Reset to defaults"
            "Back"
        )
        local choice
        choice="$(ui_choose --header "Color options:" "${choices[@]}")" || return

        case "$choice" in
            "Set accent color")
                local new_val
                if has_gum; then
                    new_val=$(gum input --header "Accent color (0-255 or #hex)" --value "${COLOR_ACCENT:-6}") || continue
                else
                    read -rp "Accent color (0-255 or #hex) [${COLOR_ACCENT:-6}]: " new_val
                    new_val="${new_val:-${COLOR_ACCENT:-6}}"
                fi
                if [[ -n "$new_val" ]] && _color_valid "$new_val"; then
                    _set_user_color "accent" "$new_val"
                    COLOR_ACCENT="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Accent: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Set header border color")
                local new_val
                local current_hdr="${COLOR_HEADER:-}"
                if has_gum; then
                    new_val=$(gum input --header "Header border color (0-255 or #hex, empty = accent)" --value "$current_hdr") || continue
                else
                    read -rp "Header border color (0-255 or #hex, empty = accent) [${current_hdr:-accent}]: " new_val
                fi
                if [[ -z "$new_val" ]]; then
                    _set_user_color "header_border" ""
                    COLOR_HEADER=""
                    type -t color_reload &>/dev/null && color_reload
                    success "Header border reset to accent"
                elif _color_valid "$new_val"; then
                    _set_user_color "header_border" "$new_val"
                    COLOR_HEADER="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Header border: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Set header text color")
                local new_val
                local current_txt="${COLOR_HEADER_TEXT:-}"
                if has_gum; then
                    new_val=$(gum input --header "Header text color (0-255 or #hex, empty = default)" --value "$current_txt") || continue
                else
                    read -rp "Header text color (0-255 or #hex, empty = default) [${current_txt:-default}]: " new_val
                fi
                if [[ -z "$new_val" ]]; then
                    _set_user_color "header_text" ""
                    COLOR_HEADER_TEXT=""
                    type -t color_reload &>/dev/null && color_reload
                    success "Header text reset to default"
                elif _color_valid "$new_val"; then
                    _set_user_color "header_text" "$new_val"
                    COLOR_HEADER_TEXT="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Header text: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Set selection title color")
                local new_val
                local current_title="${COLOR_SELECTION_TITLE:-}"
                if has_gum; then
                    new_val=$(gum input --header "Selection title color (0-255 or #hex, empty = default)" --value "$current_title") || continue
                else
                    read -rp "Selection title color (0-255 or #hex, empty = default) [${current_title:-default}]: " new_val
                fi
                if [[ -z "$new_val" ]]; then
                    _set_user_color "selection_title" ""
                    COLOR_SELECTION_TITLE=""
                    type -t color_reload &>/dev/null && color_reload
                    success "Selection title reset to default"
                elif _color_valid "$new_val"; then
                    _set_user_color "selection_title" "$new_val"
                    COLOR_SELECTION_TITLE="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Selection title color: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Set selection color")
                local new_val
                local current_sel="${_CLR_CHOOSE_CURSOR_FG:-}"
                if has_gum; then
                    new_val=$(gum input --header "Selection color (0-255 or #hex, empty = accent)" --value "$current_sel") || continue
                else
                    read -rp "Selection color (0-255 or #hex, empty = accent) [${current_sel:-accent}]: " new_val
                fi
                if [[ -z "$new_val" ]]; then
                    _set_user_color "choose_cursor_foreground" ""
                    _set_user_color "choose_selected_foreground" ""
                    _CLR_CHOOSE_CURSOR_FG=""
                    _CLR_CHOOSE_SELECTED_FG=""
                    type -t color_reload &>/dev/null && color_reload
                    success "Selection color reset to accent"
                elif _color_valid "$new_val"; then
                    _set_user_color "choose_cursor_foreground" "$new_val"
                    _set_user_color "choose_selected_foreground" "$new_val"
                    _CLR_CHOOSE_CURSOR_FG="$new_val"
                    _CLR_CHOOSE_SELECTED_FG="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Selection color: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Set error color")
                local new_val
                if has_gum; then
                    new_val=$(gum input --header "Error color (0-255 or #hex)" --value "${COLOR_ERROR:-1}") || continue
                else
                    read -rp "Error color (0-255 or #hex) [${COLOR_ERROR:-1}]: " new_val
                    new_val="${new_val:-${COLOR_ERROR:-1}}"
                fi
                if [[ -n "$new_val" ]] && _color_valid "$new_val"; then
                    _set_user_color "error" "$new_val"
                    COLOR_ERROR="$new_val"
                    type -t color_reload &>/dev/null && color_reload
                    success "Error color: $new_val"
                else
                    warn "Invalid color value"
                fi
                ;;
            "Reset to defaults")
                local user_conf="$HOME/.config/system-scripts/color.conf"
                if [[ -f "$user_conf" ]]; then
                    rm -f "$user_conf"
                    COLOR_ACCENT="#4f9872"
                    COLOR_HEADER="#4f9872"
                    COLOR_HEADER_TEXT="#ECEEEC"
                    COLOR_ERROR=1
                    COLOR_SELECTION_TITLE="#4f9872"
                    _CLR_CHOOSE_CURSOR_FG="#CBB99F"
                    _CLR_CHOOSE_SELECTED_FG="#CBB99F"
                    type -t color_reload &>/dev/null && color_reload
                    success "Colors reset to defaults"
                else
                    info "Already using defaults"
                fi
                ;;
            "Back"|"") return ;;
        esac
    done
}

# =============================================================================
# MAIN MENU (interactive loop)
# =============================================================================

main_menu() {
    while true; do
        ui_header "Fedora System Scripts - Setup"

        local choice
        choice="$(ui_choose --header "What would you like to do?" \
            "Status      View system status + submodules" \
            "Install     Install new modules" \
            "Update      Check for updates (suite + modules)" \
            "Uninstall   Remove installed modules" \
            "Info        Show module details" \
            "Reinstall   Force reinstall a module" \
            "Colors      Customize UI theme" \
            "Quit")"

        # Extract action (first word)
        local action
        action="$(echo "$choice" | awk '{print $1}')"

        case "$action" in
            Status)
                ui_header "System Status"
                show_status
                echo ""
                read -rp "Press Enter to continue..."
                ;;
            Install)   action_install ;;
            Update)    action_update ;;
            Uninstall) action_uninstall ;;
            Info)      action_info ;;
            Reinstall) action_reinstall ;;
            Colors)    action_colors ;;
            Quit|"")   echo ""; success "Bye!"; echo ""; exit 0 ;;
        esac
    done
}

# =============================================================================
# ENTRY POINT
# =============================================================================

# Always ensure lib is installed first (except for --list which is read-only)
if [[ "$MODE" != "list" ]]; then
    ensure_lib
fi

# Validate CLI target if provided
if [[ -n "$CLI_TARGET" ]]; then
    _validate_target="${CLI_TARGET%%/*}"
    if [[ -z "${MODULE_DIR_MAP[$_validate_target]:-}" ]]; then
        error "Unknown module: $_validate_target"
        info "Available modules: ${MODULES_ORDER[*]}"
        exit 1
    fi
fi

# =============================================================================
# SELF-UPDATE
# =============================================================================

readonly GITHUB_REPO="sebetc4/fedora-system-tools"
readonly INSTALL_DIR="/opt/fedora-system-tools"

# Check if a newer release is available on GitHub
# Sets SELF_UPDATE_TAG and SELF_UPDATE_LATEST on success
# Returns: 0 = update available, 1 = up to date, 2 = error
check_remote_version() {
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

    local response
    response=$(curl -sSL --max-time 10 "$api_url" 2>/dev/null) || {
        warn "Could not reach GitHub API (network issue?)"
        return 2
    }

    local tag
    tag=$(echo "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | grep -o '"v[^"]*"' | tr -d '"')

    if [[ -z "$tag" ]]; then
        warn "Could not determine latest release"
        return 2
    fi

    local latest_version="${tag#v}"
    local current_version=""
    if [[ -f "${INSTALL_DIR}/.version" ]]; then
        current_version=$(cat "${INSTALL_DIR}/.version")
    fi

    SELF_UPDATE_TAG="$tag"
    SELF_UPDATE_LATEST="$latest_version"
    SELF_UPDATE_CURRENT="${current_version:-unknown}"

    if [[ "$current_version" == "$latest_version" ]]; then
        return 1
    fi
    return 0
}

# Download and apply the update (uses SELF_UPDATE_TAG/SELF_UPDATE_LATEST)
apply_self_update() {
    local tag="$SELF_UPDATE_TAG"
    local latest_version="$SELF_UPDATE_LATEST"

    local tarball="fedora-system-tools-${latest_version}.tar.gz"
    local download_url="https://github.com/${GITHUB_REPO}/releases/download/${tag}/${tarball}"
    local tmp_dir
    tmp_dir=$(mktemp -d)

    info "Downloading ${tarball}..."
    if ! curl -sSL -o "${tmp_dir}/${tarball}" "$download_url"; then
        error "Failed to download release"
        rm -rf "$tmp_dir"
        return 1
    fi

    info "Updating ${INSTALL_DIR}..."
    sudo rm -rf "${INSTALL_DIR:?}/lib" "${INSTALL_DIR:?}/modules" "${INSTALL_DIR:?}/setup.sh" "${INSTALL_DIR:?}/Makefile"
    sudo tar xzf "${tmp_dir}/${tarball}" -C "$INSTALL_DIR" --strip-components=1
    echo "$latest_version" | sudo tee "${INSTALL_DIR}/.version" > /dev/null
    sudo chmod +x "${INSTALL_DIR}/setup.sh"

    # --- Reinstall shared library ---
    info "Updating shared library..."
    sudo "${INSTALL_DIR}/lib/install.sh"

    # --- Ensure symlink ---
    sudo ln -sf "${INSTALL_DIR}/setup.sh" "/usr/local/bin/system-tools"

    rm -rf "$tmp_dir"
    success "Updated to v${latest_version}"
}

# CLI self-update: check + apply + hint
self_update() {
    info "Checking for updates..."

    local rc=0
    check_remote_version || rc=$?

    case $rc in
        1)
            success "Already up to date (v${SELF_UPDATE_CURRENT})"
            return 0
            ;;
        2) return 1 ;;
    esac

    info "Current: v${SELF_UPDATE_CURRENT} → Latest: v${SELF_UPDATE_LATEST}"
    apply_self_update || return 1

    echo ""
    info "Run 'system-tools --upgrade' to upgrade installed modules"
}

# Non-interactive modes
case "$MODE" in
    self-update)
        self_update
        exit $?
        ;;
    post-update)
        # Relaunched after self-update: go straight to module upgrades
        success "Suite updated successfully"
        echo ""
        action_update_modules
        exit 0
        ;;
    list)
        # Source lib if available (for colors)
        if [[ -f "$LIB_DIR/core.sh" ]]; then
            source "$LIB_DIR/core.sh"
        fi
        ui_header "Fedora System Scripts - Status"
        show_status
        exit 0
        ;;
    install-all)
        info "Installing all modules..."
        echo ""
        for module in "${MODULES_ORDER[@]}"; do
            install_module "$module"
            echo ""
        done
        success "All modules installed"
        exit 0
        ;;
    install-target)
        # Parse module/submodule
        if [[ "$CLI_TARGET" == */* ]]; then
            target_module="${CLI_TARGET%%/*}"
            target_sub="${CLI_TARGET##*/}"
            install_module "$target_module" "$target_sub"
        else
            # Module-only: use interactive selection for submodule-based modules
            if [[ "${MODULE_STANDALONE[$CLI_TARGET]:-false}" != "true" ]]; then
                if _interactive_select_submodules "$CLI_TARGET"; then
                    if [[ -n "$SUBMODULE_SELECTION" ]]; then
                        install_module "$CLI_TARGET" "$SUBMODULE_SELECTION"
                    else
                        install_module "$CLI_TARGET"
                    fi
                fi
            else
                install_module "$CLI_TARGET"
            fi
        fi
        exit 0
        ;;
    info)
        # Source lib if available
        if [[ -f "$LIB_DIR/core.sh" ]]; then
            source "$LIB_DIR/core.sh"
        fi
        show_info "$CLI_TARGET"
        exit 0
        ;;
    upgrade)
        if [[ -n "$CLI_TARGET" ]]; then
            # Upgrade specific target
            if [[ "$CLI_TARGET" == */* ]]; then
                target_module="${CLI_TARGET%%/*}"
                target_sub="${CLI_TARGET##*/}"
                install_module "$target_module" "$target_sub"
            else
                install_module "$CLI_TARGET"
            fi
        else
            info "Checking for upgrades..."
            echo ""
            UPGRADED=0
            for module in "${MODULES_ORDER[@]}"; do
                installed_ver="$(get_module_installed_version "$module")"
                [[ -z "$installed_ver" ]] && continue

                if _has_module_update "$module"; then
                    _upgrade_module "$module"
                    echo ""
                    UPGRADED=$((UPGRADED + 1))
                else
                    echo -e "  ${C_DIM}$module v$installed_ver (up to date)${C_NC}"
                fi
            done
            echo ""
            if [[ $UPGRADED -eq 0 ]]; then
                success "All modules are up to date"
            else
                success "$UPGRADED module(s) upgraded"
            fi
        fi
        exit 0
        ;;
    reinstall)
        if [[ -n "$CLI_TARGET" ]]; then
            if [[ "$CLI_TARGET" == */* ]]; then
                target_module="${CLI_TARGET%%/*}"
                target_sub="${CLI_TARGET##*/}"
                INSTALL_FORCE=true install_module "$target_module" "$target_sub"
            else
                # Module-only: interactive selection for submodule-based modules
                if [[ "${MODULE_STANDALONE[$CLI_TARGET]:-false}" != "true" ]]; then
                    ensure_lib
                    if _interactive_select_submodules_reinstall "$CLI_TARGET"; then
                        if [[ -z "$SUBMODULE_SELECTION" ]]; then
                            INSTALL_FORCE=true install_module "$CLI_TARGET"
                        else
                            INSTALL_FORCE=true install_module "$CLI_TARGET" "$SUBMODULE_SELECTION"
                        fi
                    fi
                else
                    INSTALL_FORCE=true install_module "$CLI_TARGET"
                fi
            fi
        else
            ensure_lib
            action_reinstall
        fi
        exit 0
        ;;
    uninstall)
        if [[ -n "$CLI_TARGET" ]]; then
            if [[ "$CLI_TARGET" == */* ]]; then
                target_module="${CLI_TARGET%%/*}"
                target_sub="${CLI_TARGET##*/}"
                uninstall_module "$target_module" "$target_sub"
            else
                # Module-only: use interactive selection for submodule-based modules
                if [[ "${MODULE_STANDALONE[$CLI_TARGET]:-false}" != "true" ]]; then
                    ensure_lib
                    if _interactive_select_submodules_uninstall "$CLI_TARGET"; then
                        if [[ -z "$SUBMODULE_SELECTION" ]]; then
                            uninstall_module "$CLI_TARGET"
                        else
                            uninstall_module "$CLI_TARGET" "$SUBMODULE_SELECTION"
                        fi
                    fi
                else
                    uninstall_module "$CLI_TARGET"
                fi
            fi
        else
            ensure_lib
            action_uninstall
        fi
        exit 0
        ;;
esac

# Interactive mode
main_menu
