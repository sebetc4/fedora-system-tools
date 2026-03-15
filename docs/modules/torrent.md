# Torrent Module

VPN + qBittorrent container stack for secure torrent downloading via Podman.

## Architecture

```
modules/torrent/
├── module.yml                          Module metadata
├── install.sh                          Installer (deps + binaries + container setup)
├── uninstall.sh                        Uninstaller (binaries only — containers preserved)
└── scripts/
    ├── torrent.sh                      Main CLI (/usr/local/bin/torrent)
    ├── torrent-container.sh            Container setup & management
    ├── torrent-list.sh                 Download listing with scan status
    └── torrent-move.sh                 Move downloads with permission fixes
```

### Installed paths

| File | Path | Purpose |
|------|------|---------|
| Main CLI | `/usr/local/bin/torrent` | Container lifecycle, downloads, monitoring |
| Container manager | `/usr/local/bin/torrent-container` | Interactive container setup & config |
| Download lister | `/usr/local/bin/torrent-list` | List downloads with scan status |
| File mover | `/usr/local/bin/torrent-move` | Move files with permission/SELinux fixes |
| Container config | `~/.config/torrent/container.conf` | VPN provider, protocol, countries |
| Container data | `~/.config/podman/containers/` | Gluetun & qBittorrent persistent config |

## Container stack

Two Podman containers work together:

```
┌─────────────────────────────────────────────────┐
│ gluetun                                         │
│  VPN tunnel (OpenVPN / WireGuard)               │
│  Ports: 18001 (API), 18002 (qBit UI), 6881 (BT)│
├─────────────────────────────────────────────────┤
│ qbittorrent  (--network container:gluetun)      │
│  All traffic routed through VPN tunnel          │
│  WebUI on port 18002                            │
└─────────────────────────────────────────────────┘
```

**Security**: qBittorrent shares the gluetun network namespace. All traffic is
forced through the VPN tunnel. On `torrent start`, the script verifies that
qBittorrent's external IP matches the VPN IP — if not, qBittorrent is stopped
immediately with a security alert.

### Supported VPN providers

| Provider | OpenVPN | WireGuard | Free tier |
|----------|---------|-----------|-----------|
| ProtonVPN | ✅ | ✅ | ✅ |
| Mullvad | ✅ | ✅ | — |
| NordVPN | ✅ | ✅ | — |
| Surfshark | ✅ | ✅ | — |

Credentials are stored as **Podman secrets** (not plaintext in config).

## CLI — `torrent`

Requires root for container operations.

```
torrent                         Interactive menu
torrent start                   Start VPN + qBittorrent (with IP verification)
torrent stop                    Stop both containers
torrent restart                 Reconnect to different VPN server
torrent status                  Show container state + VPN IP/location
torrent ip                      Quick VPN IP lookup
torrent logs [name]             Tail container logs (gluetun or qbittorrent)
torrent watch                   Monitor VPN, auto-restart on drop
torrent update                  Pull latest container images
torrent list [opts]             List downloads with scan status
torrent move <#> [dest]         Move file to export directory
torrent export                  Move all clean files
torrent help                    Show help
```

### Start flow (security)

1. Start gluetun → wait for VPN connection (60s timeout)
2. Extract VPN IP and location from gluetun API
3. Start qBittorrent (shares gluetun network)
4. **Verify qBittorrent routes through VPN** (progressive backoff, 15 retries)
5. If IP mismatch → stop qBittorrent → security alert → exit

### Download listing — `torrent list`

```
torrent list                    Pretty listing with scan status
torrent list --all              Include pending & quarantined files
torrent list --pending          Show only files pending review
torrent list --simple           Machine-readable output
```

Status icons (integrates with clamav/quarantine module if installed):

| Icon | Meaning |
|------|---------|
| ✅ | Scanned, clean |
| ⚠️ | Pending user review |
| 🔒 | Quarantined |
| ❓ | Not scanned |

### File transfer — `torrent move`

```
torrent move <file_or_number> [destination]
torrent move --all              Move all files
torrent move --clean            Move only clean files (skip pending)
torrent move -n                 Dry-run preview
```

Files are moved with permission fixes: `chown` to real user, `chmod 644`/`755`,
and `restorecon -R` to fix SELinux container labels.

## Container management — `torrent-container`

```
torrent-container install       Interactive setup (provider, protocol, credentials)
torrent-container info          Show current configuration
torrent-container edit          Modify configuration interactively
torrent-container update        Pull latest images, offer to recreate
torrent-container delete        Remove containers + secrets (preserves downloads)
```

### Container config — `container.conf`

```bash
PROVIDER=protonvpn
VPN_TYPE=openvpn
COUNTRIES="Netherlands,Sweden"
FREE_ONLY=off                   # ProtonVPN only
TZ=Europe/Amsterdam
PUID=1000
PGID=1000
GLUETUN_API_KEY=<random-32-char>
```

Stored at `~/.config/torrent/container.conf` (mode 600).

## Install / Uninstall

### Install

1. Installs system dependencies (`podman`, `curl`, `gum`)
2. Creates `$DOWNLOAD_DIR/torrents` directory
3. Installs 4 binaries to `/usr/local/bin/`
4. Registers in module registry
5. Launches interactive container setup (`torrent-container install`)

### Uninstall

Removes binaries and registry entry. **Does not remove:**
- Podman containers (gluetun, qbittorrent)
- Podman secrets (VPN credentials)
- Downloaded files
- Container config (`~/.config/torrent/container.conf`)

Manual cleanup instructions are displayed after uninstall.

## Debug mode

```bash
TORRENT_DEBUG=1 torrent <command>
```

## Dependencies

- `podman` — Container runtime
- `curl` — VPN info queries
- `skopeo` — Image update detection (optional)
- `gum` — Interactive UI (optional, bash fallback)

---

*Last Updated: March 9, 2026*
