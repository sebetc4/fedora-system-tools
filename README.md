# Fedora System Tools

Modular Bash toolkit for Fedora workstation security, backup, and system management.

Pick what you need — antivirus scanning, automated backups, firewall hardening, torrent
isolation, desktop notifications — and install only that. Each module is independent,
versioned separately, and can be added or removed at any time.

## Installation

### One-liner (recommended)

```bash
curl -sSL https://raw.githubusercontent.com/sebetc4/fedora-system-tools/main/install.sh | bash
```

This installs the toolkit to `/opt/fedora-system-tools/` and creates the `system-tools`
command. Then use the interactive menu to install modules:

```bash
system-tools                          # Interactive menu
system-tools --install clamav         # Install a module directly
system-tools --self-update            # Update to the latest release
```

### From source (development)

```bash
git clone git@github.com:sebetc4/fedora-system-tools.git
cd fedora-system-tools
sudo make install          # Install lib + all modules
# or
./setup.sh                 # Interactive menu
```

### Requirements

- Fedora Linux (tested on Fedora 42+)
- Bash 4+, `curl`, `tar`, `sudo`
- [yq](https://github.com/mikefarah/yq) (installed automatically if missing)
- [Gum](https://github.com/charmbracelet/gum) (optional — enhances the interactive UI, auto-installed with lib)

## Modules

### ClamAV — Antivirus automation

Scheduled scans, real-time download monitoring, USB auto-scan, and quarantine management
— all built on ClamAV.

| Submodule | Description |
|-----------|-------------|
| `daily-clamscan` | Quick daily scan (Downloads, /tmp) |
| `weekly-clamscan` | Full weekly system scan |
| `download-clamscan` | Real-time download folder monitoring (inotifywait) |
| `usb-clamscan` | Automatic scan on USB insertion |
| `quarantine` | Manage quarantined files (list, restore, delete) |

### Backup — System & remote backups

Rsync-based backup scripts with hook system, BTRFS snapshot support, and GFS rotation.

| Submodule | Description |
|-----------|-------------|
| `system` | Full system backup with pre/post hooks |
| `hdd` | Simple HDD-to-HDD mirror |
| `hdd-both` | Split backup across two drives |
| `bitwarden` | Bitwarden vault export & backup |
| `vps` | Remote VPS backup with GFS rotation (user-level) |

### Torrent — Containerized torrent client

Podman-based qBittorrent + Gluetun VPN stack. Downloads are isolated in a rootless
container with automatic ClamAV scanning integration.

| Command | Description |
|---------|-------------|
| `torrent` | Main CLI — container lifecycle, downloads, security |
| `torrent-container` | Interactive container setup (VPN configuration) |
| `torrent-list` | List downloads with scan status |
| `torrent-move` | Move downloads to user folder (permissions + SELinux) |

### Firewall — Firewalld hardening

Interactive wizard for firewalld configuration: status overview, rule application,
backup & restore, dry-run mode.

### Nautilus — Bookmark manager

Manage Nautilus bookmarks and project symlinks — interactive and CLI modes.

### Notifications — Desktop notification daemon

Monitors journald for systemd service events and sends desktop notifications.
Other modules register their services automatically.

| Command | Description |
|---------|-------------|
| `notify-daemon` | Systemd user service — journald to desktop notifications |
| `notify-manage` | Manage monitored services (list, add, remove, test) |

## Usage

### Interactive

```bash
system-tools                              # Main menu
system-tools --list                       # Show installed modules & versions
system-tools --info clamav                # Module details
system-tools --info clamav/quarantine     # Submodule details
```

### Install / Upgrade / Uninstall

```bash
# Module-level
system-tools --install clamav             # All clamav submodules
system-tools --upgrade clamav             # Upgrade clamav
system-tools --uninstall clamav           # Remove clamav

# Submodule-level
system-tools --install clamav/quarantine  # Install one submodule
system-tools --upgrade clamav/quarantine  # Upgrade one submodule
system-tools --uninstall clamav/quarantine

# Bulk operations
system-tools --upgrade                    # Upgrade all installed items
system-tools --reinstall clamav           # Force reinstall
```

### Makefile targets

```bash
make install-clamav                # Install module (auto-installs lib)
make install-clamav-quarantine     # Install single submodule
make uninstall-clamav              # Remove module
make list                          # List installed items
make upgrade                       # Upgrade all
make shellcheck                    # Lint all scripts
```

## Architecture Overview

The project follows a **two-level model**: modules contain independent submodules
that can be installed, upgraded, and removed individually.

```
Module (clamav)
  ├── core               ← shared setup (packages, config, logrotate)
  ├── daily-clamscan      ← deps: [core]
  ├── weekly-clamscan     ← deps: [core]
  ├── download-clamscan   ← deps: [core]
  ├── quarantine          ← deps: [core]
  └── usb-clamscan        ← deps: [core]
```

Each module declares its metadata in a `module.yml` file — the single source of truth
for submodules, dependencies, versions, and systemd units. The shared library
(`lib/`) provides the submodule engine, registry, UI, logging, and YAML parsing.

**Standalone modules** (firewall, nautilus, notifications) skip the submodule engine
and install directly.

Detailed documentation: [`docs/`](docs/)

| Topic | Link |
|-------|------|
| Architecture & conventions | [docs/core/conventions.md](docs/core/conventions.md) |
| setup.sh reference | [docs/core/setup.md](docs/core/setup.md) |
| Shared library API | [docs/lib/overview.md](docs/lib/overview.md) |
| Versioning & releases | [docs/core/versioning.md](docs/core/versioning.md) |
| State & installed paths | [docs/core/state-and-paths.md](docs/core/state-and-paths.md) |
| Module docs | [docs/modules/](docs/modules/) |

## CI/CD

- **Lint**: ShellCheck on every push/PR to `main`
- **Release**: Git tags trigger GitHub Releases with tarballs
  - `v*` — project release (full toolkit)
  - `<module>-v*` — per-module release (changelog only)

## License

MIT
