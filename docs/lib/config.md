# config.sh — Centralized Configuration Loading

> Loads `paths.conf` (or any config file) by sourcing it into the current shell.

**Guard:** `_LIB_CONFIG_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** torrent scripts, clamav download-clamscan

---

## Constants

| Name | Value |
|---|---|
| `DEFAULT_CONFIG` | `/etc/system-scripts/paths.conf` |

---

## Functions

### `load_config [file]`

Source a configuration file. Defaults to `/etc/system-scripts/paths.conf`.

Exits with error if the file does not exist.

```bash
load_config                           # loads paths.conf
load_config "/etc/custom/scan.conf"   # loads a specific config
```

The loaded file's variables (e.g., `DOWNLOAD_DIR`, `WATCH_DIRS`, `TARGET_USER`) become available in the calling script's scope.
