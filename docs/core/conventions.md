# Conventions

Coding and visual conventions used throughout the project.

## Strict mode

All scripts use:

```bash
set -euo pipefail
trap 'echo "ERROR: ... failed at line $LINENO" >&2; exit 1' ERR
```

### Exceptions

**Daemon/service scripts** may omit `-e` with a documented comment. These
scripts handle errors explicitly to avoid the service dying on non-fatal
failures:

- `daily-clamscan.sh` — scans continue even if one path fails
- `weekly-clamscan.sh` — same rationale
- `download-clamscan.sh` — long-running daemon
- `usb-clamscan.sh` — triggered by udev, must not abort mid-scan

**Interactive tools** may omit `-e` when errors are handled per-command:

- `bookmark-manager.sh` — interactive menu handles errors explicitly

The omission must be documented with a comment in the script header.

## Color variables — `C_*`

Defined in `lib/core.sh`. Automatically disabled when stdout is not a TTY.

| Variable | ANSI code | Semantic usage |
|----------|-----------|----------------|
| `C_RED` | `\033[0;31m` | Errors, not-installed status |
| `C_GREEN` | `\033[0;32m` | Success, up-to-date status |
| `C_YELLOW` | `\033[1;33m` | Warnings, updates available |
| `C_BLUE` | `\033[0;34m` | Informational messages |
| `C_CYAN` | `\033[0;36m` | Section borders (with `C_BOLD`) |
| `C_MAGENTA` | `\033[0;35m` | Special highlights |
| `C_BOLD` | `\033[1m` | Emphasis, prompts, column headers, labels |
| `C_DIM` | `\033[2m` | Debug output, inactive/unavailable items |
| `C_NC` | `\033[0m` | Reset (No Color) |

### Semantic combinations

| Context | Colors |
|---------|--------|
| Section titles & headers | `C_BOLD` + `C_CYAN` |
| Success messages | `C_GREEN` |
| Warnings | `C_YELLOW` |
| Errors | `C_RED` |
| Info messages | `C_BLUE` |
| Column headers, labels | `C_BOLD` |
| Inactive/unavailable items | `C_DIM` |

### Usage in lib functions

The `core.sh` typed-message functions apply colors automatically:

```bash
error "Something failed"     # C_RED prefix
warn "Check this"            # C_YELLOW prefix
success "Done"               # C_GREEN prefix
info "Note"                  # C_BLUE prefix
debug "Trace"                # C_DIM prefix
```

## Color customization — `color.conf`

Colors can be customized per-system and per-user without modifying scripts.

### Config lookup order

1. `COLOR_CONF` env var (if set → only this file, no further lookup)
2. `/etc/system-scripts/color.conf` (system default, installed by lib)
3. `~/.config/system-scripts/color.conf` (user override, layered on top)

Under `sudo`, the real user's home is resolved via `SUDO_USER`.

### Config format

```ini
# color.conf — KEY=VALUE, # comments and empty lines ignored

# Theme accents (hex colors or ANSI color numbers)
accent=#4f9872
header_border=#4f9872
header_text=#ECEEEC
selection_title=#4f9872
error=1

# Per-component Gum overrides (all optional)
choose_cursor_foreground=#CBB99F
choose_selected_foreground=#CBB99F

# Terminal color overrides (ANSI escape sequences)
term_red=\033[0;31m
term_green=\033[0;32m
```

### Theme variables

| Variable | Default | Applied to |
|----------|---------|------------|
| `COLOR_ACCENT` | `#4f9872` | Gum cursors, selections, banners |
| `COLOR_HEADER` | `#4f9872` | Header border color |
| `COLOR_HEADER_TEXT` | `#ECEEEC` | Header text |
| `COLOR_SELECTION_TITLE` | `#4f9872` | `gum choose --header` text |
| `COLOR_ERROR` | `1` (ANSI red) | Error banner border |

### Terminal color overrides

`_CLR_TERM_*` keys in `color.conf` override the hardcoded `C_*` variables:

| Config key | Overrides |
|------------|-----------|
| `term_red` | `C_RED` |
| `term_green` | `C_GREEN` |
| `term_yellow` | `C_YELLOW` |
| `term_cyan` | `C_CYAN` |
| `term_blue` | `C_BLUE` |
| `term_magenta` | `C_MAGENTA` |

Only applied when stdout is a TTY.

### Reloading

Call `color_reload()` to reset and re-apply colors from config files.

See [docs/lib/color.md](../lib/color.md) for full API documentation.

## Self-contained scripts

Scripts triggered by systemd or running independently (e.g., `backup-vps.sh`,
scan daemons) **do not source the shared lib**. They define their own colors
and logging inline to avoid the `lib/` dependency at runtime.

---

*Last Updated: March 9, 2026*
