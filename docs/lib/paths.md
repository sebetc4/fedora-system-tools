# paths.sh — Locale-Aware Download Path Detection

> Detects download directories using XDG user-dirs and generates `paths.conf`. Supports both French (`Téléchargements`) and English (`Downloads`) systems.

**Guard:** `_LIB_PATHS_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** `lib/install.sh`

---

## Detection Strategy

Two methods tried in order:

1. **`~/.config/user-dirs.dirs`** — parses `XDG_DOWNLOAD_DIR` as text and expands `$HOME`. The
   file is never sourced, nor read through `xdg-user-dir`, which sources it: under `sudo`, a
   folder name holding `$(...)` would otherwise run as root.
2. **Filesystem probe** — when XDG names no folder, names the home itself (XDG's fallback) or a
   folder that does not exist: checks `~/Téléchargements` then `~/Downloads`, and falls back to a
   locale-based default. The home is never returned, which would make ClamAV watch all of it.

---

## Functions

### `detect_download_dir [user]`

Returns the download directory path for a user (defaults to `$USER`).

```bash
detect_download_dir           # current user
detect_download_dir "alice"   # specific user
```

### `detect_watch_dirs [user]`

Returns a deduplicated, sorted list of directories to monitor (one per line). Always includes the main download dir, plus any extra common locations that exist on disk.

```bash
while IFS= read -r dir; do
    echo "Watching: $dir"
done < <(detect_watch_dirs)
```

### `generate_paths_conf [user]`

Outputs a complete `paths.conf` to stdout. Installed to `/etc/system-scripts/paths.conf` by `lib/install.sh`.

Generated variables:
- `TARGET_USER` / `TARGET_HOME`
- `DOWNLOAD_DIR` — main download directory
- `EXPORT_DIR` — destination for processed files (same as download dir)
- `WATCH_DIRS` — bash array of directories to monitor

Root scripts source this file, so every value is single-quoted, a `'` written `'\''`: a folder
name stays data whatever it holds.

```bash
generate_paths_conf "$USER" > /etc/system-scripts/paths.conf
```
