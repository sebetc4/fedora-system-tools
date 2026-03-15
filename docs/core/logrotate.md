# Logrotate

> **Context purpose:**
> Log rotation configuration for system-level and user-level modules.
> Use this when adding logrotate to a module, debugging rotation issues, or understanding the two-tier pattern.

---

## Overview

The project uses two logrotate patterns depending on module type:

| | System modules | User modules |
|---|---|---|
| **Log path** | `/var/log/<module>/` | `~/.local/log/<module>/` |
| **Config format** | Static file | Template (`.tpl`) with variable substitution |
| **Installed to** | `/etc/logrotate.d/<module>` | `/etc/logrotate.d/<user>-<module>` |
| **File ownership** | `root:root` | `<user>:<user>` |
| **Rotation method** | `create` (rename + recreate) | `copytruncate` (copy + truncate in place) |
| **`su` directive** | Not needed (logrotate runs as root) | Required (`su <user> <user>`) |

Both types are processed by the system logrotate daemon (runs as root via `logrotate.timer`).

---

## System-Level Config

Static files installed with `install -m 644`. Used by system modules (`type: system`) that log to `/var/log/`.

**File location:** `modules/<module>/logrotate/<name>`

```
/var/log/<module>/*.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
```

**Current system configs:**

| Module | Config file | Log path |
|--------|------------|----------|
| clamav | `logrotate/clamav-scripts` | `/var/log/clamav/*.log` |
| backup (local) | `logrotate/backup-scripts` | `/var/log/backup/*.log` |

**How `create` works:** logrotate renames the log (`*.log` → `*.log.1`), then creates a new empty file with the specified permissions. This is safe for oneshot services (clamav scans, usb-clamscan) because they open and close the log file on each run.

---

## User-Level Config (Templates)

Template files (`.tpl`) with `__HOME__` and `__USER__` placeholders, substituted during installation via `sed`. Used by user modules (`type: user`) that log to `~/.local/log/`.

**File location:** `modules/<module>/logrotate/user-logs.tpl`

```
__HOME__/.local/log/<module>/*.log {
    su __USER__ __USER__
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

**Current user templates:**

| Module | Template | Log path | Installed as |
|--------|----------|----------|-------------|
| notifications | `logrotate/user-logs.tpl` | `~/.local/log/notifications/*.log` | `/etc/logrotate.d/<user>-notifications` |
| backup-vps | `logrotate/user-logs.tpl` | `~/.local/log/backup-vps/*.log` | `/etc/logrotate.d/<user>-backup-vps` |
| backup (bitwarden) | `bitwarden/logrotate/user-logs.tpl` | `~/.local/log/backup-bitwarden/*.log` | `/etc/logrotate.d/<user>-backup-bitwarden` |

### Why `su` and `copytruncate`

**`su <user> <user>`** — The system logrotate runs as root, but user logs live in `~/.local/log/` inside home directories with `0700` permissions. The `su` directive tells logrotate to perform the rotation as the target user, avoiding permission conflicts.

**`copytruncate`** — Instead of renaming the log file (which breaks file descriptors held by running daemons), logrotate copies the log content to a rotated file, then truncates the original to zero bytes. The running process keeps writing to the same file without interruption.

This is required for long-running daemons like `notify-daemon` that keep a file descriptor open. It is also safe for oneshot services (backup-vps, backup-bitwarden) and avoids the need for `postrotate` reload scripts.

**No `create` directive** — With `copytruncate`, the original file is never removed or recreated, so `create` is unnecessary.

---

## Installation

### Submodule engine (automatic)

Submodules declare their logrotate config in `module.yml`:

```yaml
submodules:
  core:
    logrotate: logrotate/clamav-scripts      # Static file
  bitwarden:
    logrotate: bitwarden/logrotate/user-logs.tpl  # Template
```

`lib/submodule.sh` handles installation automatically during `submodule_install`:

- **Static files** → `install -m 644` to `/etc/logrotate.d/<basename>`
- **Templates** (`.tpl`) → `sed` substitution of `__HOME__` and `__USER__`, then write to `/etc/logrotate.d/<basename without .tpl>`

Uninstallation removes the config via `rm -f "/etc/logrotate.d/<basename>"`.

### Standalone modules (manual)

Standalone user modules install logrotate in their `install.sh`:

```bash
CURRENT_USER="$(whoami)"
LOGROTATE_FILE="/etc/logrotate.d/${CURRENT_USER}-backup-vps"
sed -e "s|__HOME__|$HOME|g" -e "s|__USER__|$CURRENT_USER|g" \
    "$SCRIPT_DIR/logrotate/user-logs.tpl" \
    | sudo tee "$LOGROTATE_FILE" > /dev/null
```

Uninstallation:

```bash
sudo rm -f "/etc/logrotate.d/${CURRENT_USER}-backup-vps"
```

---

## Standard Options

All logrotate configs in the project use the same base options:

| Option | Value | Purpose |
|--------|-------|---------|
| `weekly` | — | Rotate once per week |
| `rotate 4` | — | Keep 4 rotated copies |
| `compress` | — | Gzip compress rotated logs |
| `delaycompress` | — | Compress on the next rotation cycle (keeps `.log.1` uncompressed for debugging) |
| `missingok` | — | Don't error if log file is missing |
| `notifempty` | — | Skip rotation if log is empty |

---

## Debugging

Check logrotate state for a specific config:

```bash
sudo logrotate -d /etc/logrotate.d/seb-notifications
```

Check when a log was last rotated:

```bash
grep "notifications" /var/lib/logrotate/logrotate.status
```

Force rotation for testing:

```bash
sudo logrotate -f /etc/logrotate.d/seb-notifications
```

List all project logrotate configs:

```bash
ls /etc/logrotate.d/*-notifications /etc/logrotate.d/*-backup-vps \
   /etc/logrotate.d/clamav-scripts \
   /etc/logrotate.d/backup-scripts 2>/dev/null
```

---

*Last Updated: February 27, 2026*
