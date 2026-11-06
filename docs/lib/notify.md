# notify.sh — Notification Registration Helpers

> Register and unregister notification tags with the `notify-daemon` configuration files. Works independently of the notifications module being installed.

**Guard:** `_LIB_NOTIFY_LOADED`
**Dependencies:** none (standalone, uses systemctl directly)
**Sourced by:** module installers (clamav, backup, torrent)

---

## Managed Files

All files live in `~/.config/notify-daemon/` (resolved via `SUDO_USER` when running as root):

| File | Format | Purpose |
|---|---|---|
| `services.conf` | one tag per line | Tags monitored by notify-daemon |
| `icons.conf` | `tag=icon_name` | Custom icon per tag |
| `levels.conf` | `tag=level` | Notification level (`all`, `important`, `none`) |

---

## Functions

### `notify_register tag [icon] [level]`

Register a notification tag. Idempotent — safe to call multiple times.

- Creates `~/.config/notify-daemon/` if needed
- Adds `tag` to `services.conf` (skips if already present)
- Adds `tag=icon` to `icons.conf` if icon provided (skips if already present)
- Adds `tag=level` to `levels.conf` if level provided **and not already set** (preserves user customizations)
- Under `sudo`, creates the folder as `SUDO_USER` through `runuser`, its missing parents included, and gives the user the files it writes
- Reloads `notify-daemon.service` if active

```bash
notify_register "daily-clamscan" "security-high" "all"
notify_register "backup-vps"
```

### `notify_unregister tag`

Remove a notification tag from all config files.

- Removes exact line `tag` from `services.conf`
- Removes `tag=*` line from `icons.conf`
- Removes `tag=*` line from `levels.conf`
- Deletes `services.conf` and `icons.conf` once no active entry remains (only comments/blank lines left), `levels.conf` once it holds nothing but the `default=all` that `notify_register` wrote, and `~/.config/notify-daemon/` once empty
- Reloads `notify-daemon.service` if active

```bash
notify_unregister "daily-clamscan"
```

### `_notify_resolve_home` (internal)

Returns the target user's home directory. Uses `SUDO_USER` when running as root, otherwise `$HOME`.

### `_notify_reload_daemon` (internal)

Reloads `notify-daemon.service` if it exists and is active. Handles the `sudo` → user systemd context switch via `XDG_RUNTIME_DIR`.
