#!/bin/bash
# =============================================================================
# BOOKMARK-MANAGER - Nautilus bookmark & symlink manager
# =============================================================================
# Manage Nautilus/GTK bookmarks and optional symlinks in a central directory.
# Interactive (gum) + CLI dual-mode interface.
#
# Bookmarks are entries in ~/.config/gtk-3.0/bookmarks (displayed in Nautilus
# sidebar). Symlinks are optional shortcuts in ~/Bookmarks pointing to the
# real directory, giving quick terminal/file-manager access.
#
# Module: nautilus
# Requires: core, ui
# Version: 0.1.0
#
# Usage:
#   bookmark-manager                          Interactive menu
#   bookmark-manager <command> [options]       CLI mode
# =============================================================================

# Note: -e intentionally omitted — interactive tool handles errors explicitly
set -uo pipefail

# =============================================================================
# PATHS & CONFIGURATION
# =============================================================================

readonly GTK_BOOKMARKS="${GTK_BOOKMARKS_FILE:-$HOME/.config/gtk-3.0/bookmarks}"
readonly STATE_DIR="${BOOKMARK_STATE_DIR:-$HOME/.config/system-scripts}"
readonly STATE_FILE="$STATE_DIR/bookmarks.conf"
readonly MANAGED_FILE="$STATE_DIR/bookmarks.managed"
readonly DEFAULT_BOOKMARKS_DIR="$HOME/Bookmarks"
readonly COMPLETION_DIR="$HOME/.local/share/bash-completion/completions"

# =============================================================================
# LIB LOADING
# =============================================================================

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/ui.sh"

# =============================================================================
# STATE MANAGEMENT
# =============================================================================

# Load state file (creates defaults if missing)
load_state() {
    mkdir -p "$STATE_DIR"

    if [[ ! -f "$STATE_FILE" ]]; then
        cat > "$STATE_FILE" << EOF
# bookmark-manager state
# Managed by bookmark-manager — edit with: bookmark-manager config
bookmarks_dir=$DEFAULT_BOOKMARKS_DIR
EOF
    fi

    # Source state
    # shellcheck disable=SC1090
    source "$STATE_FILE"

    # Ensure bookmarks_dir is set
    BOOKMARKS_DIR="${bookmarks_dir:-$DEFAULT_BOOKMARKS_DIR}"
}

# Save a key=value into state file
state_set() {
    local key="$1" value="$2"

    if grep -q "^${key}=" "$STATE_FILE" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$STATE_FILE"
    else
        echo "${key}=${value}" >> "$STATE_FILE"
    fi
}

# =============================================================================
# MANAGED BOOKMARKS TRACKING
# =============================================================================

# Track a bookmark URI as managed by this script
track_bookmark() {
    local uri="$1"
    mkdir -p "$STATE_DIR"
    touch "$MANAGED_FILE"
    if ! grep -qxF "$uri" "$MANAGED_FILE" 2>/dev/null; then
        echo "$uri" >> "$MANAGED_FILE"
    fi
}

# Untrack a bookmark URI
untrack_bookmark() {
    local uri="$1"
    [[ ! -f "$MANAGED_FILE" ]] && return
    local tmpfile="${MANAGED_FILE}.tmp"
    grep -vxF "$uri" "$MANAGED_FILE" > "$tmpfile" 2>/dev/null || true
    mv "$tmpfile" "$MANAGED_FILE"
}

# Check if a bookmark URI is managed by this script
is_managed() {
    local uri="$1"
    [[ -f "$MANAGED_FILE" ]] && grep -qxF "$uri" "$MANAGED_FILE" 2>/dev/null
}

# Get only managed bookmark lines from GTK bookmarks file
get_managed_bookmarks() {
    [[ ! -f "$GTK_BOOKMARKS" ]] && return
    [[ ! -f "$MANAGED_FILE" ]] && return

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri="${line%% *}"
        if is_managed "$uri"; then
            echo "$line"
        fi
    done < "$GTK_BOOKMARKS"
}

# =============================================================================
# GTK BOOKMARKS HELPERS
# =============================================================================

# Ensure GTK bookmarks file exists
ensure_gtk_bookmarks() {
    local dir
    dir="$(dirname "$GTK_BOOKMARKS")"
    mkdir -p "$dir"
    touch "$GTK_BOOKMARKS"
}

# Parse GTK bookmarks file → "uri label" lines
# Format: file:///path/to/dir Optional Label
get_gtk_bookmarks() {
    [[ ! -f "$GTK_BOOKMARKS" ]] && return
    cat "$GTK_BOOKMARKS"
}

# Check if a URI is already bookmarked
is_bookmarked() {
    local uri="$1"
    [[ -f "$GTK_BOOKMARKS" ]] && grep -q "^${uri}\b" "$GTK_BOOKMARKS"
}

# Add a GTK bookmark entry
add_gtk_bookmark() {
    local uri="$1" label="${2:-}"
    ensure_gtk_bookmarks

    if is_bookmarked "$uri"; then
        warn "Bookmark already exists: $uri"
        return 1
    fi

    if [[ -n "$label" ]]; then
        echo "$uri $label" >> "$GTK_BOOKMARKS"
    else
        echo "$uri" >> "$GTK_BOOKMARKS"
    fi
    return 0
}

# Remove a GTK bookmark by URI
remove_gtk_bookmark() {
    local uri="$1"

    if [[ ! -f "$GTK_BOOKMARKS" ]]; then
        warn "No bookmarks file found"
        return 1
    fi

    if ! grep -q "^${uri}\b" "$GTK_BOOKMARKS"; then
        warn "Bookmark not found: $uri"
        return 1
    fi

    grep -v "^${uri}\b" "$GTK_BOOKMARKS" > "${GTK_BOOKMARKS}.tmp"
    mv "${GTK_BOOKMARKS}.tmp" "$GTK_BOOKMARKS"
    return 0
}

# Get label for a bookmark URI (empty if none)
get_bookmark_label() {
    local uri="$1"
    [[ ! -f "$GTK_BOOKMARKS" ]] && return
    local line
    line=$(grep "^${uri} " "$GTK_BOOKMARKS" 2>/dev/null | head -1)
    if [[ -n "$line" ]]; then
        echo "${line#"$uri" }"
    fi
}

# Path → file:// URI
path_to_uri() {
    local path="$1"
    local encoded="${path// /%20}"
    echo "file://${encoded}"
}

# file:// URI → path (decodes all percent-encoded characters, e.g. %C3%A9 → é)
uri_to_path() {
    local uri="$1"
    local path="${uri#file://}"
    printf '%b' "${path//%/\\x}"
}

# =============================================================================
# TEXT HELPERS
# =============================================================================

# Strip emoji and decorative Unicode from a string for aligned display.
# Removes Symbol,Other (\p{So}), ZWJ (U+200D), variation selectors (U+FE0x),
# and resulting leading whitespace. Keeps accented letters (é, ñ, etc.).
_strip_emoji() {
    if command -v perl &>/dev/null; then
        perl -CS -pe 's/\p{So}|[\x{200D}\x{FE00}-\x{FE0F}]//g; s/^\s*//' <<< "$1"
    else
        echo "$1"
    fi
}

# =============================================================================
# SYMLINK HELPERS
# =============================================================================

# Ensure the bookmarks directory exists
ensure_bookmarks_dir() {
    if [[ ! -d "$BOOKMARKS_DIR" ]]; then
        error "Directory $BOOKMARKS_DIR does not exist"
        info "Run: $(basename "$0") init"
        return 1
    fi
}

# List symlinks in a directory
get_all_links() {
    local dir="${1:-$BOOKMARKS_DIR}"
    [[ ! -d "$dir" ]] && return
    find "$dir" -maxdepth 1 -type l 2>/dev/null | sort
}

# Check if a symlink exists
link_exists() {
    local name="$1"
    [[ -L "$BOOKMARKS_DIR/$name" ]]
}

# Find a symlink by name in BOOKMARKS_DIR (root or any subdirectory)
find_link() {
    local name="$1"
    [[ ! -d "$BOOKMARKS_DIR" ]] && return 1
    local result
    result="$(find "$BOOKMARKS_DIR" -maxdepth 2 -type l -name "$name" 2>/dev/null | head -1)"
    [[ -n "$result" ]] && echo "$result" && return 0
    return 1
}

# List all symlinks in BOOKMARKS_DIR and its subdirectories
get_all_links_recursive() {
    [[ ! -d "$BOOKMARKS_DIR" ]] && return
    find "$BOOKMARKS_DIR" -maxdepth 2 -type l 2>/dev/null | sort
}

# =============================================================================
# COMMANDS
# =============================================================================

# --- init -------------------------------------------------------------------
cmd_init() {
    load_state

    # Create bookmarks directory
    if [[ -d "$BOOKMARKS_DIR" ]]; then
        info "Directory $BOOKMARKS_DIR already exists"
    else
        mkdir -p "$BOOKMARKS_DIR"
        success "Directory created: $BOOKMARKS_DIR"
    fi
}

# --- add --------------------------------------------------------------------
# bookmark-manager add [dir] [-n name] [-s]
# -s: also create a symlink in BOOKMARKS_DIR
cmd_add() {
    load_state

    local target_dir="" link_name="" create_symlink=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)   link_name="$2"; shift 2 ;;
            -s|--symlink) create_symlink=true; shift ;;
            -*)          error "Unknown option: $1"; return 1 ;;
            *)           target_dir="$1"; shift ;;
        esac
    done

    # Default = current directory
    target_dir="${target_dir:-$(pwd)}"
    target_dir="$(realpath "$target_dir")"

    # Default name = directory basename
    link_name="${link_name:-$(basename "$target_dir")}"

    # Validate
    if [[ ! -d "$target_dir" ]]; then
        error "Directory does not exist: $target_dir"
        return 1
    fi

    # Add GTK bookmark
    local uri
    uri=$(path_to_uri "$target_dir")

    if add_gtk_bookmark "$uri" "$link_name"; then
        track_bookmark "$uri"
        success "Bookmark added: ${C_BOLD}$link_name${C_NC}"
        echo -e "   ${C_CYAN}$target_dir${C_NC}"
    fi

    # Optionally create symlink
    if [[ "$create_symlink" == true ]]; then
        if ! ensure_bookmarks_dir; then
            warn "Symlink skipped — run '$(basename "$0") init' first"
            return
        fi

        local link_path="$BOOKMARKS_DIR/$link_name"

        if [[ -e "$link_path" ]]; then
            warn "Symlink already exists: $link_name"
            if [[ -L "$link_path" ]]; then
                info "Current target: $(readlink "$link_path")"
            fi
        else
            ln -s "$target_dir" "$link_path"
            success "Symlink created: ${C_BOLD}$link_name${C_NC} -> ${C_CYAN}$target_dir${C_NC}"
        fi
    fi
}

# --- remove -----------------------------------------------------------------
# bookmark-manager remove <name> [-s]
# -s: also remove symlink
cmd_remove() {
    load_state

    local name="" remove_symlink=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--symlink) remove_symlink=true; shift ;;
            -*)          error "Unknown option: $1"; return 1 ;;
            *)           name="$1"; shift ;;
        esac
    done

    if [[ -z "$name" ]]; then
        error "Bookmark name required"
        echo "Usage: $(basename "$0") remove <name> [-s]"
        return 1
    fi

    # Find bookmark by label (managed bookmarks only)
    local found_uri=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri label
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        # Match by label or by directory basename from URI
        local path_basename
        path_basename="$(basename "$(uri_to_path "$uri")")"
        if [[ "$label" == "$name" || "$path_basename" == "$name" ]]; then
            found_uri="$uri"
            break
        fi
    done < <(get_managed_bookmarks)

    if [[ -n "$found_uri" ]]; then
        remove_gtk_bookmark "$found_uri"
        untrack_bookmark "$found_uri"
        success "Bookmark removed: ${C_BOLD}$name${C_NC}"
    else
        warn "Bookmark not found: $name"
    fi

    # Remove symlink if requested
    if [[ "$remove_symlink" == true ]]; then
        local link_path
        if link_path="$(find_link "$name")"; then
            local target
            target="$(readlink "$link_path")"
            rm "$link_path"
            success "Symlink removed: ${C_BOLD}$name${C_NC} (was -> ${C_CYAN}$target${C_NC})"
        else
            info "No symlink found for: $name"
        fi
    fi
}

# --- list -------------------------------------------------------------------
cmd_list() {
    load_state

    echo -e "\n${C_BOLD}${C_CYAN}Managed Bookmarks${C_NC}\n"

    local bm_count=0 link_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local uri label path status_icon
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        path="$(uri_to_path "$uri")"

        if [[ -d "$path" ]]; then
            status_icon="${C_GREEN}●${C_NC}"
        elif [[ "$uri" == file://* ]]; then
            status_icon="${C_RED}●${C_NC}"
        else
            status_icon="${C_BLUE}●${C_NC}"
        fi

        local display_label
        display_label="$(_strip_emoji "${label:-$(basename "$path")}")"

        printf "  %b  ${C_BOLD}%-20s${C_NC} ${C_DIM}%s${C_NC}\n" \
            "$status_icon" "$display_label" "$path"
        ((bm_count++))

        # Show symlinks inside bookmark subdirectories of BOOKMARKS_DIR
        if [[ -d "$BOOKMARKS_DIR" && "$path" == "$BOOKMARKS_DIR/"* && -d "$path" ]]; then
            local sublinks
            sublinks="$(get_all_links "$path")"
            if [[ -n "$sublinks" ]]; then
                while IFS= read -r slink; do
                    local sname starget sstatus
                    sname="$(basename "$slink")"
                    starget="$(readlink "$slink")"
                    if [[ -d "$starget" ]]; then
                        sstatus="${C_GREEN}●${C_NC}"
                    else
                        sstatus="${C_RED}●${C_NC}"
                    fi
                    printf "      %b  ${C_BOLD}%-18s${C_NC} ${C_DIM}-> %s${C_NC}\n" \
                        "$sstatus" "$sname" "$starget"
                    ((link_count++))
                done <<< "$sublinks"
            fi
        fi
    done < <(get_managed_bookmarks)

    if [[ $bm_count -eq 0 ]]; then
        info "No managed bookmarks found"
    else
        echo ""
        local summary="Total: $bm_count bookmark(s)"
        [[ $link_count -gt 0 ]] && summary+=", $link_count symlink(s)"
        info "$summary"
    fi

    # Show root-level symlinks not matching any managed bookmark
    if [[ -d "$BOOKMARKS_DIR" ]]; then
        local orphan_links=()
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            local lname
            lname="$(basename "$link")"
            local has_bookmark=false
            while IFS= read -r bline; do
                [[ -z "$bline" ]] && continue
                local buri blabel
                buri="${bline%% *}"
                blabel="${bline#"$buri"}"
                blabel="${blabel# }"
                local bbase="${blabel:-$(basename "$(uri_to_path "$buri")")}"
                if [[ "$bbase" == "$lname" ]]; then
                    has_bookmark=true
                    break
                fi
            done < <(get_managed_bookmarks)
            [[ "$has_bookmark" == false ]] && orphan_links+=("$link")
        done < <(get_all_links)

        if [[ ${#orphan_links[@]} -gt 0 ]]; then
            echo ""
            echo -e "${C_BOLD}Symlinks only${C_NC} (no matching bookmark):"
            for link in "${orphan_links[@]}"; do
                local lname ltarget
                lname="$(basename "$link")"
                ltarget="$(readlink "$link")"
                if [[ -d "$ltarget" ]]; then
                    printf "  ${C_GREEN}●${C_NC}  ${C_BOLD}%-20s${C_NC} ${C_DIM}%s${C_NC}\n" \
                        "$lname" "$ltarget"
                else
                    printf "  ${C_RED}●${C_NC}  ${C_BOLD}%-20s${C_NC} ${C_DIM}%s${C_NC} ${C_RED}(broken)${C_NC}\n" \
                        "$lname" "$ltarget"
                fi
            done
        fi
    fi
    echo ""
}

# --- edit -------------------------------------------------------------------
cmd_edit() {
    ensure_gtk_bookmarks

    local editor="${VISUAL:-${EDITOR:-nano}}"
    "$editor" "$GTK_BOOKMARKS"
    success "Bookmarks file saved"
}

# --- check ------------------------------------------------------------------
cmd_check() {
    load_state

    echo -e "${C_BOLD}Checking managed bookmarks & symlinks...${C_NC}\n"

    local broken_bookmarks=0 broken_links=0

    # Check managed bookmarks
    echo -e "${C_BOLD}Bookmarks:${C_NC}"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri label path
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        path="$(uri_to_path "$uri")"

        # Skip non-local bookmarks
        [[ "$uri" != file://* ]] && continue

        if [[ ! -d "$path" ]]; then
            local display="${label:-$(basename "$path")}"
            warn "Broken bookmark: ${C_BOLD}$display${C_NC} -> $path"
            ((broken_bookmarks++))
        fi
    done < <(get_managed_bookmarks)

    if [[ $broken_bookmarks -eq 0 ]]; then
        success "All bookmarks valid"
    else
        warn "$broken_bookmarks broken bookmark(s)"
    fi

    # Check symlinks (root + subdirectories)
    echo ""
    echo -e "${C_BOLD}Symlinks:${C_NC}"
    if [[ -d "$BOOKMARKS_DIR" ]]; then
        local links
        links="$(get_all_links_recursive)"
        if [[ -n "$links" ]]; then
            while IFS= read -r link; do
                local name target parent_name
                name="$(basename "$link")"
                target="$(readlink "$link")"
                parent_name="$(basename "$(dirname "$link")")"
                if [[ ! -d "$target" ]]; then
                    if [[ "$parent_name" != "$(basename "$BOOKMARKS_DIR")" ]]; then
                        warn "Broken symlink: ${C_BOLD}${parent_name}/${name}${C_NC} -> $target"
                    else
                        warn "Broken symlink: ${C_BOLD}$name${C_NC} -> $target"
                    fi
                    ((broken_links++))
                fi
            done <<< "$links"

            if [[ $broken_links -eq 0 ]]; then
                success "All symlinks valid"
            else
                warn "$broken_links broken symlink(s)"
            fi
        else
            info "No symlinks in $BOOKMARKS_DIR"
        fi
    else
        info "Bookmarks directory not initialized"
    fi

    echo ""
    local total=$((broken_bookmarks + broken_links))
    if [[ $total -gt 0 ]]; then
        info "Use '$(basename "$0") clean' to remove broken entries"
    fi

    return "$total"
}

# --- clean ------------------------------------------------------------------
cmd_clean() {
    load_state

    local cleaned=0

    # Clean broken managed bookmarks (non-managed bookmarks are left untouched)
    if [[ -f "$GTK_BOOKMARKS" ]]; then
        local tmpfile="${GTK_BOOKMARKS}.tmp"
        : > "$tmpfile"

        while IFS= read -r line; do
            [[ -z "$line" ]] && { echo "$line" >> "$tmpfile"; continue; }
            local uri path
            uri="${line%% *}"
            path="$(uri_to_path "$uri")"

            # Keep non-managed bookmarks untouched
            if ! is_managed "$uri"; then
                echo "$line" >> "$tmpfile"
            # Keep valid managed bookmarks
            elif [[ "$uri" != file://* ]] || [[ -d "$path" ]]; then
                echo "$line" >> "$tmpfile"
            else
                local label="${line#"$uri"}"
                label="${label# }"
                local display="${label:-$(basename "$path")}"
                untrack_bookmark "$uri"
                success "Removed bookmark: ${C_BOLD}$display${C_NC} (missing: $path)"
                ((cleaned++))
            fi
        done < "$GTK_BOOKMARKS"

        mv "$tmpfile" "$GTK_BOOKMARKS"
    fi

    # Clean broken symlinks (root + subdirectories)
    if [[ -d "$BOOKMARKS_DIR" ]]; then
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            local name target parent_name
            name="$(basename "$link")"
            target="$(readlink "$link")"
            parent_name="$(basename "$(dirname "$link")")"
            if [[ ! -d "$target" ]]; then
                rm "$link"
                local display_name="$name"
                [[ "$parent_name" != "$(basename "$BOOKMARKS_DIR")" ]] && display_name="${parent_name}/${name}"
                success "Removed symlink: ${C_BOLD}$display_name${C_NC} (missing: $target)"
                ((cleaned++))
            fi
        done < <(get_all_links_recursive)
    fi

    if [[ $cleaned -eq 0 ]]; then
        info "Nothing to clean"
    else
        echo ""
        success "$cleaned broken entry/entries removed"
    fi
}

# --- rename -----------------------------------------------------------------
cmd_rename() {
    load_state

    if [[ $# -lt 2 ]]; then
        error "Required: old_name new_name"
        echo "Usage: $(basename "$0") rename <old> <new>"
        return 1
    fi

    local old_name="$1" new_name="$2"
    local renamed=false

    # Rename GTK bookmark label (managed bookmarks only)
    if [[ -f "$GTK_BOOKMARKS" ]]; then
        local tmpfile="${GTK_BOOKMARKS}.tmp"
        cp "$GTK_BOOKMARKS" "$tmpfile"

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local uri label
            uri="${line%% *}"
            label="${line#"$uri"}"
            label="${label# }"
            local path_basename
            path_basename="$(basename "$(uri_to_path "$uri")")"

            if [[ "$label" == "$old_name" || ( -z "$label" && "$path_basename" == "$old_name" ) ]]; then
                # Replace this line with new label
                sed -i "s|^${line}$|${uri} ${new_name}|" "$tmpfile"
                renamed=true
                break
            fi
        done < <(get_managed_bookmarks)

        if [[ "$renamed" == true ]]; then
            mv "$tmpfile" "$GTK_BOOKMARKS"
            success "Bookmark renamed: ${C_BOLD}$old_name${C_NC} -> ${C_BOLD}$new_name${C_NC}"
        else
            rm -f "$tmpfile"
            warn "Bookmark not found: $old_name"
        fi
    fi

    # Rename symlink if exists (search root + subdirectories)
    local old_link_path
    if old_link_path="$(find_link "$old_name")"; then
        local link_dir
        link_dir="$(dirname "$old_link_path")"
        local new_link_path="$link_dir/$new_name"

        if [[ -e "$new_link_path" ]]; then
            warn "Symlink already exists: $new_name"
        else
            mv "$old_link_path" "$new_link_path"
            success "Symlink renamed: ${C_BOLD}$old_name${C_NC} -> ${C_BOLD}$new_name${C_NC}"
        fi
    fi
}

# --- info -------------------------------------------------------------------
cmd_info() {
    load_state

    if [[ $# -eq 0 ]]; then
        error "Bookmark name required"
        echo "Usage: $(basename "$0") info <name>"
        return 1
    fi

    local name="$1"

    # Find in managed bookmarks
    local found_uri="" found_label=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri label
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        local path_basename
        path_basename="$(basename "$(uri_to_path "$uri")")"

        if [[ "$label" == "$name" || "$path_basename" == "$name" ]]; then
            found_uri="$uri"
            found_label="$label"
            break
        fi
    done < <(get_managed_bookmarks)

    echo ""
    echo -e "${C_BOLD}${C_CYAN}Bookmark: $name${C_NC}"
    echo ""

    if [[ -n "$found_uri" ]]; then
        local path
        path="$(uri_to_path "$found_uri")"

        echo -e "  ${C_BOLD}Label:${C_NC}     ${found_label:-$name}"
        echo -e "  ${C_BOLD}URI:${C_NC}       $found_uri"
        echo -e "  ${C_BOLD}Path:${C_NC}      $path"

        if [[ -d "$path" ]]; then
            echo -e "  ${C_BOLD}Status:${C_NC}    ${C_GREEN}Valid${C_NC}"

            if [[ -d "$path/.git" ]]; then
                echo -e "  ${C_BOLD}Git:${C_NC}       Yes"
                local branch
                branch="$(git -C "$path" branch --show-current 2>/dev/null || echo "N/A")"
                echo -e "  ${C_BOLD}Branch:${C_NC}    $branch"
            fi

            local file_count dir_count
            file_count="$(find "$path" -maxdepth 1 -type f 2>/dev/null | wc -l)"
            dir_count="$(find "$path" -maxdepth 1 -type d 2>/dev/null | wc -l)"
            ((dir_count--)) || true
            echo -e "  ${C_BOLD}Content:${C_NC}   $file_count file(s), $dir_count folder(s)"
        elif [[ "$found_uri" == file://* ]]; then
            echo -e "  ${C_BOLD}Status:${C_NC}    ${C_RED}Broken (target missing)${C_NC}"
        else
            echo -e "  ${C_BOLD}Status:${C_NC}    ${C_BLUE}Remote${C_NC}"
        fi
    else
        echo -e "  ${C_DIM}Not found in GTK bookmarks${C_NC}"
    fi

    # Check symlink (search root + subdirectories)
    local link_path
    if link_path="$(find_link "$name")"; then
        local ltarget
        ltarget="$(readlink "$link_path")"
        echo -e "  ${C_BOLD}Symlink:${C_NC}   $link_path -> $ltarget"
        if [[ -d "$ltarget" ]]; then
            echo -e "  ${C_BOLD}Link status:${C_NC} ${C_GREEN}Valid${C_NC}"
        else
            echo -e "  ${C_BOLD}Link status:${C_NC} ${C_RED}Broken${C_NC}"
        fi
    else
        echo -e "  ${C_BOLD}Symlink:${C_NC}   ${C_DIM}None${C_NC}"
    fi
    echo ""
}

# --- open -------------------------------------------------------------------
cmd_open() {
    load_state

    local target="$BOOKMARKS_DIR"

    if [[ $# -gt 0 ]]; then
        local name="$1"
        # Try symlink first (root + subdirectories)
        local found_link
        if found_link="$(find_link "$name")"; then
            target="$found_link"
        else
            # Try managed bookmark path
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                local uri label
                uri="${line%% *}"
                label="${line#"$uri"}"
                label="${label# }"
                local path_basename
                path_basename="$(basename "$(uri_to_path "$uri")")"
                if [[ "$label" == "$name" || "$path_basename" == "$name" ]]; then
                    target="$(uri_to_path "$uri")"
                    break
                fi
            done < <(get_managed_bookmarks)
        fi

        if [[ ! -d "$target" ]]; then
            error "Not found or not a directory: $name"
            return 1
        fi
    fi

    if command -v nautilus &>/dev/null; then
        nautilus "$target" &>/dev/null &
        success "Opening in Nautilus: $target"
    elif command -v xdg-open &>/dev/null; then
        xdg-open "$target" &>/dev/null &
        success "Opening: $target"
    else
        error "No file manager found"
        return 1
    fi
}

# --- link -------------------------------------------------------------------
# Manage symlinks in a bookmark subdirectory
# bookmark-manager link <subdir> add [dir] [-n name]
# bookmark-manager link <subdir> remove <name>
# bookmark-manager link <subdir> list
cmd_link() {
    load_state

    if [[ $# -eq 0 ]]; then
        error "Usage: $(basename "$0") link <subdir> {add|remove|list}"
        return 1
    fi

    # Resolve subdir: absolute path or name relative to BOOKMARKS_DIR
    local subdir_arg="$1"; shift
    local link_dir
    if [[ "$subdir_arg" == /* ]]; then
        link_dir="$subdir_arg"
    else
        link_dir="$BOOKMARKS_DIR/$subdir_arg"
    fi

    local subcmd="${1:-list}"
    shift || true

    case "$subcmd" in
        add)       _link_add "$link_dir" "$@" ;;
        remove|rm) _link_remove "$link_dir" "$@" ;;
        list|ls)   _link_list "$link_dir" ;;
        *)
            error "Unknown link command: $subcmd"
            echo "Usage: $(basename "$0") link <subdir> {add|remove|list}"
            return 1
            ;;
    esac
}

_link_add() {
    local link_dir="${1:-$BOOKMARKS_DIR}"; shift || true

    if [[ ! -d "$link_dir" ]]; then
        error "Directory does not exist: $link_dir"
        return 1
    fi

    local target_dir="" link_name=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name) link_name="$2"; shift 2 ;;
            -*)        error "Unknown option: $1"; return 1 ;;
            *)         target_dir="$1"; shift ;;
        esac
    done

    target_dir="${target_dir:-$(pwd)}"
    target_dir="$(realpath "$target_dir")"
    link_name="${link_name:-$(basename "$target_dir")}"

    if [[ ! -d "$target_dir" ]]; then
        error "Directory does not exist: $target_dir"
        return 1
    fi

    local link_path="$link_dir/$link_name"

    if [[ -e "$link_path" ]]; then
        error "Already exists: $link_name"
        [[ -L "$link_path" ]] && info "Current target: $(readlink "$link_path")"
        return 1
    fi

    ln -s "$target_dir" "$link_path"
    success "Symlink created: ${C_BOLD}$link_name${C_NC} -> ${C_CYAN}$target_dir${C_NC}"
}

_link_remove() {
    local link_dir="${1:-$BOOKMARKS_DIR}" name="${2:-}"

    if [[ ! -d "$link_dir" ]]; then
        error "Directory does not exist: $link_dir"
        return 1
    fi

    if [[ -z "$name" ]]; then
        error "Symlink name required"
        return 1
    fi

    local link_path="$link_dir/$name"

    if [[ ! -L "$link_path" ]]; then
        if [[ -e "$link_path" ]]; then
            error "$name is not a symbolic link"
        else
            error "Symlink not found: $name"
        fi
        return 1
    fi

    local target
    target="$(readlink "$link_path")"
    rm "$link_path"
    success "Symlink removed: ${C_BOLD}$name${C_NC} (was -> ${C_CYAN}$target${C_NC})"
}

_link_list() {
    local link_dir="${1:-$BOOKMARKS_DIR}"

    if [[ ! -d "$link_dir" ]]; then
        error "Directory does not exist: $link_dir"
        return 1
    fi

    local links
    links="$(get_all_links "$link_dir")"

    if [[ -z "$links" ]]; then
        info "No symlinks in $link_dir"
        return 0
    fi

    echo -e "\n${C_BOLD}${C_CYAN}Symlinks in $link_dir${C_NC}\n"

    while IFS= read -r link; do
        local name target status_icon
        name="$(basename "$link")"
        target="$(readlink "$link")"

        if [[ -d "$target" ]]; then
            status_icon="${C_GREEN}●${C_NC}"
        else
            status_icon="${C_RED}●${C_NC}"
        fi

        printf "  %b  ${C_BOLD}%-20s${C_NC} -> ${C_CYAN}%s${C_NC}\n" \
            "$status_icon" "$name" "$target"
    done <<< "$links"

    local count
    count="$(echo "$links" | wc -l)"
    echo ""
    info "Total: $count symlink(s)"
    echo ""
}

# --- config -----------------------------------------------------------------
cmd_config() {
    load_state

    local subcmd="${1:-show}"
    shift || true

    case "$subcmd" in
        show)
            echo -e "\n${C_BOLD}${C_CYAN}Configuration${C_NC}\n"
            echo -e "  ${C_BOLD}Bookmarks dir:${C_NC}   $BOOKMARKS_DIR"
            echo -e "  ${C_BOLD}GTK bookmarks:${C_NC}   $GTK_BOOKMARKS"
            echo -e "  ${C_BOLD}State file:${C_NC}      $STATE_FILE"
            echo ""
            ;;
        dir)
            local new_dir="${1:-}"
            if [[ -z "$new_dir" ]]; then
                echo "$BOOKMARKS_DIR"
                return
            fi
            state_set "bookmarks_dir" "$new_dir"
            success "Bookmarks directory set to: $new_dir"
            info "Run '$(basename "$0") init' to create it"
            ;;
        *)
            error "Unknown config command: $subcmd"
            echo "Usage: $(basename "$0") config {show|dir [path]}"
            return 1
            ;;
    esac
}

# --- export / import --------------------------------------------------------
cmd_export() {
    load_state

    local output="${1:-bookmarks-backup.txt}"

    local count=0
    : > "$output"

    # Export managed bookmarks
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "bookmark|$line" >> "$output"
        ((count++))
    done < <(get_managed_bookmarks)

    # Export symlinks
    if [[ -d "$BOOKMARKS_DIR" ]]; then
        while IFS= read -r link; do
            [[ -z "$link" ]] && continue
            local name target
            name="$(basename "$link")"
            target="$(readlink "$link")"
            echo "symlink|$name|$target" >> "$output"
            ((count++))
        done < <(get_all_links)
    fi

    if [[ $count -eq 0 ]]; then
        warn "Nothing to export"
        rm -f "$output"
    else
        success "Exported $count entry/entries to: $output"
    fi
}

cmd_import() {
    load_state

    local input="${1:-bookmarks-backup.txt}"

    if [[ ! -f "$input" ]]; then
        error "File not found: $input"
        return 1
    fi

    local imported=0 skipped=0

    while IFS='|' read -r type rest; do
        case "$type" in
            bookmark)
                local uri label
                uri="${rest%% *}"
                label="${rest#"$uri"}"
                label="${label# }"

                if is_bookmarked "$uri"; then
                    track_bookmark "$uri"
                    warn "Skipped (exists): ${label:-$uri}"
                    ((skipped++))
                else
                    add_gtk_bookmark "$uri" "$label"
                    track_bookmark "$uri"
                    success "Imported bookmark: ${label:-$uri}"
                    ((imported++))
                fi
                ;;
            symlink)
                local name target
                IFS='|' read -r name target <<< "$rest"
                local link_path="$BOOKMARKS_DIR/$name"

                if [[ -e "$link_path" ]]; then
                    warn "Skipped (exists): $name"
                    ((skipped++))
                elif [[ ! -d "$target" ]]; then
                    warn "Skipped (missing target): $name -> $target"
                    ((skipped++))
                else
                    ln -s "$target" "$link_path"
                    success "Imported symlink: $name"
                    ((imported++))
                fi
                ;;
        esac
    done < "$input"

    echo ""
    info "Result: $imported imported, $skipped skipped"
}

# --- install-completion -----------------------------------------------------
cmd_install_completion() {
    mkdir -p "$COMPLETION_DIR"

    local script_name
    script_name="$(basename "$0" .sh)"
    local completion_file="$COMPLETION_DIR/$script_name"

    cat > "$completion_file" << 'COMPLETION'
# Bash completion for bookmark-manager

_bookmark_manager() {
    local cur prev words cword
    _init_completion || return

    local commands="init add remove list edit check clean rename info open link config export import help"
    local link_commands="add remove list"

    case "${words[1]}" in
        remove|info|open|rename)
            local bookmarks_dir="${BOOKMARKS_DIR:-$HOME/Bookmarks}"
            local managed_file="$HOME/.config/system-scripts/bookmarks.managed"
            local gtk_bookmarks="$HOME/.config/gtk-3.0/bookmarks"
            local names=""
            # From symlinks
            if [[ -d "$bookmarks_dir" ]]; then
                names+=" $(find "$bookmarks_dir" -maxdepth 1 -type l -printf '%f\n' 2>/dev/null)"
            fi
            # From managed GTK bookmarks labels
            if [[ -f "$gtk_bookmarks" ]] && [[ -f "$managed_file" ]]; then
                while IFS= read -r line; do
                    local uri="${line%% *}"
                    if grep -qxF "$uri" "$managed_file" 2>/dev/null; then
                        local label="${line#"$uri"}"
                        label="${label# }"
                        [[ -n "$label" ]] && names+=" $label"
                    fi
                done < "$gtk_bookmarks"
            fi
            COMPREPLY=($(compgen -W "$names" -- "$cur"))
            return
            ;;
        add)
            case "$prev" in
                -n|--name) return ;;
            esac
            if [[ "$cur" == -* ]]; then
                COMPREPLY=($(compgen -W "-n --name -s --symlink" -- "$cur"))
            else
                _filedir -d
            fi
            return
            ;;
        link)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$link_commands" -- "$cur"))
            elif [[ "${words[2]}" == "remove" ]]; then
                local bookmarks_dir="${BOOKMARKS_DIR:-$HOME/Bookmarks}"
                if [[ -d "$bookmarks_dir" ]]; then
                    local links
                    links=$(find "$bookmarks_dir" -maxdepth 1 -type l -printf '%f\n' 2>/dev/null)
                    COMPREPLY=($(compgen -W "$links" -- "$cur"))
                fi
            elif [[ "${words[2]}" == "add" ]]; then
                _filedir -d
            fi
            return
            ;;
        config)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "show dir" -- "$cur"))
            elif [[ "${words[2]}" == "dir" ]]; then
                _filedir -d
            fi
            return
            ;;
        export|import)
            _filedir
            return
            ;;
    esac

    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
    fi
}

complete -F _bookmark_manager bookmark-manager
COMPLETION

    success "Completion installed: $completion_file"
    info "Reload your shell or run: source $completion_file"
}

# =============================================================================
# INTERACTIVE MODE
# =============================================================================

interactive_add() {
    load_state

    echo -e "${C_BOLD}${C_CYAN}Add a bookmark${C_NC}"
    echo ""

    local name
    name=$(ui_input "Bookmark name" "projects")
    [[ -z "$name" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    local default_path="$BOOKMARKS_DIR/$name"
    local path
    path=$(ui_input "Directory path" "$default_path")
    [[ -z "$path" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    # Resolve to absolute
    path="$(realpath -m "$path")"

    if [[ ! -d "$path" ]]; then
        if ui_confirm "Directory $path does not exist. Create it?"; then
            mkdir -p "$path"
            success "Directory created: $path"
        else
            echo -e "${C_YELLOW}Cancelled${C_NC}"
            return
        fi
    fi

    local create_symlink=false
    # Only offer a symlink if the target is outside ~/Bookmarks — creating one
    # inside would be redundant (the directory is already there).
    if [[ "$path" != "$BOOKMARKS_DIR" && "$path" != "$BOOKMARKS_DIR/"* ]]; then
        if ui_confirm "Also create a symlink in $BOOKMARKS_DIR?"; then
            create_symlink=true
        fi
    fi

    # Add bookmark
    local uri
    uri=$(path_to_uri "$path")
    if add_gtk_bookmark "$uri" "$name"; then
        track_bookmark "$uri"
        success "Bookmark added: ${C_BOLD}$name${C_NC} -> $path"
    fi

    # Create symlink
    if [[ "$create_symlink" == true ]] && [[ -d "$BOOKMARKS_DIR" ]]; then
        local link_path="$BOOKMARKS_DIR/$name"
        if [[ ! -e "$link_path" ]]; then
            ln -s "$path" "$link_path"
            success "Symlink created: $name"
        else
            warn "Symlink already exists: $name"
        fi
    fi
}

interactive_remove() {
    load_state

    local names=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri label
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        names+=("${label:-$(basename "$(uri_to_path "$uri")")}")
    done < <(get_managed_bookmarks)

    if [[ ${#names[@]} -eq 0 ]]; then
        warn "No managed bookmarks to remove"
        return
    fi

    echo -e "${C_BOLD}${C_CYAN}Remove a bookmark${C_NC}"
    echo ""

    local name
    name=$(ui_choose --header "Select bookmark to remove" "${names[@]}")
    [[ -z "$name" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    local also_symlink=false
    if [[ -d "$BOOKMARKS_DIR" ]] && [[ -L "$BOOKMARKS_DIR/$name" ]]; then
        if ui_confirm "Also remove symlink '$name'?"; then
            also_symlink=true
        fi
    fi

    if ui_confirm "Remove bookmark '$name'?"; then
        if [[ "$also_symlink" == true ]]; then
            cmd_remove "$name" -s
        else
            cmd_remove "$name"
        fi
    else
        echo -e "${C_YELLOW}Cancelled${C_NC}"
    fi
}

interactive_rename() {
    load_state

    local names=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri label
        uri="${line%% *}"
        label="${line#"$uri"}"
        label="${label# }"
        names+=("${label:-$(basename "$(uri_to_path "$uri")")}")
    done < <(get_managed_bookmarks)

    if [[ ${#names[@]} -eq 0 ]]; then
        warn "No managed bookmarks to rename"
        return
    fi

    echo -e "${C_BOLD}${C_CYAN}Rename a bookmark${C_NC}"
    echo ""

    local old_name
    old_name=$(ui_choose --header "Select bookmark to rename" "${names[@]}")
    [[ -z "$old_name" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    local new_name
    new_name=$(ui_input "New name" "$old_name")
    [[ -z "$new_name" || "$new_name" == "$old_name" ]] && echo -e "${C_YELLOW}Cancelled${C_NC}" && return

    cmd_rename "$old_name" "$new_name"
}

interactive_link() {
    load_state

    echo -e "${C_BOLD}${C_CYAN}Symlink management${C_NC}"
    echo ""

    # Build list of managed subdirectories inside BOOKMARKS_DIR
    local subdirs=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local uri path
        uri="${line%% *}"
        path="$(uri_to_path "$uri")"
        if [[ "$path" == "$BOOKMARKS_DIR/"* ]] && [[ -d "$path" ]]; then
            subdirs+=("$(basename "$path")")
        fi
    done < <(get_managed_bookmarks)

    if [[ ${#subdirs[@]} -eq 0 ]]; then
        warn "No bookmark subdirectories found in $BOOKMARKS_DIR"
        info "Add a bookmark inside $BOOKMARKS_DIR first"
        info "Example: bookmark-manager add $BOOKMARKS_DIR/projects -n Projects"
        return
    fi

    # Step 1: select subdirectory
    local subdir_name
    subdir_name=$(ui_choose --header "Select bookmark directory" "${subdirs[@]}")
    [[ -z "$subdir_name" ]] && return

    local link_dir="$BOOKMARKS_DIR/$subdir_name"
    echo ""

    # Step 2: select action
    local action
    action=$(ui_choose --header "Symlinks in $subdir_name" \
        "List symlinks" \
        "Add symlink" \
        "Remove symlink" \
        "Back")

    echo ""

    case "$action" in
        "List symlinks") _link_list "$link_dir" ;;
        "Add symlink")
            local name
            name=$(ui_input "Symlink name" "")
            [[ -z "$name" ]] && return

            local dir
            dir=$(ui_input "Target directory" "$(pwd)")
            [[ -z "$dir" ]] && return

            _link_add "$link_dir" "$dir" -n "$name"
            ;;
        "Remove symlink")
            local links=()
            while IFS= read -r link; do
                [[ -z "$link" ]] && continue
                links+=("$(basename "$link")")
            done < <(get_all_links "$link_dir")

            if [[ ${#links[@]} -eq 0 ]]; then
                warn "No symlinks to remove in $subdir_name"
                return
            fi

            local lname
            lname=$(ui_choose --header "Select symlink to remove" "${links[@]}")
            [[ -z "$lname" ]] && return

            if ui_confirm "Remove symlink '$lname'?"; then
                _link_remove "$link_dir" "$lname"
            fi
            ;;
        "Back"|"") return ;;
    esac
}

interactive_menu() {
    while true; do
        ui_header "BOOKMARK-MANAGER"

        local action
        action=$(ui_choose --header "What do you want to do?" \
            "List all" \
            "Add bookmark" \
            "Remove bookmark" \
            "Rename bookmark" \
            "Manage symlinks" \
            "Check integrity" \
            "Clean broken" \
            "Edit bookmarks file" \
            "Configuration" \
            "Quit")

        echo ""

        case "$action" in
            "List all")            cmd_list ;;
            "Add bookmark")        interactive_add ;;
            "Remove bookmark")     interactive_remove ;;
            "Rename bookmark")     interactive_rename ;;
            "Manage symlinks")     interactive_link ;;
            "Check integrity")     cmd_check || true ;;
            "Clean broken")        cmd_clean ;;
            "Edit bookmarks file") cmd_edit ;;
            "Configuration")       cmd_config show ;;
            "Quit"|"")             break ;;
        esac

        echo ""
        echo -e "${C_DIM}Press Enter to continue...${C_NC}"
        read -r
    done
}

# =============================================================================
# HELP
# =============================================================================

cmd_help() {
    local script_name
    script_name="$(basename "$0")"

    # Pipe through printf '%b' to interpret \033 escape sequences in C_* variables
    cat << EOF | while IFS= read -r line; do printf '%b\n' "$line"; done
${C_BOLD}$script_name${C_NC} - Nautilus bookmark & symlink manager

${C_BOLD}USAGE${C_NC}
    $script_name                            Interactive menu
    $script_name <command> [options]         CLI mode

${C_BOLD}BOOKMARK COMMANDS${C_NC}
    ${C_CYAN}init${C_NC}                         Create ~/Bookmarks dir + Nautilus sidebar entry
    ${C_CYAN}add${C_NC} [dir] [-n name] [-s]     Add bookmark (current dir by default, -s = symlink)
    ${C_CYAN}remove${C_NC} <name> [-s]           Remove bookmark (-s = also remove symlink)
    ${C_CYAN}list${C_NC}                         List all bookmarks & symlinks (with subdirectory tree)
    ${C_CYAN}edit${C_NC}                         Open bookmarks file in \$EDITOR
    ${C_CYAN}check${C_NC}                        Check for broken bookmarks & symlinks (recursive)
    ${C_CYAN}clean${C_NC}                        Remove broken entries (recursive)
    ${C_CYAN}rename${C_NC} <old> <new>           Rename bookmark (+ symlink if exists)
    ${C_CYAN}info${C_NC} <name>                  Show bookmark details
    ${C_CYAN}open${C_NC} [name]                  Open bookmark/symlink in Nautilus

${C_BOLD}SYMLINK COMMANDS${C_NC}
    ${C_CYAN}link${C_NC} <subdir> add [dir] [-n name]   Create symlink in bookmark subdirectory
    ${C_CYAN}link${C_NC} <subdir> remove <name>         Remove symlink from bookmark subdirectory
    ${C_CYAN}link${C_NC} <subdir> list                  List symlinks in bookmark subdirectory

${C_BOLD}OTHER${C_NC}
    ${C_CYAN}config${C_NC} [show|dir [path]]     View/change configuration
    ${C_CYAN}export${C_NC} [file]                Export bookmarks + symlinks
    ${C_CYAN}import${C_NC} [file]                Import from backup file
    ${C_CYAN}install-completion${C_NC}           Install bash tab completion
    ${C_CYAN}help${C_NC}                         Show this help

${C_BOLD}EXAMPLES${C_NC}
    $script_name init                          # Setup ~/Bookmarks
    $script_name add                           # Bookmark current directory
    $script_name add /code/myapp -n MyApp      # Bookmark with custom name
    $script_name add /code/myapp -s            # Bookmark + symlink
    $script_name add -s -n Projet              # Bookmark cwd + symlink as "Projet"
    $script_name remove OldProject -s          # Remove bookmark + symlink
    $script_name link projects add /code/app -n App  # Symlink in ~/Bookmarks/projects/
    $script_name list                          # Show everything
    $script_name edit                          # Edit raw bookmarks file
    $script_name check                         # Verify integrity

${C_BOLD}CONFIGURATION${C_NC}
    BOOKMARKS_DIR        Symlink directory (default: ~/Bookmarks)
    GTK_BOOKMARKS_FILE   GTK bookmarks path (default: ~/.config/gtk-3.0/bookmarks)
    EDITOR / VISUAL      Editor for 'edit' command

    State file: ~/.config/system-scripts/bookmarks.conf

EOF
}

# =============================================================================
# MAIN
# =============================================================================

# No args: interactive mode
if [[ $# -eq 0 ]]; then
    load_state
    interactive_menu
    exit 0
fi

CMD="$1"
shift

case "$CMD" in
    init)                cmd_init "$@" ;;
    add|a)               cmd_add "$@" ;;
    remove|rm|delete)    cmd_remove "$@" ;;
    list|ls|l)           cmd_list "$@" ;;
    edit|e)              cmd_edit "$@" ;;
    check|verify)        cmd_check "$@" ;;
    clean|prune)         cmd_clean "$@" ;;
    rename|mv)           cmd_rename "$@" ;;
    info|show)           cmd_info "$@" ;;
    open|o)              cmd_open "$@" ;;
    link|ln)             cmd_link "$@" ;;
    config|cfg)          cmd_config "$@" ;;
    export)              cmd_export "$@" ;;
    import)              cmd_import "$@" ;;
    install-completion)  cmd_install_completion "$@" ;;
    help|--help|-h)      cmd_help ;;
    *)
        error "Unknown command: $CMD"
        echo "Use '$(basename "$0") help' for help"
        exit 1
        ;;
esac
