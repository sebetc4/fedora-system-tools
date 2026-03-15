# Notification System

> **Context purpose:**
> Architecture and conventions for the desktop notification system based on journald and notify-daemon.
> Use this when adding notifications to a module, debugging notification issues, or understanding the tag convention.

---

## Overview

Scripts send notifications via `logger` (systemd journal). A user-level daemon (`notify-daemon.service`) monitors specific journal tags and dispatches desktop notifications using `notify-send`.

```
Script                  journald                    notify-daemon           Desktop
  │                        │                            │                     │
  ├─ logger -t TAG ──────► │ SYSLOG_IDENTIFIER=TAG ───► │ process_notification │
  │   -p user.PRIORITY     │ PRIORITY=N                 │     │               │
  │                        │                            │     ├─► notify-send ─► Popup
  │                        │                            │     └─► email (opt)  │
  │                        │                            │                     │
  ├─ stdout (from script) ► │ SYSLOG_IDENTIFIER=BINARY  │  (ignored — different tag)
```

---

## Tag Convention

### The `notify-` Prefix

All notification tags **must** use the `notify-` prefix:

```
notify-<module>-<purpose>
```

| Tag | Module | Scripts |
|-----|--------|---------|
| `notify-daily-scan` | clamav | daily-clamscan |
| `notify-weekly-scan` | clamav | weekly-clamscan |
| `notify-download-scan` | clamav | download-clamscan |
| `notify-usb-scan` | clamav | usb-clamscan |
| `notify-backup-system` | backup | system |
| `notify-backup-hdd` | backup | hdd |
| `notify-backup-hdd-both` | backup | hdd-both |
| `notify-backup-vps` | backup | vps |

### Why the Prefix is Required

When a script runs as a systemd service, systemd automatically tags **all stdout/stderr** with the binary name as `SYSLOG_IDENTIFIER`. If the notification tag matches the binary name, notify-daemon receives both intentional `logger` calls **and** every stdout line — causing notification spam.

The `notify-` prefix guarantees the notification tag never collides with any binary name or systemd service identifier.

**Example — without prefix (broken):**

```
binary name:      backup-vps          ← systemd sets SYSLOG_IDENTIFIER=backup-vps
notification tag: backup-vps          ← same! Every stdout line becomes a notification
```

**Example — with prefix (correct):**

```
binary name:      backup-vps          ← systemd sets SYSLOG_IDENTIFIER=backup-vps
notification tag: notify-backup-vps   ← different — only explicit logger calls match
```

---

## Architecture

### Components

| Component | Path | Role |
|-----------|------|------|
| notify-daemon | `modules/notifications/scripts/notify-daemon.sh` | Journald listener, dispatches desktop notifications |
| notify-manage | `modules/notifications/scripts/notify-manage.sh` | CLI to list/add/remove/test monitored tags |
| lib/notify.sh | `lib/notify.sh` | Registration helpers (`notify_register`, `notify_unregister`) |
| lib/submodule.sh | `lib/submodule.sh` | Auto-registers tags from `module.yml` during install |

### Configuration Files

All stored in `~/.config/notify-daemon/`:

**`services.conf`** — Tags monitored by the daemon (one per line):

```
# Services monitored by notify-daemon (one per line)
notify-daily-scan
notify-weekly-scan
notify-download-scan
notify-usb-scan
notify-backup-vps
```

**`icons.conf`** — Default icon per tag:

```
# Format: tag=icon_name
notify-daily-scan=security-high
notify-weekly-scan=security-high
notify-download-scan=security-medium
notify-usb-scan=drive-removable-media
notify-backup-system=drive-harddisk
notify-backup-hdd=drive-harddisk
notify-backup-hdd-both=drive-harddisk
notify-backup-vps=drive-harddisk
```

**`levels.conf`** — Per-tag notification level filter:

```ini
# Levels: all | important | none
# Tags not listed inherit the default level
default=all

notify-daily-scan=important
notify-weekly-scan=important
notify-download-scan=important
notify-backup-system=important
notify-backup-hdd=important
notify-backup-hdd-both=important
notify-backup-vps=important
```

**`state`** — Last processed journal timestamp (microseconds since epoch):

```
1709312345678901
```

The daemon writes this file after each processed notification. On restart, entries with a timestamp ≤ the saved value are skipped — preventing duplicate desktop notifications when the daemon restarts or journald replays recent entries.

### Log File

`~/.local/log/notifications/notify-daemon.log`

---

## Priority Levels

Scripts control notification urgency via syslog priority:

| Syslog Priority | Level | Desktop Behavior | Use For |
|-----------------|-------|------------------|---------|
| `user.crit` (2) | critical | Popup + email | Virus found, backup failed |
| `user.err` (3) | critical | Popup + email | Service errors |
| `user.warning` (4) | warning | Popup (yellow) | Partial failures, stale signatures |
| `user.notice` (5) | normal | Popup (info) | Scan clean, backup complete |
| `user.info` (6) | info | Panel only (no popup) | Informational summaries |

The daemon also overrides priority based on keyword detection:
- `virus`, `infected`, `malware` → forced `critical`
- `error`, `failed`, `failure` → forced `warning`

---

## Notification Levels

Each tag has a **notification level** that controls which urgencies trigger a desktop notification. The daemon evaluates the level after priority conversion, before calling `notify-send`. Scripts always emit `logger` unconditionally — the daemon decides whether to forward the notification.

### Levels

| Level | Urgencies delivered | Typical use |
|-------|--------------------|--------------|
| `all` | critical, warning, normal, info | Every event (USB scans, interactive scripts) |
| `important` | critical, warning only | Scheduled tasks — threats and errors only |
| `none` | — | Silenced (journald still receives all logs) |

The recommended default for **scheduled tasks** is `important` — success notifications from timers (daily scan, backup) create noise. The `all` level suits infrequent, user-triggered operations where confirming success is useful.

### Configuration: `levels.conf`

`~/.config/notify-daemon/levels.conf` maps tags to levels:

```ini
# Levels: all | important | none
# Tags not listed inherit the default level
default=all

notify-daily-scan=important
notify-weekly-scan=important
notify-download-scan=important
notify-backup-vps=important
```

The `default=` key applies to any tag without an explicit entry.

### Managing Levels

```bash
notify-manage level                                       # Show all tag levels
notify-manage level notify-backup-vps                     # Show level for one tag
notify-manage level notify-backup-vps important           # Set to important
notify-manage level notify-daily-scan none                # Silence a tag
notify-manage level notify-usb-scan all                   # Receive all events
```

### Module Default Level

Modules declare a **suggested** default level in `module.yml`:

```yaml
notifications:
  - tag: notify-daily-scan
    icon: security-high
    level: important    # Written to levels.conf only if no entry exists yet
```

This is written to `levels.conf` during `submodule_install` **only if no level is already configured** for that tag. User customizations are always preserved.

Icons are resolved in priority order:

1. **Inline directive** — `[ICON:icon-name]` at the start of the message
2. **Service config** — `icons.conf` mapping for the tag
3. **Urgency default** — `dialog-error` (critical), `dialog-warning` (warning), `dialog-information` (normal/info)

Common icons:

| Icon | Usage |
|------|-------|
| `security-high` | Clean scan |
| `security-low` | Virus found |
| `security-medium` | Download scan |
| `dialog-error` | Fatal errors |
| `dialog-warning` | Warnings |
| `drive-harddisk` | Backup operations |
| `drive-removable-media` | USB operations |
| `emblem-synchronizing` | Sync/transfer complete |

---

## Sending Notifications from Scripts

### Pattern: Single Notification at End

Scripts should use `logger` only for **final status** — not for progress or debug output. File logging (`log()`) handles the detailed audit trail.

**Self-contained script** (no shared lib):

```bash
readonly LOG_TAG="notify-mymodule-task"

# File logging — no notifications
log() {
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$message" >> "$LOG_FILE"
    echo "$message"
}

# ... script logic with log() calls ...

# Single notification at the end
if [[ "$ERRORS" -gt 0 ]]; then
    logger -t "$LOG_TAG" -p user.crit "[ICON:dialog-error] Task failed: $ERRORS error(s)"
else
    logger -t "$LOG_TAG" -p user.notice "[ICON:dialog-information] Task completed successfully"
fi
```

**Script with dedicated notification function** (daemon-filtered):

```bash
readonly LOG_TAG="notify-backup-hdd"

# Always emit — notify-daemon filters based on levels.conf
# Use: notify-manage level notify-backup-hdd [all|important|none]
send_notification() {
    local type="$1" title="$2" message="$3"

    case "$type" in
        success)
            logger -t "$LOG_TAG" -p user.notice "[ICON:drive-harddisk] $title: $message"
            ;;
        error)
            logger -t "$LOG_TAG" -p user.err "[ICON:dialog-error] $title: $message"
            ;;
    esac
}
```

### Message Format

```bash
logger -t "$LOG_TAG" -p "user.<priority>" "[ICON:<icon-name>] <message>"
```

- **Tag** (`-t`): Must use the `notify-` prefixed tag from `LOG_TAG`
- **Priority** (`-p`): Syslog priority (see table above)
- **Icon directive**: Optional `[ICON:name]` prefix, stripped by the daemon before display
- **Message**: Concise summary — this appears in the desktop popup

---

## Registering Tags

### Automatic (submodule engine)

Tags declared in `module.yml` are auto-registered during `submodule_install` and auto-unregistered during `submodule_uninstall`:

```yaml
# module.yml
submodules:
  my-script:
    notifications:
      - tag: notify-mymodule-task
        icon: dialog-information
```

`lib/submodule.sh` calls `notify_register` / `notify_unregister` from `lib/notify.sh`.

### Manual (standalone modules)

Standalone modules that don't use the submodule engine register tags directly in their `install.sh`:

```bash
# Using lib/notify.sh (if available)
source "$LIB_DIR/notify.sh"
notify_register "notify-backup-vps" "drive-harddisk"
```

Or via direct file manipulation (no lib dependency):

```bash
NOTIFY_DIR="$HOME/.config/notify-daemon"
grep -qxF "notify-backup-vps" "$NOTIFY_DIR/services.conf" 2>/dev/null \
    || echo "notify-backup-vps" >> "$NOTIFY_DIR/services.conf"
```

### Management CLI

```bash
notify-manage list                                        # Show monitored tags
notify-manage add notify-my-tag --icon dialog-information # Register a tag
notify-manage remove notify-my-tag                        # Unregister a tag
notify-manage level notify-daily-scan                     # Show level for a tag
notify-manage level notify-daily-scan important           # Set level
notify-manage test notify-daily-scan                      # Send test notifications (shows current level)
```

Changes via `notify-manage` (add, remove, level) automatically reload the daemon if it is running. No manual restart needed.

---

## Systemd Service Considerations

For scripts that run as systemd services (via timers), add these directives to prevent stdout from leaking into journald with the binary's tag:

```ini
[Service]
StandardOutput=null
StandardError=journal
```

This ensures only explicit `logger` calls (with the `notify-` prefixed tag) reach the daemon. Stderr is still captured in the journal for debugging via `journalctl --user -u service-name`.

---

## Debugging

Check if notify-daemon is running:

```bash
systemctl --user status notify-daemon.service
```

View daemon logs:

```bash
tail -f ~/.local/log/notifications/notify-daemon.log
```

List registered tags:

```bash
notify-manage list
# or directly:
cat ~/.config/notify-daemon/services.conf
```

Send a test notification:

```bash
logger -t notify-backup-vps -p user.notice "[ICON:drive-harddisk] Test notification"
```

Check what the daemon receives from journald:

```bash
journalctl -f -t notify-backup-vps -o json | jq '{MESSAGE, PRIORITY, SYSLOG_IDENTIFIER}'
```

Check or reset daemon state (last processed timestamp):

```bash
cat ~/.config/notify-daemon/state                         # View last processed timestamp
rm ~/.config/notify-daemon/state                          # Reset — daemon will process all new entries
```

---

*Last Updated: March 2, 2026*
