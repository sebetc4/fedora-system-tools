# color.sh — Customizable UI Color Theme

> Loads color configuration from conf files and exports `GUM_*` environment variables for consistent theming across all interactive scripts.

**Guard:** `_LIB_COLOR_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** `ui.sh`, module installers

---

## Config Lookup Order

1. `COLOR_CONF` env var (if set, uses only this file)
2. `/etc/system-scripts/color.conf` (system default)
3. `~/.config/system-scripts/color.conf` (user override, layered on top)

When running under `sudo`, the real user's home is resolved via `SUDO_USER`.

## Color Variables

### Primary

| Variable | Default | Purpose |
|---|---|---|
| `COLOR_ACCENT` | `#4f9872` | Primary accent (cursors, selections, banners) |
| `COLOR_HEADER` | `#4f9872` | Header border color |
| `COLOR_HEADER_TEXT` | `#ECEEEC` | Header text color |
| `COLOR_SELECTION_TITLE` | `#4f9872` | `gum choose --header` text |
| `COLOR_ERROR` | `1` (ANSI red) | Error border accent |

### Per-Component Overrides

Internal `_CLR_*` variables for fine-grained Gum component theming. All default to empty (inherit from `COLOR_ACCENT`):

- `_CLR_CHOOSE_CURSOR_FG` / `_CLR_CHOOSE_SELECTED_FG` — defaults `#CBB99F`
- `_CLR_INPUT_PROMPT_FG` / `_CLR_INPUT_CURSOR_FG`
- `_CLR_FILTER_INDICATOR_FG` / `_CLR_FILTER_MATCH_FG`
- `_CLR_CONFIRM_SELECTED_FG`
- `_CLR_SPIN_SPINNER_FG`

### Terminal Color Overrides

`_CLR_TERM_*` variables override `C_RED`, `C_GREEN`, `C_YELLOW`, `C_CYAN`, `C_BLUE`, `C_MAGENTA` from `core.sh`. Only applied when stdout is a terminal (`[[ -t 1 ]]`).

---

## Config File Format

```ini
# color.conf
accent=#4f9872
header_border=#4f9872
header_text=#ECEEEC
selection_title=#4f9872
error=1
choose_cursor_foreground=#CBB99F
term_red=\e[38;5;196m
```

Lines starting with `#` and empty lines are ignored.

---

## Functions

### `_color_load_conf file`

Parse a `KEY=VALUE` config file and set color variables. Skips comments and empty lines.

### `_color_user_conf`

Returns the path to the user's color.conf (`~/.config/system-scripts/color.conf`), resolving `SUDO_USER` when running as root.

### `_color_apply_gum`

Exports `GUM_*` environment variables from the loaded color values. No-op if Gum is not installed.

### `color_reload`

Resets all color values to defaults, reloads config files, and re-applies Gum exports. Call after modifying `color.conf` to update the running session.
