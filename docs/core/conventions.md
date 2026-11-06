# Conventions

Coding and visual conventions used throughout the project, and where personal settings live.
Versions follow [Versioning](versioning.md), installed files are listed in
[State, Configuration & Installed Paths](state-and-paths.md), and a module is reviewed against
[Module Review](module-review.md).

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

### Arithmetic under `set -e`

An arithmetic command, `(( ))`, returns status 1 whenever its expression evaluates to 0, and
`set -e` then ends the script without a message. `((n++))` evaluates to the old value, so a
counter starting at 0 stops the script the first time it is incremented:

```bash
bash -c 'set -e; n=0; ((n++)); echo reached'      # prints nothing, exits 1
bash -c 'set -e; n=0; n=$((n + 1)); echo reached' # prints "reached"
```

Increment with an assignment, `n=$((n + 1))`, never with `((n++))`, `((++n))` or
`((n += 1))` as a statement: the last two fail too as soon as the result is 0. `(( ))` stays
for conditions, in `if (( n > 0 ))` or `while (( i < max ))`, where its status is the point.

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

## Real user and home

A script running under `sudo` acts for the user who called it: `detect_real_user` from
`lib/fs.sh` sets `REAL_USER` and `REAL_HOME` from `SUDO_USER`. A user's home comes from the
password database, never from tilde expansion through `eval`, which runs whatever the name
holds:

```bash
home=$(getent passwd "$user" | cut -d: -f6)   # never: eval echo "~$user"
```

## Installers

- No heredocs: a static file (logrotate config, systemd unit) is stored in the module and
  installed with `install -m 644`; a dynamic one is a template with `__PLACEHOLDER__` values
  filled by `sed`.
- Packages come from Fedora's repositories. A third-party repository or download is used only
  when Fedora does not ship the software, with its key or checksum verified: a key import is
  never followed by `|| true`.
- An install or upgrade never overwrites a config file the user may have edited.

## Personal settings

The repository is public and holds generic defaults only, such as the `my-vps` placeholder of
`backup/vps`. The user's own values live in the config files a module installs on the machine
(`~/.config/…`, `/etc/…`), which an install or upgrade never overwrites. Copies of those files
are kept in `my-config/` at the checkout's root, ignored by git, laid out like the repository's
tree: `my-config/modules/backup/vps/config.yml` is the user's copy of
`modules/backup/vps/config.yml`, kept to restore it after a reinstall. The postinstall
`personal` profile holds only choices fit to publish: packages, Flatpaks, desktop settings.

No tracked file holds:

- a secret: password, token, API key, private key, VPN credentials;
- the name or address of one of the user's hosts;
- an account name or an email address;
- a path or a value of the user's own, where a generic default can stand.

## Decisions

### 2026-11-06 — Personal settings live on the machine, never in the repository

Decided with the user while framing the review of the modules for Fedora 45; it shapes
Personal settings above, and every module's defaults are checked against its list.

- Set aside: the installed config files alone, with no copy, since a reinstall would lose
  them.
- Set aside: the postinstall `personal` profile, since it is tracked and the repository is
  public.
- Facts: `my-config/` already held the user's copies of the backup configs, laid out like the
  repository's tree, and `.gitignore` already excluded it.
- Revisit: if the repository stops being public.
