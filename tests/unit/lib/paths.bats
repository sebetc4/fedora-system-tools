#!/usr/bin/env bats
# =============================================================================
# PATHS.BATS - Unit tests for lib/paths.sh
# =============================================================================
# Covers the download directory detection and the paths.conf it generates,
# which root scripts source: a folder name must come back as data, never run.
# Each test builds a home under its own temporary directory.
#
# Run: make test
# =============================================================================

setup() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.config"
    source "$BATS_TEST_DIRNAME/../../../lib/paths.sh"
}

# Write a user-dirs.dirs whose download folder is <name>, and create it
set_download_dir() {
    mkdir -p "$HOME/$1"
    printf "XDG_DOWNLOAD_DIR=\"\$HOME/%s\"\n" "$1" > "$HOME/.config/user-dirs.dirs"
}

@test "detect_download_dir: the folder user-dirs.dirs names" {
    set_download_dir "Téléchargements"
    run detect_download_dir
    [[ "$output" == "$HOME/Téléchargements" ]] || { echo "got '$output'"; return 1; }
}

@test "detect_download_dir: without user-dirs.dirs, an existing Downloads, never the home" {
    mkdir -p "$HOME/Downloads"
    run detect_download_dir
    [[ "$output" == "$HOME/Downloads" ]] || { echo "got '$output'"; return 1; }
}

@test "detect_watch_dirs: the download folder and the other one that exists, once each" {
    set_download_dir "Téléchargements"
    mkdir -p "$HOME/Downloads"
    run detect_watch_dirs
    [[ "$output" == "$HOME/Downloads"$'\n'"$HOME/Téléchargements" ]] || { echo "got '$output'"; return 1; }
}

@test "generate_paths_conf: sourcing it gives back the paths, and runs nothing they hold" {
    local name="dl \$(touch $BATS_TEST_TMPDIR/ran) it's \`x\` \\n"
    set_download_dir "$name"
    generate_paths_conf > "$BATS_TEST_TMPDIR/paths.conf"
    (
        # shellcheck source=/dev/null
        source "$BATS_TEST_TMPDIR/paths.conf"
        [[ "${DOWNLOAD_DIR:-}" == "$HOME/$name" ]] || { echo "DOWNLOAD_DIR='${DOWNLOAD_DIR:-}'"; exit 1; }
        [[ "${WATCH_DIRS[0]}" == "$HOME/$name" ]] || { echo "WATCH_DIRS[0]='${WATCH_DIRS[0]}'"; exit 1; }
        [[ "$TARGET_HOME" == "$HOME" ]] || { echo "TARGET_HOME='$TARGET_HOME'"; exit 1; }
    )
    [[ ! -e "$BATS_TEST_TMPDIR/ran" ]] || { echo "a folder name ran as a command"; return 1; }
}
