#!/bin/bash
# =============================================================================
# RESOURCES.SH - AW88399 resource manager (internal hook lib)
# =============================================================================
# Clones / updates the upstream audio fix repository and provides helpers
# to locate patches, firmware, and UCM2 files.
#
# Module: build-kernel (hook: aw88399)
# Version: 0.1.0
# =============================================================================

[[ -n "${_AW88399_RESOURCES_LOADED:-}" ]] && return 0
readonly _AW88399_RESOURCES_LOADED=1

# Evaluated at call time — RESOURCE_CACHE_DIR is set by load_config(), not at source time
_repo_dir() { echo "${RESOURCE_CACHE_DIR}/16iax10h-linux-sound-saga"; }

# =============================================================================
# REPOSITORY
# =============================================================================

clone_audio_fix_repo() {
    local repo_url="$AW88399_FIX_REPO"
    local repo_dir
    repo_dir="$(_repo_dir)"

    log_section "Fetching AW88399 Resources"
    mkdir -p "$RESOURCE_CACHE_DIR"

    if [[ -d "${repo_dir}/.git" ]]; then
        log_step "Updating existing repository..."
        if git -C "$repo_dir" pull --ff-only 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
            log_success "Repository updated"
            return 0
        else
            log_warn "Pull failed — re-cloning..."
            rm -rf "$repo_dir"
        fi
    fi

    log_step "Cloning: $repo_url"
    git clone --depth 1 "$repo_url" "$repo_dir" 2>&1 | tee -a "${LOG_FILE:-/dev/null}" \
        || { log_error "Failed to clone repository"; return 1; }

    local commit
    commit=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null)
    log_success "Repository ready (commit: $commit)"
}

# =============================================================================
# PATCH SELECTION
# =============================================================================

# Get the patch file for a given major.minor.patch kernel version.
# Tries: exact match → major.minor match → latest for major.minor (with confirm).
# Args: $1 = kernel_version_mmp (e.g. 6.19.7)
get_patch_file() {
    local kernel_version="$1"
    local patches_dir
    patches_dir="$(_repo_dir)/fix/patches"

    [[ -d "$patches_dir" ]] \
        || { log_error "Patches directory not found: $patches_dir"; return 1; }

    local major_minor
    major_minor=$(echo "$kernel_version" | grep -oP '^\d+\.\d+')

    local patch_file=""
    local is_fallback=false

    if [[ -f "${patches_dir}/16iax10h-audio-linux-${kernel_version}.patch" ]]; then
        patch_file="${patches_dir}/16iax10h-audio-linux-${kernel_version}.patch"
    elif [[ -f "${patches_dir}/16iax10h-audio-linux-${major_minor}.patch" ]]; then
        patch_file="${patches_dir}/16iax10h-audio-linux-${major_minor}.patch"
    else
        patch_file=$(find "$patches_dir" -name "16iax10h-audio-linux-${major_minor}*.patch" 2>/dev/null \
            | sort -V | tail -1)
        [[ -n "$patch_file" ]] && is_fallback=true
    fi

    if [[ -z "$patch_file" || ! -f "$patch_file" ]]; then
        log_error "No patch found for kernel $kernel_version"
        log "Available patches:"
        find "$patches_dir" -name "*.patch" -type f | while read -r f; do
            log "  - $(basename "$f")"
        done
        return 1
    fi

    if [[ "$is_fallback" == "true" ]]; then
        log_warn "No patch validated for kernel $kernel_version"
        log_warn "Closest match: $(basename "$patch_file")"
        ui_confirm "Use $(basename "$patch_file") for kernel $kernel_version?" \
            || { log "Aborted by user"; return 1; }
    fi

    echo "$patch_file"
}

# =============================================================================
# FIRMWARE
# =============================================================================

get_firmware_file() {
    local f
    f="$(_repo_dir)/fix/firmware/aw88399_acf.bin"
    [[ -f "$f" ]] || { log_error "Firmware file not found: $f"; return 1; }
    echo "$f"
}

install_firmware() {
    local dest="/lib/firmware/aw88399_acf.bin"
    log_step "Installing AW88399 firmware..."

    local src
    src=$(get_firmware_file) || return 1

    if [[ -f "$dest" ]]; then
        local src_md5 dest_md5
        src_md5=$(md5sum "$src"  | cut -d' ' -f1)
        dest_md5=$(md5sum "$dest" | cut -d' ' -f1)
        if [[ "$src_md5" == "$dest_md5" ]]; then
            log_success "Firmware already up-to-date"
            return 0
        fi
    fi

    if sudo cp "$src" "$dest" && sudo chmod 644 "$dest"; then
        log_success "Firmware installed: $dest"
    else
        log_error "Failed to install firmware"
        return 1
    fi
}

# =============================================================================
# UCM2
# =============================================================================

get_ucm2_dir() {
    local d
    d="$(_repo_dir)/fix/ucm2"
    [[ -d "$d" ]] || { log_error "UCM2 directory not found: $d"; return 1; }
    echo "$d"
}

install_ucm2() {
    local dest="/usr/share/alsa/ucm2/HDA"
    log_step "Installing UCM2 configuration files..."

    local src
    src=$(get_ucm2_dir) || return 1

    [[ -d "$dest" ]] || { log_error "UCM2 destination not found: $dest (is alsa-ucm installed?)"; return 1; }

    local count=0
    for file in HiFi-analog.conf HiFi-mic.conf; do
        local src_file="${src}/${file}"
        local dest_file="${dest}/${file}"

        [[ -f "$src_file" ]] || { log_warn "UCM2 source not found: $src_file"; continue; }

        # Backup original
        [[ -f "$dest_file" && ! -f "${dest_file}.orig" ]] \
            && sudo cp "$dest_file" "${dest_file}.orig"

        sudo cp -f "$src_file" "$dest_file" \
            || { log_error "Failed to install $file"; continue; }
        log_success "Installed: $file"
        ((count++))
    done

    (( count > 0 )) || { log_error "No UCM2 files were installed"; return 1; }
    log_success "UCM2 configuration installed ($count files)"
}

# =============================================================================
# RESOURCE STATUS
# =============================================================================

show_resource_status() {
    echo ""
    echo -e "${C_BOLD}=== AW88399 Resource Status ===${C_NC}"
    echo ""

    local repo_dir
    repo_dir="$(_repo_dir)"
    echo -ne "  Repository:  "
    [[ -d "${repo_dir}/.git" ]] \
        && echo -e "${C_GREEN}Cloned${C_NC} ($(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null))" \
        || echo -e "${C_YELLOW}Not cloned${C_NC}"

    echo -ne "  Firmware:    "
    [[ -f "/lib/firmware/aw88399_acf.bin" ]] \
        && echo -e "${C_GREEN}Installed${C_NC}" \
        || echo -e "${C_RED}Missing${C_NC}"

    echo -ne "  UCM2:        "
    if [[ -f "/usr/share/alsa/ucm2/HDA/HiFi-analog.conf.orig" ]]; then
        echo -e "${C_GREEN}Installed (custom)${C_NC}"
    elif [[ -f "/usr/share/alsa/ucm2/HDA/HiFi-analog.conf" ]]; then
        echo -e "${C_YELLOW}Default${C_NC}"
    else
        echo -e "${C_RED}Missing${C_NC}"
    fi
    echo ""
}
