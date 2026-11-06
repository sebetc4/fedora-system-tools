#!/usr/bin/env bats
# =============================================================================
# COLOR.BATS - Unit tests for lib/color.sh
# =============================================================================
# Covers the color.conf reader and color_reload, on a config written in the
# test's temporary directory through COLOR_CONF.
#
# Run: make test
# =============================================================================

setup() {
    export COLOR_CONF="$BATS_TEST_TMPDIR/color.conf"
    cat > "$COLOR_CONF" <<'CONF'
# Accent first
accent = #112233
  # an indented comment

error=9
choose_cursor_foreground=#445566
unknown_key=whatever
CONF
    source "$BATS_TEST_DIRNAME/../../../lib/color.sh"
}

@test "color.conf: keys are read, spaces around = trimmed, comments and unknown keys ignored" {
    [[ "$COLOR_ACCENT" == "#112233" && "$COLOR_ERROR" == "9" && "$_CLR_CHOOSE_CURSOR_FG" == "#445566" ]] \
        || { echo "accent='$COLOR_ACCENT' error='$COLOR_ERROR' cursor='$_CLR_CHOOSE_CURSOR_FG'"; return 1; }
}

@test "color.conf: a key it leaves out keeps its default" {
    [[ "$COLOR_HEADER" == "#4f9872" && "$COLOR_HEADER_TEXT" == "#ECEEEC" && -z "$_CLR_INPUT_PROMPT_FG" ]] \
        || { echo "header='$COLOR_HEADER' header_text='$COLOR_HEADER_TEXT' prompt='$_CLR_INPUT_PROMPT_FG'"; return 1; }
}

@test "color_reload: a key removed from color.conf goes back to its default" {
    echo "header_border=#778899" > "$COLOR_CONF"
    color_reload
    [[ "$COLOR_ACCENT" == "#4f9872" && "$COLOR_ERROR" == "1" && "$_CLR_CHOOSE_CURSOR_FG" == "#CBB99F" && "$COLOR_HEADER" == "#778899" ]] \
        || { echo "accent='$COLOR_ACCENT' error='$COLOR_ERROR' cursor='$_CLR_CHOOSE_CURSOR_FG' header='$COLOR_HEADER'"; return 1; }
}

@test "color.conf: a missing file leaves every default" {
    rm -f "$COLOR_CONF"
    color_reload
    [[ "$COLOR_ACCENT" == "#4f9872" && "$COLOR_SELECTION_TITLE" == "#4f9872" ]] || { echo "accent='$COLOR_ACCENT'"; return 1; }
}
