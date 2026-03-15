#!/bin/bash
# =============================================================================
# SUBMODULE.SH - Submodule install/uninstall/update engine
# =============================================================================
# Generic functions to install, uninstall, and update submodules declared
# in module.yml. Each module's install.sh becomes a thin orchestrator that
# calls these functions.
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
    yq -r '.submodules | keys | .[]' "$yml" 2>/dev/null
}

# Get a submodule array field as newline-separated values
# Args: submodule_name field [module_yml_path]
submodule_get_array() {
    local submodule="$1"
    local field="$2"
    local yml="${3:-module.yml}"
    yq -r ".submodules.\"$submodule\".$field // [] | .[]" "$yml" 2>/dev/null
}

# =============================================================================
# USER-TYPE SUBMODULE SUPPORT
# =============================================================================
# Submodules can declare `type: user` in module.yml to override the module's
# default type. User-type submodules install to user paths (~/.local/bin,
# ~/.config/systemd/user/) and use user systemd + user registry.
#
# Context variables (set by _submodule_resolve_context):
#   _sub_type    — "system" or "user"
#   _real_user   — target user (SUDO_USER or USER)
#   _real_home   — target user's home directory
#   _real_uid    — target user's UID

# Resolve type and user context for a submodule
# Args: submodule_name module_yml
# Sets: _sub_type, _real_user, _real_home, _real_uid
_submodule_resolve_context() {
    local submodule="$1"
    local module_yml="$2"
    _sub_type=$(submodule_get "$submodule" "type" "$module_yml")
    [[ -z "$_sub_type" ]] && _sub_type=$(module_get "type" "$module_yml")
    _real_user="${SUDO_USER:-$USER}"
    _real_home=$(getent passwd "$_real_user" | cut -d: -f6)
    _real_uid=$(id -u "$_real_user")
}

# Run systemctl with user/system context
# Uses _sub_type, _real_user, _real_uid from _submodule_resolve_context
_systemctl_cmd() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        sudo -u "$_real_user" XDG_RUNTIME_DIR="/run/user/$_real_uid" \
            systemctl --user "$@"
    else
        systemctl "$@"
    fi
}

# Get bin_path based on submodule type
# Uses _sub_type, _real_home from _submodule_resolve_context
_submodule_bin_path() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        echo "$_real_home/.local/bin"
    else
        echo "/usr/local/bin"
    fi
}

# Get systemd unit directory based on submodule type
# Uses _sub_type, _real_home from _submodule_resolve_context
_submodule_systemd_dir() {
    if [[ "${_sub_type:-system}" == "user" ]]; then
        echo "$_real_home/.config/systemd/user"
    else
        echo "/etc/systemd/system"
    fi
}

# Expand ~ in paths for user-type submodules
# Args: path
# Uses _real_home from _submodule_resolve_context
_submodule_expand_path() {
    local path="$1"
    # shellcheck disable=SC2088  # Tilde is a literal prefix from YAML, not shell expansion
    if [[ "$path" == "~/"* ]]; then
        echo "${_real_home}/${path#\~/}"
    else
        echo "$path"
    fi
}

# Check if a submodule is installed, using the correct registry for its type
# Args: module_name submodule_name module_yml
_is_sub_installed() {
    local module_name="$1" submodule="$2" module_yml="$3"
    local sub_type
    sub_type=$(submodule_get "$submodule" "type" "$module_yml")
    [[ -z "$sub_type" ]] && sub_type=$(module_get "type" "$module_yml")
    if [[ "$sub_type" == "user" ]]; then
        local real_user="${SUDO_USER:-$USER}"
        local real_home
        real_home=$(getent passwd "$real_user" | cut -d: -f6)
        REGISTRY_PATH_OVERRIDE="$real_home/.config/system-scripts/registry" \
            registry_is_submodule_installed "$module_name" "$submodule"
    else
        registry_is_submodule_installed "$module_name" "$submodule"
    fi
}

# Get submodule version from the correct registry for its type
# Args: module_name submodule_name module_yml
_get_sub_version() {
    local module_name="$1" submodule="$2" module_yml="$3"
    local sub_type
    sub_type=$(submodule_get "$submodule" "type" "$module_yml")
    [[ -z "$sub_type" ]] && sub_type=$(module_get "type" "$module_yml")
    if [[ "$sub_type" == "user" ]]; then
        local real_user="${SUDO_USER:-$USER}"
        local real_home
        real_home=$(getent passwd "$real_user" | cut -d: -f6)
        REGISTRY_PATH_OVERRIDE="$real_home/.config/system-scripts/registry" \
            registry_get_submodule_version "$module_name" "$submodule"
    else
        registry_get_submodule_version "$module_name" "$submodule"
    fi
}

# =============================================================================
# UNINSTALL ORDERING
# =============================================================================

# Sort submodules for uninstall: dependencies last
# Args: module_yml submodule_names...
# Output: sorted names (one per line), deps after their dependents
submodule_sort_uninstall() {
    local module_yml="$1"
    shift
    local subs=("$@")

    local ordered=()
    local deferred=()

    for sub in "${subs[@]}"; do
        local is_dep_of_selected=false
        for other in "${subs[@]}"; do
            [[ "$other" == "$sub" ]] && continue
            local other_deps
            mapfile -t other_deps < <(submodule_get_array "$other" "deps" "$module_yml")
            for d in "${other_deps[@]}"; do
                if [[ "$d" == "$sub" ]]; then
                    is_dep_of_selected=true
                    break
                fi
            done
            [[ "$is_dep_of_selected" == "true" ]] && break
        done

        if [[ "$is_dep_of_selected" == "true" ]]; then
            deferred+=("$sub")
        else
            ordered+=("$sub")
        fi
    done

    printf '%s\n' "${ordered[@]}" "${deferred[@]}"
}

# =============================================================================
# INDENTED OUTPUT HELPERS (used inside submodule install/uninstall)
# =============================================================================

_sub_success() { echo -e "  ${C_GREEN}✓ $1${C_NC}"; }
_sub_info()    { echo -e "  ${C_BLUE}$1${C_NC}"; }
_sub_error()   { echo -e "  ${C_RED}Error: $1${C_NC}" >&2; }

# Show preserved config files after submodule uninstall
# Reads configs: (no_overwrite: true) and hooks.hooks_config from module.yml
# Args: submodule_name module_yml real_home
_show_preserved_configs() {
    local submodule="$1"
    local module_yml="$2"
    local real_home="$3"
    local preserved=()

    # Collect configs with no_overwrite: true that still exist on disk
    local config_count
    config_count=$(yq -r ".submodules.\"$submodule\".configs // [] | length" "$module_yml")
    local i
    for (( i=0; i<config_count; i++ )); do
        local dest no_overwrite
        no_overwrite=$(yq -r ".submodules.\"$submodule\".configs[$i].no_overwrite // false" "$module_yml")
        [[ "$no_overwrite" != "true" ]] && continue
        dest=$(yq -r ".submodules.\"$submodule\".configs[$i].dest" "$module_yml")
        dest="${dest/#\~/$real_home}"
        [[ -f "$dest" ]] && preserved+=("$dest")
    done

    # Collect hooks_config files that still exist on disk
    local hooks_config
    hooks_config=$(yq -r ".submodules.\"$submodule\".hooks.hooks_config // \"\"" "$module_yml")
    if [[ -n "$hooks_config" ]]; then
        local config_dir="$real_home/.config/backup/hooks"
        if [[ -d "$config_dir" ]]; then
            for cfg in "$config_dir"/*.yml; do
                [[ -f "$cfg" ]] && preserved+=("$cfg")
            done
        fi
    fi

    # Display if any preserved configs found
    if [[ ${#preserved[@]} -gt 0 ]]; then
        echo ""
        echo -e "${C_YELLOW}Config files were NOT removed:${C_NC}"
        for path in "${preserved[@]}"; do
            echo "  $path"
        done
        echo ""
    fi
}

# =============================================================================
# SUBMODULE INSTALL
# =============================================================================

# Install a single submodule
# Args: module_dir submodule_name [module_yml]
# Env: SUBMODULE_PROGRESS_CURRENT, SUBMODULE_PROGRESS_TOTAL (optional, set by caller)
submodule_install() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="${3:-$module_dir/module.yml}"

    local module_name module_version version bin_path
    module_name=$(module_get "name" "$module_yml")
    module_version=$(module_get "version" "$module_yml")
    version=$(submodule_get "$submodule" "version" "$module_yml")

    # --- Resolve type and user context ---
    _submodule_resolve_context "$submodule" "$module_yml"
    bin_path=$(_submodule_bin_path)
    local systemd_dir
    systemd_dir=$(_submodule_systemd_dir)

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

    # --- Section header ---
    if [[ -n "${SUBMODULE_PROGRESS_CURRENT:-}" ]]; then
        echo -e "${C_BOLD}[${SUBMODULE_PROGRESS_CURRENT}/${SUBMODULE_PROGRESS_TOTAL}] Installing ${module_name}/${submodule} v${version}${C_NC}"
    else
        echo -e "${C_BOLD}Installing ${module_name}/${submodule} v${version}${C_NC}"
    fi

    # --- Check if already at this version ---
    if _is_sub_installed "$module_name" "$submodule" "$module_yml"; then
        local iver
        iver=$(_get_sub_version "$module_name" "$submodule" "$module_yml")
        local cmp
        cmp=$(version_compare "$iver" "$version")
        if [[ "$cmp" == "eq" ]]; then
            if [[ "${SUBMODULE_FORCE:-}" == "true" ]]; then
                _sub_info "Reinstalling $module_name/$submodule v$version"
            else
                _sub_success "$module_name/$submodule v$version already installed"
                return 0
            fi
        else
            _sub_info "Upgrading $module_name/$submodule v$iver -> v$version"
        fi
    fi

    # --- Resolve submodule dependencies (deps:) ---
    local deps
    mapfile -t deps < <(submodule_get_array "$submodule" "deps" "$module_yml")
    for dep in "${deps[@]}"; do
        [[ -z "$dep" ]] && continue
        if ! _is_sub_installed "$module_name" "$dep" "$module_yml"; then
            _sub_info "Installing dependency: $module_name/$dep"
            SUBMODULE_PROGRESS_CURRENT="" SUBMODULE_PROGRESS_TOTAL="" \
                submodule_install "$module_dir" "$dep" "$module_yml"
        fi
    done

    # --- Required commands (non-dnf, must be pre-installed) ---
    local req_count
    req_count=$(yq -r ".submodules.\"$submodule\".required_commands // [] | length" "$module_yml")
    if [[ "$req_count" -gt 0 ]]; then
        local req_missing=() req_hints=()
        local ri
        for (( ri=0; ri<req_count; ri++ )); do
            local req_name req_hint
            req_name=$(yq -r ".submodules.\"$submodule\".required_commands[$ri] | (.name // .)" "$module_yml")
            [[ -z "$req_name" ]] && continue
            # Check as real user (not root) since user-installed commands
            # (npm, pip, cargo, etc.) may not be in root's PATH
            local _req_found=false
            if command -v "$req_name" &>/dev/null; then
                _req_found=true
            elif [[ -n "${SUDO_USER:-}" ]]; then
                sudo -u "$SUDO_USER" bash -lc "command -v '$req_name'" &>/dev/null && _req_found=true
            fi
            if [[ "$_req_found" == "false" ]]; then
                req_missing+=("$req_name")
                req_hint=$(yq -r ".submodules.\"$submodule\".required_commands[$ri] | (.install_hint // \"\")" "$module_yml")
                [[ -n "$req_hint" ]] && req_hints+=("  $req_name: $req_hint")
            fi
        done
        if [[ ${#req_missing[@]} -gt 0 ]]; then
            _sub_error "Missing required command(s): ${req_missing[*]}"
            if [[ ${#req_hints[@]} -gt 0 ]]; then
                for hint in "${req_hints[@]}"; do
                    echo -e "  ${C_YELLOW}${hint}${C_NC}" >&2
                done
            fi
            return 1
        fi
    fi

    # --- System dependencies (dnf packages) ---
    local sys_deps
    mapfile -t sys_deps < <(submodule_get_array "$submodule" "system_deps" "$module_yml")
    if [[ ${#sys_deps[@]} -gt 0 ]]; then
        local missing=()
        for dep in "${sys_deps[@]}"; do
            [[ -z "$dep" ]] && continue
            command -v "$dep" &>/dev/null || missing+=("$dep")
        done
        if [[ ${#missing[@]} -gt 0 ]]; then
            echo -e "${C_YELLOW}Missing system packages: ${missing[*]}${C_NC}"
            local confirm_deps
            read -r -p "Install these packages? [y/N] " confirm_deps
            if [[ "${confirm_deps,,}" == "y" ]]; then
                dnf install -y "${missing[@]}"
            else
                warn "Skipping package installation — submodule may not work correctly"
            fi
        fi
    fi

    # --- Install binary/binaries ---
    local source_field
    source_field=$(submodule_get "$submodule" "source" "$module_yml")

    # Ensure bin_path exists (especially for user type: ~/.local/bin)
    if [[ "$_sub_type" == "user" ]]; then
        mkdir -p "$bin_path"
        chown "$_real_user:$_real_user" "$bin_path"
    fi

    if [[ -n "$source_field" ]]; then
        # Single source file
        local bin_name
        bin_name=$(submodule_get "$submodule" "bin_name" "$module_yml")
        if [[ -n "$bin_name" ]]; then
            install -m 755 "$module_dir/$source_field" "$bin_path/$bin_name"
            [[ "$_sub_type" == "user" ]] && chown "$_real_user:$_real_user" "$bin_path/$bin_name"
        fi
    else
        # Multi-source submodule (array of source:bin_name pairs)
        local sources
        mapfile -t sources < <(submodule_get_array "$submodule" "source" "$module_yml")
        for entry in "${sources[@]}"; do
            [[ -z "$entry" ]] && continue
            local src bin
            src="${entry%%:*}"
            bin="${entry##*:}"
            install -m 755 "$module_dir/$src" "$bin_path/$bin"
            [[ "$_sub_type" == "user" ]] && chown "$_real_user:$_real_user" "$bin_path/$bin"
        done
    fi

    # --- Run install hook ---
    local install_hook
    install_hook=$(yq -r ".submodules.\"$submodule\".hooks.install // \"\"" "$module_yml")
    if [[ -n "$install_hook" && -f "$module_dir/$install_hook" ]]; then
        bash "$module_dir/$install_hook"
    fi

    # --- Install services ---
    local services
    mapfile -t services < <(submodule_get_array "$submodule" "services" "$module_yml")

    # Ensure systemd directory exists (especially for user type)
    if [[ ${#services[@]} -gt 0 || "$_sub_type" == "user" ]]; then
        mkdir -p "$systemd_dir"
        [[ "$_sub_type" == "user" ]] && chown -R "$_real_user:$_real_user" \
            "$_real_home/.config/systemd"
    fi

    for svc in "${services[@]}"; do
        [[ -z "$svc" ]] && continue
        if [[ "$svc" == *.tpl ]]; then
            _install_service_template "$module_dir/$svc" "$module_dir" "$submodule"
        else
            install -m 644 "$module_dir/$svc" "$systemd_dir/"
        fi
    done

    # --- Install timers ---
    local timers
    mapfile -t timers < <(submodule_get_array "$submodule" "timers" "$module_yml")
    for tmr in "${timers[@]}"; do
        [[ -z "$tmr" ]] && continue
        install -m 644 "$module_dir/$tmr" "$systemd_dir/"
    done

    # Fix ownership for user-type systemd units
    if [[ "$_sub_type" == "user" && ( ${#services[@]} -gt 0 || ${#timers[@]} -gt 0 ) ]]; then
        chown -R "$_real_user:$_real_user" "$systemd_dir"
    fi

    # --- Reload systemd if services or timers were installed ---
    if [[ ${#services[@]} -gt 0 || ${#timers[@]} -gt 0 ]]; then
        _systemctl_cmd daemon-reload
    fi

    # --- Enable timers ---
    # Use enable without --now: with Persistent=true, --now would trigger
    # immediate execution of overdue timers during installation.
    # Exception: user timers use --now (no persistent boot trigger for user units)
    for tmr in "${timers[@]}"; do
        [[ -z "$tmr" ]] && continue
        local timer_name
        timer_name=$(basename "$tmr")
        if [[ "$_sub_type" == "user" ]]; then
            _systemctl_cmd enable --now "$timer_name" 2>/dev/null || true
        else
            _systemctl_cmd enable "$timer_name" 2>/dev/null || true
        fi
    done

    # --- Enable services (only persistent daemons, not timer-triggered oneshots) ---
    # If the submodule has timers, the services are triggered by those timers
    # and must NOT be enabled directly (--now would start an immediate scan).
    if [[ ${#timers[@]} -eq 0 ]]; then
        for svc in "${services[@]}"; do
            [[ -z "$svc" ]] && continue
            local svc_name
            svc_name=$(basename "$svc")
            # Templates are rendered to their final name (without .tpl)
            svc_name="${svc_name%.tpl}"
            _systemctl_cmd enable --now "$svc_name" 2>/dev/null || true
        done
    fi

    # --- Create directories ---
    local dirs
    mapfile -t dirs < <(yq -r ".submodules.\"$submodule\".dirs // [] | .[].path" "$module_yml" 2>/dev/null)
    for i in "${!dirs[@]}"; do
        local dir_path="${dirs[$i]}"
        [[ -z "$dir_path" ]] && continue
        dir_path=$(_submodule_expand_path "$dir_path")
        local dir_mode
        dir_mode=$(yq -r ".submodules.\"$submodule\".dirs[$i].mode // \"755\"" "$module_yml")
        if [[ "$_sub_type" == "user" ]]; then
            install -d -o "$_real_user" -g "$_real_user" -m "$dir_mode" "$dir_path"
        else
            install -d -m "$dir_mode" "$dir_path"
        fi
    done

    # --- Install configs (no_overwrite) ---
    _install_submodule_configs "$module_dir" "$submodule" "$module_yml"

    # --- Install hooks (backup-system style) ---
    _install_submodule_hooks "$module_dir" "$submodule" "$module_yml"

    # --- Install logrotate config ---
    local logrotate
    logrotate=$(submodule_get "$submodule" "logrotate" "$module_yml")
    if [[ -n "$logrotate" && -f "$module_dir/$logrotate" ]]; then
        local logrotate_dest
        logrotate_dest=$(basename "$logrotate")
        logrotate_dest="/etc/logrotate.d/${logrotate_dest%.tpl}"

        if [[ "$logrotate" == *.tpl ]]; then
            local real_user="${SUDO_USER:-$USER}"
            local real_home
            real_home=$(getent passwd "$real_user" | cut -d: -f6)
            sed -e "s|__HOME__|$real_home|g" -e "s|__USER__|$real_user|g" \
                "$module_dir/$logrotate" > "$logrotate_dest"
            chmod 644 "$logrotate_dest"
        else
            install -m 644 "$module_dir/$logrotate" "$logrotate_dest"
        fi
    fi

    # --- Register notifications ---
    local notif_tags
    mapfile -t notif_tags < <(yq -r ".submodules.\"$submodule\".notifications // [] | .[].tag" "$module_yml" 2>/dev/null)
    for i in "${!notif_tags[@]}"; do
        local tag="${notif_tags[$i]}"
        [[ -z "$tag" ]] && continue
        local icon
        icon=$(yq -r ".submodules.\"$submodule\".notifications[$i].icon // \"\"" "$module_yml")
        local notif_level
        notif_level=$(yq -r ".submodules.\"$submodule\".notifications[$i].level // \"\"" "$module_yml")
        notify_register "$tag" "$icon" "$notif_level"
    done

    # --- Register in registry ---
    if [[ "$_sub_type" == "user" ]]; then
        REGISTRY_PATH_OVERRIDE="$_real_home/.config/system-scripts/registry" \
            registry_set_submodule "$module_name" "$submodule" "$version" "$module_version"
    else
        registry_set_submodule "$module_name" "$submodule" "$version" "$module_version"
    fi

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

    local module_name bin_path
    module_name=$(module_get "name" "$module_yml")

    # --- Resolve type and user context ---
    _submodule_resolve_context "$submodule" "$module_yml"
    bin_path=$(_submodule_bin_path)
    local systemd_dir
    systemd_dir=$(_submodule_systemd_dir)

    # --- Section header ---
    if [[ -n "${SUBMODULE_PROGRESS_CURRENT:-}" ]]; then
        echo -e "${C_BOLD}[${SUBMODULE_PROGRESS_CURRENT}/${SUBMODULE_PROGRESS_TOTAL}] Uninstalling ${module_name}/${submodule}${C_NC}"
    else
        echo -e "${C_BOLD}Uninstalling ${module_name}/${submodule}${C_NC}"
    fi

    # --- Check registry (use user registry for user-type submodules) ---
    local _reg_installed=false
    if [[ "$_sub_type" == "user" ]]; then
        REGISTRY_PATH_OVERRIDE="$_real_home/.config/system-scripts/registry" \
            registry_is_submodule_installed "$module_name" "$submodule" && _reg_installed=true
    else
        registry_is_submodule_installed "$module_name" "$submodule" && _reg_installed=true
    fi

    if [[ "$_reg_installed" == "false" ]]; then
        _sub_info "$module_name/$submodule is not installed"
        return 0
    fi

    # --- Check for dependents (deps: protection) ---
    local all_subs
    mapfile -t all_subs < <(submodule_list "$module_yml")
    local dependents=()
    for other in "${all_subs[@]}"; do
        [[ "$other" == "$submodule" ]] && continue
        # Check registry with correct path for each submodule's type
        local _other_type _other_installed=false
        _other_type=$(submodule_get "$other" "type" "$module_yml")
        [[ -z "$_other_type" ]] && _other_type="$_sub_type"
        if [[ "$_other_type" == "user" ]]; then
            REGISTRY_PATH_OVERRIDE="$_real_home/.config/system-scripts/registry" \
                registry_is_submodule_installed "$module_name" "$other" && _other_installed=true
        else
            registry_is_submodule_installed "$module_name" "$other" && _other_installed=true
        fi
        [[ "$_other_installed" == "false" ]] && continue
        local other_deps
        mapfile -t other_deps < <(submodule_get_array "$other" "deps" "$module_yml")
        for d in "${other_deps[@]}"; do
            if [[ "$d" == "$submodule" ]]; then
                dependents+=("$other")
                break
            fi
        done
    done

    if [[ ${#dependents[@]} -gt 0 ]]; then
        _sub_error "Cannot uninstall $module_name/$submodule — required by: ${dependents[*]}"
        return 1
    fi

    # --- Stop & disable timers ---
    local timers
    mapfile -t timers < <(submodule_get_array "$submodule" "timers" "$module_yml")
    for tmr in "${timers[@]}"; do
        [[ -z "$tmr" ]] && continue
        local timer_name
        timer_name=$(basename "$tmr")
        _systemctl_cmd disable --now "$timer_name" 2>/dev/null || true
    done

    # --- Stop & disable services ---
    local services
    mapfile -t services < <(submodule_get_array "$submodule" "services" "$module_yml")
    for svc in "${services[@]}"; do
        [[ -z "$svc" ]] && continue
        local svc_name
        if [[ "$svc" == *.tpl ]]; then
            svc_name=$(basename "${svc%.tpl}")
        else
            svc_name=$(basename "$svc")
        fi
        _systemctl_cmd disable --now "$svc_name" 2>/dev/null || true
    done

    # --- Remove binaries ---
    local source_field
    source_field=$(submodule_get "$submodule" "source" "$module_yml")

    if [[ -n "$source_field" ]]; then
        local bin_name
        bin_name=$(submodule_get "$submodule" "bin_name" "$module_yml")
        [[ -n "$bin_name" ]] && rm -f "$bin_path/$bin_name"
    else
        # Multi-source
        local sources
        mapfile -t sources < <(submodule_get_array "$submodule" "source" "$module_yml")
        for entry in "${sources[@]}"; do
            [[ -z "$entry" ]] && continue
            local bin="${entry##*:}"
            rm -f "$bin_path/$bin"
        done
    fi

    # --- Remove service/timer files ---
    for svc in "${services[@]}"; do
        [[ -z "$svc" ]] && continue
        local svc_name
        if [[ "$svc" == *.tpl ]]; then
            svc_name=$(basename "${svc%.tpl}")
        else
            svc_name=$(basename "$svc")
        fi
        rm -f "$systemd_dir/$svc_name"
    done
    for tmr in "${timers[@]}"; do
        [[ -z "$tmr" ]] && continue
        rm -f "$systemd_dir/$(basename "$tmr")"
    done

    if [[ ${#services[@]} -gt 0 || ${#timers[@]} -gt 0 ]]; then
        _systemctl_cmd daemon-reload
    fi

    # --- Run uninstall hook ---
    local uninstall_hook
    uninstall_hook=$(yq -r ".submodules.\"$submodule\".hooks.uninstall // \"\"" "$module_yml")
    if [[ -n "$uninstall_hook" && -f "$module_dir/$uninstall_hook" ]]; then
        bash "$module_dir/$uninstall_hook"
    fi

    # --- Remove logrotate config ---
    local logrotate
    logrotate=$(submodule_get "$submodule" "logrotate" "$module_yml")
    if [[ -n "$logrotate" ]]; then
        local logrotate_name
        logrotate_name=$(basename "$logrotate")
        rm -f "/etc/logrotate.d/${logrotate_name%.tpl}"
    fi

    # --- Remove directories (reverse order, deepest first) ---
    local dirs
    mapfile -t dirs < <(yq -r ".submodules.\"$submodule\".dirs // [] | .[].path" "$module_yml" 2>/dev/null)
    if [[ ${#dirs[@]} -gt 0 ]]; then
        local reversed=()
        for (( i=${#dirs[@]}-1; i>=0; i-- )); do
            reversed+=("${dirs[$i]}")
        done
        for dir_path in "${reversed[@]}"; do
            [[ -z "$dir_path" ]] && continue
            dir_path=$(_submodule_expand_path "$dir_path")
            if [[ -d "$dir_path" ]]; then
                rm -rf "$dir_path"
            fi
        done
    fi

    # --- Unregister notifications ---
    local notif_tags
    mapfile -t notif_tags < <(yq -r ".submodules.\"$submodule\".notifications // [] | .[].tag" "$module_yml" 2>/dev/null)
    for tag in "${notif_tags[@]}"; do
        [[ -z "$tag" ]] && continue
        notify_unregister "$tag"
    done

    # --- Remove hooks ---
    _uninstall_submodule_hooks "$submodule" "$module_yml"

    # --- Show preserved configs ---
    _show_preserved_configs "$submodule" "$module_yml" "$_real_home"

    # --- Unregister from registry ---
    if [[ "$_sub_type" == "user" ]]; then
        REGISTRY_PATH_OVERRIDE="$_real_home/.config/system-scripts/registry" \
            registry_remove_submodule "$module_name" "$submodule"
    else
        registry_remove_submodule "$module_name" "$submodule"
    fi

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
#   _module_pre_uninstall              — Cleanup before uninstall loop
#   _module_post_uninstall module_name — Custom messages after uninstall

# Run the full submodule install orchestration for a module
# Args: module_dir [-- CLI args...]
# CLI args: --all (install all), --only <names> (comma-separated), or none (interactive)
submodule_run_install() {
    local module_dir="$1"; shift
    local module_yml="$module_dir/module.yml"

    # --- Parse CLI arguments ---
    local install_mode="interactive"
    local only_list=""
    local force_mode=false

    for arg in "$@"; do
        case "$arg" in
            --all) install_mode="all" ;;
            --force) force_mode=true ;;
            --only)
                install_mode="only"
                ;;
            *)
                if [[ "$install_mode" == "only" && -z "$only_list" ]]; then
                    only_list="$arg"
                fi
                ;;
        esac
    done

    # --- Module metadata ---
    local module_name module_version
    module_name=$(module_get "name" "$module_yml")
    module_version=$(module_get "version" "$module_yml")

    # --- List all submodules ---
    local all_submodules=()
    mapfile -t all_submodules < <(submodule_list "$module_yml")

    # Show header + status only in interactive/all mode (--only skips: caller already displayed it)
    if [[ "$install_mode" != "only" ]]; then
        info "Module: $module_name v$module_version"
        echo ""

        for sub in "${all_submodules[@]}"; do
            local sub_desc sub_ver sub_iver
            sub_desc=$(submodule_get "$sub" "description" "$module_yml")
            sub_ver=$(submodule_get "$sub" "version" "$module_yml")

            if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
                sub_iver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
                if [[ "$force_mode" == "true" ]]; then
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
    if [[ "$force_mode" == "true" ]]; then
        # Force mode: all submodules are candidates (reinstall installed ones)
        available_subs=("${all_submodules[@]}")
    else
        # Normal mode: not-yet-installed OR outdated submodules
        for sub in "${all_submodules[@]}"; do
            if ! _is_sub_installed "$module_name" "$sub" "$module_yml"; then
                available_subs+=("$sub")
            else
                # Check if installed version is outdated
                local sub_iver sub_aver sub_cmp
                sub_iver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
                sub_aver=$(submodule_get "$sub" "version" "$module_yml")
                sub_cmp=$(version_compare "$sub_iver" "$sub_aver")
                if [[ "$sub_cmp" == "lt" ]]; then
                    available_subs+=("$sub")
                fi
            fi
        done

        if [[ ${#available_subs[@]} -eq 0 ]]; then
            success "All submodules are up to date"
            return 0
        fi
    fi

    # --- Select submodules ---
    local selected=()

    case "$install_mode" in
        all)
            selected=("${all_submodules[@]}")
            ;;
        only)
            IFS=',' read -ra selected <<< "$only_list"
            # Validate names
            for sel in "${selected[@]}"; do
                local found=false
                for sub in "${all_submodules[@]}"; do
                    [[ "$sel" == "$sub" ]] && found=true && break
                done
                if [[ "$found" == "false" ]]; then
                    error "Unknown submodule: $sel" "exit"
                fi
            done
            ;;
        interactive)
            local select_header="Select submodules to install:"
            [[ "$force_mode" == "true" ]] && select_header="Select submodules to reinstall:"

            if has_gum; then
                local gum_selected=()
                mapfile -t gum_selected < <(
                    printf '%s\n' "all" "${available_subs[@]}" | \
                    gum choose --no-limit --header "$select_header"
                )
                # Expand "all" to full list
                if printf '%s\n' "${gum_selected[@]}" | grep -qx "all"; then
                    selected=("${available_subs[@]}")
                else
                    selected=("${gum_selected[@]}")
                fi
            else
                echo -e "${C_BOLD}${select_header}${C_NC}"
                echo "  Enter numbers separated by spaces, or 'all' for everything"
                echo ""
                local i=1
                for sub in "${available_subs[@]}"; do
                    local sub_desc
                    sub_desc=$(submodule_get "$sub" "description" "$module_yml")
                    echo -e "  ${C_BOLD}$i)${C_NC} $sub — $sub_desc"
                    ((i++))
                done
                echo ""
                local selection
                read -rp "Selection [all]: " selection
                selection="${selection:-all}"

                if [[ "$selection" == "all" ]]; then
                    selected=("${available_subs[@]}")
                else
                    for num in $selection; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#available_subs[@]} )); then
                            selected+=("${available_subs[$((num-1))]}")
                        fi
                    done
                fi
            fi
            ;;
    esac

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "No submodules selected. Nothing to install."
        return 0
    fi

    echo ""
    if [[ "$force_mode" == "true" ]]; then
        info "Reinstalling ${#selected[@]} submodule(s)..."
    else
        info "Installing ${#selected[@]} submodule(s)..."
    fi
    echo ""

    # --- Install loop ---
    local idx=0
    for sub in "${selected[@]}"; do
        (( ++idx ))
        SUBMODULE_FORCE="$force_mode" \
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
            local sub_ver
            sub_ver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
            echo "  • $sub v$sub_ver"
        fi
    done
    echo ""

    # --- Optional post-install callback ---
    if declare -F _module_post_install &>/dev/null; then
        _module_post_install "$module_name"
    fi
}

# Run the full submodule uninstall orchestration for a module
# Args: module_dir [-- CLI args...]
# CLI args: --all, --only <names>, or none (interactive)
submodule_run_uninstall() {
    local module_dir="$1"; shift
    local module_yml="$module_dir/module.yml"
    local module_name
    module_name=$(module_get "name" "$module_yml")

    # --- Parse CLI arguments ---
    local uninstall_mode="interactive"
    local only_list=""

    for arg in "$@"; do
        case "$arg" in
            --all) uninstall_mode="all" ;;
            --only)
                uninstall_mode="only"
                ;;
            *)
                if [[ "$uninstall_mode" == "only" && -z "$only_list" ]]; then
                    only_list="$arg"
                fi
                ;;
        esac
    done

    # --- Build installed list from all defined submodules (handles mixed types) ---
    local all_subs_yml=()
    mapfile -t all_subs_yml < <(submodule_list "$module_yml")

    local installed=()
    for sub in "${all_subs_yml[@]}"; do
        if _is_sub_installed "$module_name" "$sub" "$module_yml"; then
            installed+=("$sub")
        fi
    done

    if [[ ${#installed[@]} -eq 0 ]]; then
        warn "$module_name: no installed submodules found"
        return 0
    fi

    # --- Select submodules ---
    local selected=()

    case "$uninstall_mode" in
        all)
            selected=("${installed[@]}")
            ;;
        only)
            IFS=',' read -ra selected <<< "$only_list"
            ;;
        interactive)
            info "Installed submodules:"
            for sub in "${installed[@]}"; do
                local sub_ver
                sub_ver=$(_get_sub_version "$module_name" "$sub" "$module_yml")
                echo -e "  ${C_GREEN}$sub${C_NC} v$sub_ver"
            done
            echo ""

            if has_gum; then
                local gum_selected=()
                mapfile -t gum_selected < <(
                    printf '%s\n' "all" "${installed[@]}" | \
                    gum choose --no-limit --header "Select submodules to uninstall:"
                )
                if printf '%s\n' "${gum_selected[@]}" | grep -qx "all"; then
                    selected=("${installed[@]}")
                else
                    selected=("${gum_selected[@]}")
                fi
            else
                echo -e "${C_BOLD}Select submodules to uninstall:${C_NC}"
                echo "  Enter numbers separated by spaces, or 'all' for everything"
                echo ""
                local i=1
                for sub in "${installed[@]}"; do
                    echo -e "  ${C_BOLD}$i)${C_NC} $sub"
                    ((i++))
                done
                echo ""
                local selection
                read -rp "Selection [all]: " selection
                selection="${selection:-all}"

                if [[ "$selection" == "all" ]]; then
                    selected=("${installed[@]}")
                else
                    for num in $selection; do
                        if [[ "$num" =~ ^[0-9]+$ ]] && (( num >= 1 && num <= ${#installed[@]} )); then
                            selected+=("${installed[$((num-1))]}")
                        fi
                    done
                fi
            fi
            ;;
    esac

    if [[ ${#selected[@]} -eq 0 ]]; then
        warn "No submodules selected. Nothing to uninstall."
        return 0
    fi

    # --- Optional pre-uninstall callback ---
    if declare -F _module_pre_uninstall &>/dev/null; then
        _module_pre_uninstall
    fi

    info "Uninstalling ${#selected[@]} submodule(s)..."
    echo ""

    # --- Sort: deps last (core after its dependents) ---
    mapfile -t selected < <(submodule_sort_uninstall "$module_yml" "${selected[@]}")

    # --- Uninstall loop ---
    local idx=0
    for sub in "${selected[@]}"; do
        (( ++idx ))
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
            (( ++remaining ))
        fi
    done
    if [[ "$remaining" -gt 0 ]]; then
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
# Args: template_path module_dir submodule_name
_install_service_template() {
    local tpl_path="$1"
    local module_dir="$2"
    local submodule="$3"

    local svc_name
    svc_name=$(basename "${tpl_path%.tpl}")
    local output="/etc/systemd/system/$svc_name"

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
        } > "$output"
    else
        # Generic template: substitute __HOME__ and __USER__
        local current_user="${SUDO_USER:-$USER}"
        local current_home
        current_home=$(getent passwd "$current_user" | cut -d: -f6)
        sed -e "s|__HOME__|$current_home|g" \
            -e "s|__USER__|$current_user|g" \
            "$tpl_path" > "$output"
    fi

    chmod 644 "$output"
}

# Install config files for a submodule (with no_overwrite support)
# Args: module_dir submodule_name module_yml
_install_submodule_configs() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="$3"

    local config_count
    config_count=$(yq -r ".submodules.\"$submodule\".configs // [] | length" "$module_yml")
    [[ "$config_count" -eq 0 ]] && return 0

    local real_user="${SUDO_USER:-$USER}"
    local real_home
    real_home=$(getent passwd "$real_user" | cut -d: -f6)

    local i
    for (( i=0; i<config_count; i++ )); do
        local src dest no_overwrite
        src=$(yq -r ".submodules.\"$submodule\".configs[$i].source" "$module_yml")
        dest=$(yq -r ".submodules.\"$submodule\".configs[$i].dest" "$module_yml")
        no_overwrite=$(yq -r ".submodules.\"$submodule\".configs[$i].no_overwrite // false" "$module_yml")

        # Expand ~ to real home
        dest="${dest/#\~/$real_home}"

        # Create parent directory
        local dest_dir
        dest_dir=$(dirname "$dest")
        mkdir -p "$dest_dir"
        chown "$real_user:$real_user" "$dest_dir"

        if [[ "$no_overwrite" == "true" && -f "$dest" ]]; then
            _sub_info "Config already exists: $dest"
        else
            cp "$module_dir/$src" "$dest"
            chown "$real_user:$real_user" "$dest"
            _sub_success "Created: $dest"
        fi
    done
}

# Install hook scripts for a submodule (backup-system pattern)
# Args: module_dir submodule_name module_yml
_install_submodule_hooks() {
    local module_dir="$1"
    local submodule="$2"
    local module_yml="$3"

    local hooks_dir
    hooks_dir=$(yq -r ".submodules.\"$submodule\".hooks.install // \"\"" "$module_yml")
    [[ -z "$hooks_dir" ]] && return 0

    # If hooks.install points to a .sh file, it's handled as an install hook (already run)
    [[ "$hooks_dir" == *.sh ]] && return 0

    # It's a directory of hook scripts — install them
    local lib_hooks_dir="/usr/local/lib/system-scripts/hooks.d"

    if [[ -d "$module_dir/$hooks_dir" ]]; then
        local hook_subdir
        for hook_subdir in "$module_dir/$hooks_dir"/*/; do
            [[ -d "$hook_subdir" ]] || continue
            local subdir_name
            subdir_name=$(basename "$hook_subdir")
            install -d -m 755 "$lib_hooks_dir/$subdir_name"
            for hook in "$hook_subdir"*.sh; do
                [[ -f "$hook" ]] || continue
                install -m 755 "$hook" "$lib_hooks_dir/$subdir_name/"
                _sub_success "Installed hook: $subdir_name/$(basename "$hook")"
            done
        done
    fi

    # Install hook configs
    local hooks_config
    hooks_config=$(yq -r ".submodules.\"$submodule\".hooks.hooks_config // \"\"" "$module_yml")
    if [[ -n "$hooks_config" && -d "$module_dir/$hooks_config" ]]; then
        local real_user="${SUDO_USER:-$USER}"
        local real_home
        real_home=$(getent passwd "$real_user" | cut -d: -f6)
        local config_dir="$real_home/.config/backup/hooks"
        mkdir -p "$config_dir"

        for hook_cfg in "$module_dir/$hooks_config/"*.yml; do
            [[ -f "$hook_cfg" ]] || continue
            local cfg_name
            cfg_name=$(basename "$hook_cfg")
            if [[ ! -f "$config_dir/$cfg_name" ]]; then
                cp "$hook_cfg" "$config_dir/$cfg_name"
                chown "$real_user:$real_user" "$config_dir/$cfg_name"
                _sub_success "Created: $config_dir/$cfg_name"
            else
                _sub_info "Config already exists: $config_dir/$cfg_name"
            fi
        done
        chown "$real_user:$real_user" "$config_dir"
    fi
}

# Uninstall hook scripts for a submodule
# Args: submodule_name module_yml
_uninstall_submodule_hooks() {
    local submodule="$1"
    local module_yml="$2"

    local hooks_dir
    hooks_dir=$(yq -r ".submodules.\"$submodule\".hooks.install // \"\"" "$module_yml")
    [[ -z "$hooks_dir" ]] && return 0
    [[ "$hooks_dir" == *.sh ]] && return 0

    local lib_hooks_dir="/usr/local/lib/system-scripts/hooks.d"

    if [[ -d "$lib_hooks_dir" ]]; then
        rm -rf "$lib_hooks_dir/pre-backup"
        rm -rf "$lib_hooks_dir/post-backup"
        rmdir "$lib_hooks_dir" 2>/dev/null || true
    fi
}
