# paths.sh — Locale-Aware Download Path Detection

> Detects download directories using XDG user-dirs and generates `paths.conf`. Supports both French (`Téléchargements`) and English (`Downloads`) systems.

**Guard:** `_LIB_PATHS_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** `lib/install.sh`

---

## Detection Strategy

Three methods tried in order:

1. **`xdg-user-dir DOWNLOAD`** — if available and running as the target user
2. **`~/.config/user-dirs.dirs`** — parses `XDG_DOWNLOAD_DIR` from config file, expands `$HOME`
3. **Filesystem probe** — checks `~/Téléchargements` then `~/Downloads`; falls back to locale-based default

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
detect_watch_dirs | while IFS= read -r dir; do
    echo "Watching: $dir"
done
```

### `generate_paths_conf [user]`

Outputs a complete `paths.conf` to stdout. Installed to `/etc/system-scripts/paths.conf` by `lib/install.sh`.

Generated variables:
- `TARGET_USER` / `TARGET_HOME`
- `DOWNLOAD_DIR` — main download directory
- `EXPORT_DIR` — destination for processed files (same as download dir)
- `WATCH_DIRS` — bash array of directories to monitor

```bash
generate_paths_conf "$USER" > /etc/system-scripts/paths.conf
```
