# ClamAV Module

> **Context purpose:**
> ClamAV antivirus module — submodule overview, naming conventions, log paths, and notification tags.
> Use this when adding or modifying clamav submodules, or understanding the module structure.

---

## Overview

The clamav module provides antivirus scanning via ClamAV: scheduled scans, real-time download monitoring, USB drive scanning, quarantine management, and a diagnostic/configuration tool.

All submodules depend on the **core** submodule which handles shared setup (packages, daemon config, SELinux, virus definitions, logrotate).

---

## Script Organization

```
modules/clamav/scripts/
  core/       → Internal hooks (not installed as user commands)
                configure-clamav.sh, update-definitions.sh,
                install.sh (packages), install-usb-clamscan.sh
  services/   → Systemd service scripts (installed to /usr/local/bin/)
                daily-clamscan.sh, weekly-clamscan.sh,
                download-clamscan.sh, usb-clamscan.sh
  tools/      → Interactive user-facing tools (installed to /usr/local/bin/)
                quarantine.sh, clamav-manage.sh
```

---

## Naming Conventions

| Pattern | Role | Scripts |
|---------|------|---------|
| `*-clamscan` | Scan services (systemd oneshot/timer/daemon) | `daily-clamscan`, `weekly-clamscan`, `download-clamscan`, `usb-clamscan` |
| `clamav-*` | Admin/management tools | `clamav-manage` |
| `*-clamav` / `*-definitions` | Internal hooks (not installed as commands) | `configure-clamav`, `update-definitions` |

Notification tags follow the `notify-` prefix convention:

| Tag | Scripts |
|-----|---------|
| `notify-daily-scan` | daily-clamscan |
| `notify-weekly-scan` | weekly-clamscan |
| `notify-download-scan` | download-clamscan |
| `notify-usb-scan` | usb-clamscan |

---

## Submodules

| Submodule | Description | Binary | Service |
|-----------|-------------|--------|---------|
| **core** | Shared setup (packages, config, SELinux, definitions) | `clamav-manage` | — |
| **daily-clamscan** | Quick daily scan (Downloads, /tmp) | `daily-clamscan` | timer |
| **weekly-clamscan** | Full weekly system scan | `weekly-clamscan` | timer |
| **download-clamscan** | Real-time download scanning (inotifywait) | `download-clamscan` | service |
| **quarantine** | Manage quarantined files | `quarantine` | — |
| **usb-clamscan** | Automatic ClamAV scan on USB insertion | `usb-clamscan` | udev-triggered |

All submodules declare `deps: [core]` — the submodule engine auto-installs core first.

---

## Log Paths

All clamav scripts log to the shared `/var/log/clamav/` directory:

| Script | Log file |
|--------|----------|
| daily-clamscan | `/var/log/clamav/daily-clamscan.log` |
| weekly-clamscan | `/var/log/clamav/weekly-clamscan.log` |
| download-clamscan | `/var/log/clamav/download-clamscan.log` |
| usb-clamscan | `/var/log/clamav/usb-clamscan.log` |

Rotation is handled by a single logrotate config (`logrotate/clamav-scripts`) matching `/var/log/clamav/*.log`.

---

## Configuration

| File | Format | Purpose |
|------|--------|---------|
| `/etc/system-scripts/clamav.conf` | Shell vars | Scan profile (standard/paranoid/minimal), detection settings |
| `/etc/clamd.d/scan.conf` | ClamAV native | Daemon configuration (socket, threads, limits) |
| `/etc/system-scripts/paths.conf` | Shell vars | Download directories (used by daily-clamscan, download-clamscan) |

Profile management: `sudo clamav-manage configure`

---

*Last Updated: March 1, 2026*
