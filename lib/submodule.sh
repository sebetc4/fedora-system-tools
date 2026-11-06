#!/bin/bash
# =============================================================================
# SUBMODULE.SH - Submodule install/uninstall/update engine
# =============================================================================
# Generic functions to install, uninstall, and update submodules declared
# in module.yml. Each module's install.sh becomes a thin orchestrator that
# calls these functions.
#
# An uninstall removes what module.yml declares and nothing else: binaries,
# units, logrotate configs, declared directories, the hook scripts the module
# ships, and the folders of the user's home they needed once those are empty.
# Config files stay.
#
# Requires: yq (for parsing module.yml), core.sh, registry.sh, notify.sh
# Usage: source "$LIB_DIR/submodule.sh"
#
# Includes double-sourcing protection.
# =============================================================================

# Double-sourcing guard
[[ -n "${_LIB_SUBMODULE_LOADED:-}" ]] && return 0
readonly _LIB_SUBMODULE_LOADED=1

source "$(dirname "${BASH_SOURCE[0]}")/core.sh"
source "$(dirname "${BASH_SOURCE[0]}")/registry.sh"
source "$(dirname "${BASH_SOURCE[0]}")/notify.sh"

# =============================================================================
# MODULE.YML PARSING (yq wrappers)
# =============================================================================

# Get a top-level field from module.yml
# Args: field [module_yml_path]
module_get() {
    local field="$1"
    local yml="${2:-module.yml}"
    yq -r ".$field // \"\"" "$yml"
}

# Get a submodule-level field from module.yml
# Args: submodule_name field [module_yml_path]
submodule_get() {
    local submodule="$1"
    local field="$2"
    local yml="${3:-module.yml}"
    yq -r ".submodules.\"$submodule\".$field // \"\"" "$yml"
}

# List all submodule names from module.yml
# Args: [module_yml_path]
# Output: one name per line
submodule_list() {
    local yml="${1:-module.yml}"
    yq -r '.submodules // {} | keys | .[]' "$yml"
}

# Get a submodule array field as newline-separated values
# Args: submodule_name field [module_yml_path]
submodule_get_array() {
    local submodule="$1"
    local field="$2"
    local yml="${3:-module.yml}"
    yq -r ".submodules.\"$submodule\".$field // [] | .[]" "$yml"
}

# =============================================================================
# USER CONTEXT
# =============================================================================
# The engine runs as root under sudo and acts for SUDO_USER. Submodules can
# declare `type: user` in module.yml to override the module's default type:
# they install to user paths (~/.local/bin, ~/.config/systemd/user/), use
# systemctl --user and the user registry. Whatever the type, a file written
# in the user's home is written by the user, its missing parents included.
#
# Context variables (set by _submodule_resolve_context, local to the
# submodule_install or submodule_uninstall call that resolved them):
#   _sub_type    — "system" or "user"
#   _real_user   — target user (SUDO_USER or USER)
#   _real_home   — target user's home directory
#   _real_uid    — target user's UID

# Print a submodule's type: its own, or the module's, "system" by default
# Args: submodule_name module_yml
_submodule_type() {
    local type
    type=$(submodule_get "$1" "type" "$2")
    [[ -n "$type" ]] || type=$(module_get "type" "$2")
    echo "${type:-system}"
}

# Print the user an install acts for: SUDO_USER under sudo, the caller
# otherwise, by id since USER may be unset, as in a container
_submodule_user() {
    echo "${SUDO_USER:-$(id -un)}"
}

# Print the home of the user an install acts for
_submodule_user_home() {
    local user home
    user=$(_submodule_user)
    home=$(getent passwd "$user" | cut -d: -f6) || true
    if [[ -z "$home" ]]; then
        _sub_error "No home found for user '$user'"
        return 1
    fi
    echo "$home"
}

# Resolve type and user context for a submodule. The caller declares the
# context variables local first, so a dependency installed meanwhile keeps
# its own context and leaves the caller's untouched.
# Args: submodule_name module_yml
# Sets: _sub_type, _real_user, _real_home, _real_uid
_submodule_resolve_context() {
    _sub_type=$(_submodule_type "$1" "$2")
    _real_user=$(_submodule_user)
    _real_home=$(_submodule_user_home) || return 1
    _real_uid=$(id -u "$_real_user")
}

# Run a command as the user: through runuser when root acts for another
# user, directly otherwise
# Uses _real_user
_as_user() {
    if [[ $EUID -eq 0 && "$_real_user" != "root" ]]; then
        runuser -u "$_real_user" -- "$@"
    else
        "$@"
    fi
}

# Run a command as the user when <path> lies in the user's home, as the
# caller otherwise
# Args: path command...
# Uses _real_home, _real_user
_submodule_owner_run() {
    local path="$1"
    shift
    if [[ "$path" == "$_real_home"/* ]]; then
        _as_user "$@"
    else
        "$@"
    fi
}

# Write stdin to a file with a mode, as its owner per _submodule_owner_run
# Args: dest mode
_submodule_write() {
    local dest="$1" mode="$2"
    _submodule_owner_run "$dest" tee "$dest" > /dev/null
    _submodule_owner_run "$dest" chmod "$mode" "$dest"
}

# Print a template with __HOME__ and __USER__ replaced by the user's
# Args: template_path
_submodule_render() {
    sed -e "s|__HOME__|$_real_home|g" -e "s|__USER__|$_real_user|g" "$1"
}

# Run systemctl with user/system context
# Uses _sub_type, _real_user, _real_uid
_systemctl_cmd() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        _as_user env XDG_RUNTIME_DIR="/run/user/$_real_uid" systemctl --user "$@"
    else
        systemctl "$@"
    fi
}

# Get bin_path based on submodule type
# Uses _sub_type, _real_home
_submodule_bin_path() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        echo "$_real_home/.local/bin"
    else
        echo "/usr/local/bin"
    fi
}

# Get systemd unit directory based on submodule type
# Uses _sub_type, _real_home
_submodule_systemd_dir() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        echo "$_real_home/.config/systemd/user"
    else
        echo "/etc/systemd/system"
    fi
}

# Expand a leading ~/ to the user's home
# Args: path
# Uses _real_home
_submodule_expand_path() {
    local path="$1"
    # shellcheck disable=SC2088  # Tilde is a literal prefix from YAML, not shell expansion
    if [[ "$path" == "~/"* ]]; then
        echo "${_real_home}/${path#\~/}"
    else
        echo "$path"
    fi
}

# Print the destination of a submodule's logrotate config: its file name, and
# for a template, the user's name before it (bitwarden/logrotate/
# backup-bitwarden.tpl gives /etc/logrotate.d/<user>-backup-bitwarden)
# Args: logrotate_path
# Uses _real_user
_submodule_logrotate_dest() {
    local name
    name=$(basename "$1")
    if [[ "$name" == *.tpl ]]; then
        echo "/etc/logrotate.d/${_real_user}-${name%.tpl}"
    else
        echo "/etc/logrotate.d/$name"
    fi
}

# Print the unit names a submodule installs: its timers, then its services,
# templates under their rendered name
# Args: submodule_name module_yml
_submodule_units() {
    local unit
    while IFS= read -r unit; do
        [[ -n "$unit" ]] || continue
        unit=$(basename "$unit")
        echo "${unit%.tpl}"
    done < <(submodule_get_array "$1" "timers" "$2"; submodule_get_array "$1" "services" "$2")
}

# =============================================================================
# REGISTRY ACCESS
# =============================================================================

# Run a registry function against the registry of a submodule's type: the
# user's for type user, the default one otherwise
# Args: submodule_name module_yml registry_function args...
_submodule_registry() {
    local submodule="$1" module_yml="$2" home
    shift 2
    if [[ "$(_submodule_type "$submodule" "$module_yml")" == "user" ]]; then
        home=$(_submodule_user_home) || return 1
        REGISTRY_PATH_OVERRIDE="$home/.config/system-scripts/registry" "$@"
    else
        "$@"
    fi
}

# Check if a submodule is installed, using the correct registry for its type
# Args: module_name submodule_name module_yml
_is_sub_installed() {
    _submodule_registry "$2" "$3" registry_is_submodule_installed "$1" "$2"
}

# Get submodule version from the correct registry for its type
# Args: module_name submodule_name module_yml
_get_sub_version() {
    _submodule_registry "$2" "$3" registry_get_submodule_version "$1" "$2"
}

# Print the installed submodules that depend on a submodule
# Args: module_name submodule_name module_yml
_submodule_dependents() {
    local module_name="$1" submodule="$2" module_yml="$3" other
    while IFS= read -r other; do
        [[ "$other" == "$submodule" ]] && continue
        submodule_get_array "$other" "deps" "$module_yml" | grep -qxF -- "$submodule" || continue
        if _is_sub_installed "$module_name" "$other" "$module_yml"; then
            echo "$other"
        fi
    done < <(submodule_list "$module_yml")
}

# =============================================================================
# DEPENDENCY CHECKS
# =============================================================================

# Print the packages of a list that nothing installed provides
# Args: package...
_submodule_missing_packages() {
    local pkg
    for pkg in "$@"; do
        [[ -n "$pkg" ]] || continue
        rpm -q --quiet --whatprovides "$pkg" 2>/dev/null || echo "$pkg"
    done
}

# Succeed when a command is found, in the caller's PATH or in the user's
# login PATH, where npm, pip and cargo put theirs
# Args: command
# Uses _real_user
_submodule_has_command() {
    command -v "$1" &>/dev/null && return 0
    [[ $EUID -eq 0 && "$_real_user" != "root" ]] || return 1
    # shellcheck disable=SC2016  # $1 expands in the user's shell
    _as_user bash -lc 'command -v "$1"' _ "$1" &>/dev/null
}

# =============================================================================
# REMOVAL GUARDS
# =============================================================================

# Succeed when a declared directory may be removed with its content: an
# absolute path with no "." or ".." component, two levels deep at least,
# two levels below the user's home when it lies in it, and owned by no
# package (/var/log, /etc/logrotate.d...)
# Args: dir
# Uses _real_home
_submodule_removable_dir() {
    local dir="${1%/}"
    [[ "$dir" == /?*/?* ]] || return 1
    [[ "$dir/" != */./* && "$dir/" != */../* && "$dir" != *//* ]] || return 1
    if [[ "$dir" == "$_real_home" || "$dir" == "$_real_home"/* ]]; then
        [[ "$dir" == "$_real_home"/?*/?* ]] || return 1
    fi
    ! rpm -qf "$dir" &>/dev/null
}

# Remove a directory of the user's home, then each parent, while they are
# empty, stopping above the home's direct children (~/.config, ~/.local).
# A directory already gone hands over to its parent.
# Args: dir
# Uses _real_home
_submodule_prune_home_dir() {
    local dir="${1%/}"
    [[ -n "${_real_home:-}" ]] || return 0
    while [[ "$dir" == "$_real_home"/?*/?* ]]; do
        if [[ -d "$dir" ]]; then
            rmdir "$dir" 2>/dev/null || return 0
        fi
        dir=$(dirname "$dir")
    done
}

# =============================================================================
# UNINSTALL ORDERING
# =============================================================================

# Sort submodules for uninstall: dependencies last, at any depth
# Args: module_yml submodule_names...
# Output: sorted names (one per line). Each pass emits, in the given order,
# the submodules no pending one depends on; a dependency cycle, which no
# pass can break, is emitted as it stands.
submodule_sort_uninstall() {
    local module_yml="$1"
    shift
    local pending=("$@")
    local -A deps_of=()
    local sub other needed
    for sub in "${pending[@]}"; do
        deps_of[$sub]=" $(submodule_get_array "$sub" "deps" "$module_yml" | tr '\n' ' ')"
    done

    while (( ${#pending[@]} > 0 )); do
        local emitted=() held=()
        for sub in "${pending[@]}"; do
            needed=false
            for other in "${pending[@]}"; do
                if [[ "$other" != "$sub" && "${deps_of[$other]}" == *" $sub "* ]]; then
                    needed=true
                    break
                fi
            done
            if [[ "$needed" == "true" ]]; then
                held+=("$sub")
            else
                emitted+=("$sub")
            fi
        done
        if (( ${#emitted[@]} == 0 )); then
            emitted=("${held[@]}")
            held=()
        fi
        printf '%s\n' "${emitted[@]}"
        pending=("${held[@]}")
    done
}

# =============================================================================
# INDENTED OUTPUT HELPERS (used inside submodule install/uninstall)
# =============================================================================

_sub_success() { echo -e "  ${C_GREEN}✓ $1${C_NC}"; }
_sub_info()    { echo -e "  ${C_BLUE}$1${C_NC}"; }
_sub_warn()    { echo -e "  ${C_YELLOW}Warning: $1${C_NC}" >&2; }
_sub_error()   { echo -e "  ${C_RED}Error: $1${C_NC}" >&2; }

# Show the config files an uninstall leaves, which it never removes
# Args: submodule_name module_yml
_show_preserved_configs() {
    local submodule="$1" module_yml="$2"
    local preserved=() dest
    while IFS= read -r dest; do
        [[ -n "$dest" ]] || continue
        dest=$(_submodule_expand_path "$dest")
        if [[ -f "$dest" ]]; then
            preserved+=("$dest")
        fi
    done < <(yq -r ".submodules.\"$submodule\".configs // [] | .[].dest" "$module_yml")

    if (( ${#preserved[@]} > 0 )); then
        echo ""
        echo -e "${C_YELLOW}Config files were NOT removed:${C_NC}"
        printf '  %s\n' "${preserved[@]}"
        echo ""
    fi
}

# =============================================================================
# SUBMODULE INSTALL
# =============================================================================

# Install a single submodule
# Args: module_dir submodule_name [module_yml]
# Env: SUBMODULE_PROGRESS_CURRENT, SUBMODULE_PROGRESS_TOTAL (optional, set by caller)
#      SUBMODULE_FORCE=true reinstalls a submodule already at its version
submodule_install() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="${3:-$module_dir/module.yml}"

    local module_name module_version version
    module_name=$(module_get "name" "$module_yml")
    module_version=$(module_get "version" "$module_yml")
    version=$(submodule_get "$submodule" "version" "$module_yml")

    # --- Validate submodule exists in module.yml ---
    if [[ -z "$submodule" || -z "$version" ]]; then
        error "Unknown submodule '$submodule' in $module_name (not found in module.yml)" "exit"
    fi

    # --- Check minimum lib version ---
    local min_lib_version
    min_lib_version=$(module_get "min_lib_version" "$module_yml")
    if [[ -n "$min_lib_version" ]]; then
        local lib_cmp
        lib_cmp=$(version_compare "$LIB_VERSION" "$min_lib_version")
        if [[ "$lib_cmp" == "lt" ]]; then
            error "Module $module_name requires lib >= $min_lib_version (installed: $LIB_VERSION). Run: make install-lib" "exit"
        fi
    fi

    # --- Resolve type and user context ---
    local _sub_type _real_user _real_home _real_uid
    _submodule_resolve_context "$submodule" "$module_yml" || return 1
    local bin_path systemd_dir
    bin_path=$(_submodule_bin_path)
    systemd_dir=$(_submodule_systemd_dir)

    # --- Section header ---
    if [[ -n "${SUBMODULE_PROGRESS_CURRENT:-}" ]]; then
        echo -e "${C_BOLD}[${SUBMODULE_PROGRESS_CURRENT}/${SUBMODULE_PROGRESS_TOTAL}] Installing ${module_name}/${submodule} v${version}${C_NC}"
    else
        echo -e "${C_BOLD}Installing ${module_name}/${submodule} v${version}${C_NC}"
    fi

    # --- Check if already at this version ---
    if _is_sub_installed "$module_name" "$submodule" "$module_yml"; then
        local iver cmp
        iver=$(_get_sub_version "$module_name" "$submodule" "$module_yml")
        cmp=$(version_compare "$iver" "$version")
        case "$cmp" in
            eq)
                if [[ "${SUBMODULE_FORCE:-}" != "true" ]]; then
                    _sub_success "$module_name/$submodule v$version already installed"
                    return 0
                fi
                _sub_info "Reinstalling $module_name/$submodule v$version"
                ;;
            lt) _sub_info "Upgrading $module_name/$submodule v$iver -> v$version" ;;
            gt) _sub_info "Downgrading $module_name/$submodule v$iver -> v$version" ;;
        esac
    fi

    # --- Resolve submodule dependencies (deps:) ---
    local deps dep
    mapfile -t deps < <(submodule_get_array "$submodule" "deps" "$module_yml")
    for dep in "${deps[@]}"; do
        [[ -z "$dep" ]] && continue
        if ! _is_sub_installed "$module_name" "$dep" "$module_yml"; then
            _sub_info "Installing dependency: $module_name/$dep"
            SUBMODULE_PROGRESS_CURRENT="" SUBMODULE_PROGRESS_TOTAL="" \
                submodule_install "$module_dir" "$dep" "$module_yml"
        fi
    done

    # --- Required commands (not from dnf: the user installs them) ---
    local req_count ri req_name req_hint
    req_count=$(yq -r ".submodules.\"$submodule\".required_commands // [] | length" "$module_yml")
    for (( ri = 0; ri < req_count; ri++ )); do
        req_name=$(yq -r ".submodules.\"$submodule\".required_commands[$ri] | (.name // .)" "$module_yml")
        [[ -z "$req_name" ]] && continue
        _submodule_has_command "$req_name" && continue
        req_hint=$(yq -r ".submodules.\"$submodule\".required_commands[$ri] | (.install_hint // \"\")" "$module_yml")
        _sub_warn "$req_name not found: $module_name/$submodule needs it to run${req_hint:+ ($req_hint)}"
    done

    # --- System dependencies (dnf packages) ---
    local sys_deps missing
    mapfile -t sys_deps < <(submodule_get_array "$submodule" "system_deps" "$module_yml")
    mapfile -t missing < <(_submodule_missing_packages "${sys_deps[@]}")
    if (( ${#missing[@]} > 0 )); then
        _sub_info "Installing packages: ${missing[*]}"
        if ! dnf install -y "${missing[@]}"; then
            _sub_error "Could not install the packages $module_name/$submodule needs: ${missing[*]}"
            return 1
        fi
    fi

    # --- Install binary ---
    local source_field bin_name
    source_field=$(submodule_get "$submodule" "source" "$module_yml")
    bin_name=$(submodule_get "$submodule" "bin_name" "$module_yml")
    if [[ -n "$source_field" && -n "$bin_name" ]]; then
        _submodule_owner_run "$bin_path" mkdir -p "$bin_path"
        _submodule_owner_run "$bin_path" install -m 755 "$module_dir/$source_field" "$bin_path/$bin_name"
    fi

    # --- Run install hook ---
    local install_hook
    install_hook=$(submodule_get "$submodule" "hooks.install" "$module_yml")
    if [[ -n "$install_hook" ]]; then
        if [[ ! -f "$module_dir/$install_hook" ]]; then
            _sub_error "Install hook not found: $module_dir/$install_hook"
            return 1
        fi
        bash "$module_dir/$install_hook"
    fi

    # --- Install services and timers ---
    local services timers unit
    mapfile -t services < <(submodule_get_array "$submodule" "services" "$module_yml")
    mapfile -t timers < <(submodule_get_array "$submodule" "timers" "$module_yml")
    if (( ${#services[@]} + ${#timers[@]} > 0 )); then
        _submodule_owner_run "$systemd_dir" mkdir -p "$systemd_dir"
    fi
    for unit in "${services[@]}" "${timers[@]}"; do
        [[ -z "$unit" ]] && continue
        if [[ "$unit" == *.tpl ]]; then
            _install_service_template "$module_dir/$unit" "$systemd_dir"
        else
            _submodule_owner_run "$systemd_dir" install -m 644 "$module_dir/$unit" "$systemd_dir/"
        fi
    done

    if (( ${#services[@]} + ${#timers[@]} > 0 )); then
        _systemctl_cmd daemon-reload
    fi

    # --- Enable timers ---
    # System timers are enabled without --now: with Persistent=true, --now
    # would start an overdue run during installation. User timers use --now,
    # their manager starting them only at the next login otherwise.
    local name
    for unit in "${timers[@]}"; do
        [[ -z "$unit" ]] && continue
        name=$(basename "$unit")
        if [[ "$_sub_type" == "user" ]]; then
            _systemctl_cmd enable --now "$name" || _sub_warn "Could not enable $name"
        else
            _systemctl_cmd enable "$name" || _sub_warn "Could not enable $name"
        fi
    done

    # --- Enable services (only persistent daemons, not timer-triggered oneshots) ---
    # With timers, the services are triggered by those timers and must NOT be
    # enabled directly (--now would start an immediate scan). A template
    # (name@.service) runs by instance, started by its trigger.
    if (( ${#timers[@]} == 0 )); then
        for unit in "${services[@]}"; do
            [[ -z "$unit" ]] && continue
            name=$(basename "${unit%.tpl}")
            [[ "$name" == *@.* ]] && continue
            _systemctl_cmd enable --now "$name" || _sub_warn "Could not enable $name"
        done
    fi

    # --- Create directories ---
    local dirs i dir_path dir_mode
    mapfile -t dirs < <(yq -r ".submodules.\"$submodule\".dirs // [] | .[].path" "$module_yml")
    for i in "${!dirs[@]}"; do
        [[ -z "${dirs[$i]}" ]] && continue
        dir_path=$(_submodule_expand_path "${dirs[$i]}")
        dir_mode=$(yq -r ".submodules.\"$submodule\".dirs[$i].mode // \"755\"" "$module_yml")
        _submodule_owner_run "$dir_path" mkdir -p "$dir_path"
        _submodule_owner_run "$dir_path" chmod "$dir_mode" "$dir_path"
    done

    # --- Install configs (no_overwrite) ---
    _install_submodule_configs "$module_dir" "$submodule" "$module_yml"

    # --- Install hook scripts (hook_scripts) ---
    _install_submodule_hooks "$module_dir" "$submodule" "$module_yml"

    # --- Install logrotate config ---
    local logrotate logrotate_dest
    logrotate=$(submodule_get "$submodule" "logrotate" "$module_yml")
    if [[ -n "$logrotate" ]]; then
        logrotate_dest=$(_submodule_logrotate_dest "$logrotate")
        if [[ "$logrotate" == *.tpl ]]; then
            _submodule_render "$module_dir/$logrotate" | _submodule_write "$logrotate_dest" 644
        else
            install -m 644 "$module_dir/$logrotate" "$logrotate_dest"
        fi
    fi

    # --- Register notifications ---
    local notif_tags tag icon notif_level
    mapfile -t notif_tags < <(yq -r ".submodules.\"$submodule\".notifications // [] | .[].tag" "$module_yml")
    for i in "${!notif_tags[@]}"; do
        tag="${notif_tags[$i]}"
        [[ -z "$tag" ]] && continue
        icon=$(yq -r ".submodules.\"$submodule\".notifications[$i].icon // \"\"" "$module_yml")
        notif_level=$(yq -r ".submodules.\"$submodule\".notifications[$i].level // \"\"" "$module_yml")
        notify_register "$tag" "$icon" "$notif_level"
    done

    # --- Register in registry ---
    _submodule_registry "$submodule" "$module_yml" \
        registry_set_submodule "$module_name" "$submodule" "$version" "$module_version"

    _sub_success "Installed $module_name/$submodule v$version"
}

# =============================================================================
# SUBMODULE UNINSTALL
# =============================================================================

# Uninstall a single submodule
# Args: module_dir submodule_name [module_yml]
# Env: SUBMODULE_PROGRESS_CURRENT, SUBMODULE_PROGRESS_TOTAL (optional, set by caller)
submodule_uninstall() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="${3:-$module_dir/module.yml}"

    local module_name
    module_name=$(module_get "name" "$module_yml")

    # --- Resolve type and user context ---
    local _sub_type _real_user _real_home _real_uid
    _submodule_resolve_context "$submodule" "$module_yml" || return 1
    local bin_path systemd_dir
    bin_path=$(_submodule_bin_path)
    systemd_dir=$(_submodule_systemd_dir)

    # --- Section header ---
    if [[ -n "${SUBMODULE_PROGRESS_CURRENT:-}" ]]; then
        echo -e "${C_BOLD}[${SUBMODULE_PROGRESS_CURRENT}/${SUBMODULE_PROGRESS_TOTAL}] Uninstalling ${module_name}/${submodule}${C_NC}"
    else
        echo -e "${C_BOLD}Uninstalling ${module_name}/${submodule}${C_NC}"
    fi

    if ! _is_sub_installed "$module_name" "$submodule" "$module_yml"; then
        _sub_info "$module_name/$submodule is not installed"
        return 0
    fi

    # --- Check for dependents (deps: protection) ---
    local dependents
    mapfile -t dependents < <(_submodule_dependents "$module_name" "$submodule" "$module_yml")
    if (( ${#dependents[@]} > 0 )); then
        _sub_error "Cannot uninstall $module_name/$submodule — required by: ${dependents[*]}"
        return 1
    fi

    # --- Stop & disable units ---
    # Only an enabled unit is disabled: a unit without [Install], such as a
    # timer's service, is stopped alone. A template (name@.service) has running
    # instances to stop. A timer's persistent timestamp goes with it; `clean`
    # fails on a timer without Persistent=, which has none.
    local units unit state
    mapfile -t units < <(_submodule_units "$submodule" "$module_yml")
    for unit in "${units[@]}"; do
        [[ -f "$systemd_dir/$unit" ]] || continue
        if [[ "$unit" == *@.* ]]; then
            _systemctl_cmd stop "${unit/@./@*.}" || _sub_warn "Could not stop the instances of $unit"
            continue
        fi
        _systemctl_cmd stop "$unit" || _sub_warn "Could not stop $unit"
        state=$(_systemctl_cmd is-enabled "$unit" 2>/dev/null || true)
        if [[ "$state" == enabled* ]]; then
            _systemctl_cmd disable "$unit" || _sub_warn "Could not disable $unit"
        fi
        if [[ "$unit" == *.timer ]]; then
            _systemctl_cmd clean --what=state "$unit" 2>/dev/null || true
        fi
    done

    # --- Remove binary ---
    local bin_name
    bin_name=$(submodule_get "$submodule" "bin_name" "$module_yml")
    if [[ -n "$bin_name" ]]; then
        rm -f "$bin_path/$bin_name"
        _submodule_prune_home_dir "$bin_path"
    fi

    # --- Remove unit files ---
    for unit in "${units[@]}"; do
        rm -f "$systemd_dir/$unit"
    done
    if (( ${#units[@]} > 0 )); then
        _systemctl_cmd daemon-reload
    fi
    # The folders systemctl enable and a persistent user timer created
    if [[ "$_sub_type" == "user" ]] && (( ${#units[@]} > 0 )); then
        local wants
        for wants in "$systemd_dir"/*.wants; do
            _submodule_prune_home_dir "$wants"
        done
        _submodule_prune_home_dir "$systemd_dir"
        _submodule_prune_home_dir "$_real_home/.local/share/systemd/timers"
    fi

    # --- Run uninstall hook ---
    local uninstall_hook
    uninstall_hook=$(submodule_get "$submodule" "hooks.uninstall" "$module_yml")
    if [[ -n "$uninstall_hook" ]]; then
        if [[ ! -f "$module_dir/$uninstall_hook" ]]; then
            _sub_error "Uninstall hook not found: $module_dir/$uninstall_hook"
            return 1
        fi
        bash "$module_dir/$uninstall_hook"
    fi

    # --- Remove logrotate config ---
    local logrotate
    logrotate=$(submodule_get "$submodule" "logrotate" "$module_yml")
    if [[ -n "$logrotate" ]]; then
        rm -f "$(_submodule_logrotate_dest "$logrotate")"
    fi

    # --- Remove directories (reverse order, deepest first) ---
    local dirs i dir_path
    mapfile -t dirs < <(yq -r ".submodules.\"$submodule\".dirs // [] | .[].path" "$module_yml")
    for (( i = ${#dirs[@]} - 1; i >= 0; i-- )); do
        [[ -z "${dirs[$i]}" ]] && continue
        dir_path=$(_submodule_expand_path "${dirs[$i]}")
        if [[ -d "$dir_path" ]]; then
            if ! _submodule_removable_dir "$dir_path"; then
                _sub_warn "Kept $dir_path: not a directory an uninstall may remove"
                continue
            fi
            rm -rf -- "${dir_path:?}"
        fi
        _submodule_prune_home_dir "$(dirname "$dir_path")"
    done

    # --- Unregister notifications ---
    local notif_tags tag
    mapfile -t notif_tags < <(yq -r ".submodules.\"$submodule\".notifications // [] | .[].tag" "$module_yml")
    for tag in "${notif_tags[@]}"; do
        [[ -z "$tag" ]] && continue
        notify_unregister "$tag"
    done

    # --- Remove hook scripts ---
    _uninstall_submodule_hooks "$module_dir" "$submodule" "$module_yml"

    # --- Show preserved configs ---
    _show_preserved_configs "$submodule" "$module_yml"

    # --- Unregister from registry ---
    _submodule_registry "$submodule" "$module_yml" \
        registry_remove_submodule "$module_name" "$submodule"

    _sub_success "Uninstalled $module_name/$submodule"
}

# =============================================================================
# ORCHESTRATORS (install/uninstall full module)
# =============================================================================
# These functions handle the complete install/uninstall flow for a module:
# CLI parsing, submodule listing, selection, and the install/uninstall loop.
#
# Module install.sh/uninstall.sh scripts become thin wrappers that source
# the lib and call these functions.
#
# Optional callbacks (define as functions before calling):
#   _module_post_install  module_name  — Custom summary after install
#   _module_post_uninstall module_name — Custom messages after uninstall

# Parse an orchestrator's options
# Args: allow_force options...
# Sets: _mode (all, only or interactive), _only (comma-separated), _force
_submodule_parse_args() {
    local allow_force="$1"
    shift
    _mode="interactive"
    _only=""
    _force=false
    while (( $# > 0 )); do
        case "$1" in
            --all) _mode="all" ;;
            --only)
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    error "--only needs a comma-separated list of submodules"
                    return 1
                fi
                _mode="only"
                _only="$2"
                shift
                ;;
            --force)
                if [[ "$allow_force" != "true" ]]; then
                    error "Unknown option: $1"
                    return 1
                fi
                _force=true
                ;;
            *)
                error "Unknown option: $1"
                return 1
                ;;
        esac
        shift
    done
}

# Check that each selected name is a submodule of the module
# Args: module_yml names...
_submodule_check_names() {
    local module_yml="$1" name
    shift
    for name in "$@"; do
        if ! submodule_list "$module_yml" | grep -qxF -- "$name"; then
            error "Unknown submodule: $name"
            return 1
        fi
    done
}

# Let the user pick submodules, with gum or a numbered list
# Args: header names...
# Output: the names picked, one per line
_submodule_pick() {
    local header="$1"
    shift
    local names=("$@") picked=() selection num i

    if has_gum; then
        mapfile -t picked < <(printf '%s\n' "all" "${names[@]}" | gum choose --no-limit --header "$header")
        if printf '%s\n' "${picked[@]}" | grep -qx "all"; then
            picked=("${names[@]}")
        fi
    else
        echo -e "${C_BOLD}${header}${C_NC}" >&2
        echo "  Enter numbers separated by spaces, or 'all' for everything" >&2
        echo "" >&2
        for i in "${!names[@]}"; do
            echo -e "  ${C_BOLD}$((i + 1)))${C_NC} ${names[$i]}" >&2
        done
        echo "" >&2
        read -rp "Selection [all]: " selection
        selection="${selection:-all}"
        if [[ "$selection" == "all" ]]; then
            picked=("${names[@]}")
        else
            for num in $selection; do
                if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#names[@]} )); then
                    picked+=("${names[$((num - 1))]}")
                fi
            done
        fi
    fi
    if (( ${#picked[@]} > 0 )); then
        printf '%s\n' "${picked[@]}"
    fi
}

# Run the full submodule install orchestration for a module
# Args: module_dir [CLI args...]
# CLI args: --all (install all), --only <names> (comma-separated), --force, or none (interactive)
submodule_run_install() {
    local module_dir="$1"; shift
    local module_yml="$module_dir/module.yml"

    # --- Parse CLI arguments ---
    local _mode _only _force
    _submodule_parse_args true "$@" || return 1

    # --- Module metadata ---
    local module_name module_version
    module_name=$(module_get "name" "$module_yml")
    module_version=$(module_get "version" "$module_yml")

    # --- List all submodules ---
    local all_submodules=() sub
    mapfile -t all_submodules < <(submodule_list "$module_yml")

    # Show header + status only in interactive/all mode (--only skips: caller already displayed it)
    if [[ "$_mode" != "only" ]]; then
        info "Module: $module_name v$module_version"
        echo ""

        local sub_desc sub_ver sub_iver
        for sub in "${all_submodules[@]}"; do
            sub_desc=$(submodule_get "$sub" "description" "$module_yml")
            sub_ver=$(submodule_get "$sub" "version" "$module_yml")

            if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
                sub_iver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
                if [[ "$_force" == "true" ]]; then
                    echo -e "  ${C_YELLOW}[reinstall v$sub_iver]${C_NC} $sub — $sub_desc"
                else
                    echo -e "  ${C_GREEN}[installed v$sub_iver]${C_NC} $sub — $sub_desc"
                fi
            else
                echo -e "  ${C_DIM}[available v$sub_ver]${C_NC} $sub — $sub_desc"
            fi
        done
        echo ""
    fi

    # --- Filter submodules ---
    local available_subs=()
    if [[ "$_force" == "true" ]]; then
        # Force mode: all submodules are candidates (reinstall installed ones)
        available_subs=("${all_submodules[@]}")
    else
        # Normal mode: not-yet-installed OR outdated submodules
        local sub_iver sub_aver
        for sub in "${all_submodules[@]}"; do
            if ! _is_sub_installed "$module_name" "$sub" "$module_yml"; then
                available_subs+=("$sub")
            else
                sub_iver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
                sub_aver=$(submodule_get "$sub" "version" "$module_yml")
                if [[ "$(version_compare "$sub_iver" "$sub_aver")" == "lt" ]]; then
                    available_subs+=("$sub")
                fi
            fi
        done

        if (( ${#available_subs[@]} == 0 )); then
            success "All submodules are up to date"
            return 0
        fi
    fi

    # --- Select submodules ---
    local selected=()
    case "$_mode" in
        all)
            selected=("${all_submodules[@]}")
            ;;
        only)
            IFS=',' read -ra selected <<< "$_only"
            _submodule_check_names "$module_yml" "${selected[@]}" || return 1
            ;;
        interactive)
            local select_header="Select submodules to install:"
            [[ "$_force" == "true" ]] && select_header="Select submodules to reinstall:"
            mapfile -t selected < <(_submodule_pick "$select_header" "${available_subs[@]}")
            ;;
    esac

    if (( ${#selected[@]} == 0 )); then
        warn "No submodules selected. Nothing to install."
        return 0
    fi

    echo ""
    if [[ "$_force" == "true" ]]; then
        info "Reinstalling ${#selected[@]} submodule(s)..."
    else
        info "Installing ${#selected[@]} submodule(s)..."
    fi
    echo ""

    # --- Install loop ---
    local idx=0
    for sub in "${selected[@]}"; do
        idx=$((idx + 1))
        SUBMODULE_FORCE="$_force" \
        SUBMODULE_PROGRESS_CURRENT=$idx SUBMODULE_PROGRESS_TOTAL=${#selected[@]} \
            submodule_install "$module_dir" "$sub" "$module_yml"
        echo ""
    done

    success "$module_name v$module_version installation complete"
    echo ""

    # --- Summary: list installed submodules ---
    echo -e "${C_BLUE}Installed submodules:${C_NC}"
    for sub in "${all_submodules[@]}"; do
        if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
            echo "  • $sub v$(_get_sub_version "$module_name" "$sub" "$module_yml")"
        fi
    done
    echo ""

    # --- Optional post-install callback ---
    if declare -F _module_post_install &>/dev/null; then
        _module_post_install "$module_name"
    fi
}

# Run the full submodule uninstall orchestration for a module
# Args: module_dir [CLI args...]
# CLI args: --all, --only <names>, or none (interactive)
submodule_run_uninstall() {
    local module_dir="$1"; shift
    local module_yml="$module_dir/module.yml"
    local module_name
    module_name=$(module_get "name" "$module_yml")

    # --- Parse CLI arguments ---
    local _mode _only _force
    _submodule_parse_args false "$@" || return 1

    # --- Build installed list from all defined submodules (handles mixed types) ---
    local all_subs_yml=() sub
    mapfile -t all_subs_yml < <(submodule_list "$module_yml")

    local installed=()
    for sub in "${all_subs_yml[@]}"; do
        if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
            installed+=("$sub")
        fi
    done

    if (( ${#installed[@]} == 0 )); then
        warn "$module_name: no installed submodules found"
        return 0
    fi

    # --- Select submodules ---
    local selected=()
    case "$_mode" in
        all)
            selected=("${installed[@]}")
            ;;
        only)
            IFS=',' read -ra selected <<< "$_only"
            _submodule_check_names "$module_yml" "${selected[@]}" || return 1
            ;;
        interactive)
            info "Installed submodules:"
            for sub in "${installed[@]}"; do
                echo -e "  ${C_GREEN}$sub${C_NC} v$(_get_sub_version "$module_name" "$sub" "$module_yml")"
            done
            echo ""
            mapfile -t selected < <(_submodule_pick "Select submodules to uninstall:" "${installed[@]}")
            ;;
    esac

    if (( ${#selected[@]} == 0 )); then
        warn "No submodules selected. Nothing to uninstall."
        return 0
    fi

    info "Uninstalling ${#selected[@]} submodule(s)..."
    echo ""

    # --- Sort: deps last (core after its dependents) ---
    mapfile -t selected < <(submodule_sort_uninstall "$module_yml" "${selected[@]}")

    # --- Uninstall loop ---
    local idx=0
    for sub in "${selected[@]}"; do
        idx=$((idx + 1))
        SUBMODULE_PROGRESS_CURRENT=$idx SUBMODULE_PROGRESS_TOTAL=${#selected[@]} \
            submodule_uninstall "$module_dir" "$sub" "$module_yml"
        echo ""
    done

    success "$module_name uninstall complete"
    echo ""

    # Count remaining installed submodules (handles mixed types)
    local remaining=0
    for sub in "${all_subs_yml[@]}"; do
        if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
            remaining=$((remaining + 1))
        fi
    done
    if (( remaining > 0 )); then
        info "$remaining submodule(s) still installed"
    fi

    # --- Optional post-uninstall callback ---
    if declare -F _module_post_uninstall &>/dev/null; then
        _module_post_uninstall "$module_name"
    fi

    echo ""
}

# =============================================================================
# INTERNAL HELPERS
# =============================================================================

# Install a service template (.tpl) with dynamic substitutions
# Args: template_path systemd_dir
_install_service_template() {
    local tpl_path="$1"
    local systemd_dir="$2"

    local svc_name
    svc_name=$(basename "${tpl_path%.tpl}")
    local output="$systemd_dir/$svc_name"

    # Special handling for download-clamscan.service.tpl
    if [[ "$svc_name" == "download-clamscan.service" ]]; then
        local config_file="${PATHS_CONF:-/etc/system-scripts/paths.conf}"
        if [[ -f "$config_file" ]]; then
            # shellcheck source=/dev/null
            source "$config_file"
        fi

        {
            # Copy template up to the placeholder
            sed '/##READWRITE_PATHS##/q' "$tpl_path" | head -n -1

            # Insert ReadWritePaths
            echo "ReadWritePaths=/var/log/clamav"
            echo "ReadWritePaths=/var/quarantine"
            if [[ -n "${WATCH_DIRS+x}" ]]; then
                for dir in "${WATCH_DIRS[@]}"; do
                    if [[ -d "$dir" ]]; then
                        echo "ReadWritePaths=$dir"
                    fi
                done
            fi

            # Append the rest of the template
            sed -n '/##READWRITE_PATHS##/,$p' "$tpl_path" | tail -n +2
        } | _submodule_write "$output" 644
    else
        _submodule_render "$tpl_path" | _submodule_write "$output" 644
    fi
}

# Install config files for a submodule (with no_overwrite support)
# Args: module_dir submodule_name module_yml
_install_submodule_configs() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="$3"

    local config_count i src dest no_overwrite
    config_count=$(yq -r ".submodules.\"$submodule\".configs // [] | length" "$module_yml")
    for (( i = 0; i < config_count; i++ )); do
        src=$(yq -r ".submodules.\"$submodule\".configs[$i].source" "$module_yml")
        dest=$(yq -r ".submodules.\"$submodule\".configs[$i].dest" "$module_yml")
        no_overwrite=$(yq -r ".submodules.\"$submodule\".configs[$i].no_overwrite // false" "$module_yml")
        dest=$(_submodule_expand_path "$dest")

        if [[ "$no_overwrite" == "true" && -f "$dest" ]]; then
            _sub_info "Config already exists: $dest"
            continue
        fi
        _submodule_owner_run "$dest" mkdir -p "$(dirname "$dest")"
        _submodule_owner_run "$dest" install -m 644 "$module_dir/$src" "$dest"
        _sub_success "Created: $dest"
    done
}

# Install a submodule's hook scripts: each <event>/<name>.sh of its
# hook_scripts folder goes to <hooks.d>/<event>/<name>.sh, where hooks.d is
# SUBMODULE_HOOKS_DIR or /usr/local/lib/system-scripts/hooks.d
# Args: module_dir submodule_name module_yml
_install_submodule_hooks() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="$3"
    local hooks_dir="${SUBMODULE_HOOKS_DIR:-/usr/local/lib/system-scripts/hooks.d}"

    local scripts_dir hook event
    scripts_dir=$(submodule_get "$submodule" "hook_scripts" "$module_yml")
    [[ -n "$scripts_dir" ]] || return 0
    if [[ ! -d "$module_dir/$scripts_dir" ]]; then
        _sub_error "Hook scripts folder not found: $module_dir/$scripts_dir"
        return 1
    fi

    for hook in "$module_dir/$scripts_dir"/*/*.sh; do
        [[ -f "$hook" ]] || continue
        event=$(basename "$(dirname "$hook")")
        install -d -m 755 "$hooks_dir/$event"
        install -m 755 "$hook" "$hooks_dir/$event/"
        _sub_success "Installed hook: $event/$(basename "$hook")"
    done
}

# Remove the hook scripts a submodule ships, leaving any other script of
# hooks.d, then each folder left empty
# Args: module_dir submodule_name module_yml
_uninstall_submodule_hooks() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="$3"
    local hooks_dir="${SUBMODULE_HOOKS_DIR:-/usr/local/lib/system-scripts/hooks.d}"

    local scripts_dir hook event
    scripts_dir=$(submodule_get "$submodule" "hook_scripts" "$module_yml")
    [[ -n "$scripts_dir" ]] || return 0

    for hook in "$module_dir/$scripts_dir"/*/*.sh; do
        [[ -f "$hook" ]] || continue
        event=$(basename "$(dirname "$hook")")
        rm -f "$hooks_dir/$event/$(basename "$hook")"
        rmdir "$hooks_dir/$event" 2>/dev/null || true
    done
    rmdir "$hooks_dir" 2>/dev/null || true
}
