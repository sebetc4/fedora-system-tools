# Firewall Module

Config-driven firewall hardening for Fedora workstations using firewalld.

## Architecture

```
modules/firewall/
├── module.yml                          Module metadata
├── install.sh                          Installer (config + binary + apply)
├── uninstall.sh                        Uninstaller (restore + cleanup)
├── scripts/
│   ├── configure-firewall.sh           Apply engine (reads config, idempotent)
│   └── firewall-harden.sh             Interactive CLI (/usr/local/bin/firewall-harden)
└── templates/
    └── firewall.conf.default           Default config template
```

### Installed paths

| File | Path | Purpose |
|------|------|---------|
| CLI binary | `/usr/local/bin/firewall-harden` | User-facing command |
| Config | `/etc/system-scripts/firewall.conf` | Source of truth for rules |
| State | `/etc/system-scripts/firewall.state` | Pre-hardening snapshot |

## Config file — `firewall.conf`

Shell-sourceable file at `/etc/system-scripts/firewall.conf`. Same pattern as
`paths.conf`. Env var override: `FIREWALL_CONF`.

```bash
# Zone — leave empty to keep current zone
FIREWALL_ZONE=""

# Services to REMOVE from the active zone
REMOVE_SERVICES=(ssh samba-client mdns)

# Services to explicitly ALLOW
ALLOW_SERVICES=(dhcpv6-client)

# Ports to OPEN (format: port/proto or range/proto)
ALLOW_PORTS=()

# Ports to CLOSE
CLOSE_PORTS=(1025-65535/tcp 1025-65535/udp)

# Log denied packets: all | unicast | broadcast | multicast | off
LOG_DENIED="off"
```

### Variables

| Variable | Type | Values | Default |
|----------|------|--------|---------|
| `FIREWALL_ZONE` | string | Zone name or empty | `""` (keep current) |
| `REMOVE_SERVICES` | array | firewalld service names | `(ssh samba-client mdns)` |
| `ALLOW_SERVICES` | array | firewalld service names | `(dhcpv6-client)` |
| `ALLOW_PORTS` | array | `port/proto` or `range/proto` | `()` |
| `CLOSE_PORTS` | array | `port/proto` or `range/proto` | `(1025-65535/tcp 1025-65535/udp)` |
| `LOG_DENIED` | string | all, unicast, broadcast, multicast, off | `"off"` |

## State file — `firewall.state`

Auto-generated snapshot of the firewall state **before** the first apply.
Shell-sourceable, same format. Created once, never overwritten.

```bash
STATE_ZONE="FedoraWorkstation"
STATE_SERVICES=(ssh dhcpv6-client samba-client mdns)
STATE_PORTS=(1025-65535/tcp 1025-65535/udp)
STATE_LOG_DENIED="off"
STATE_DATE="2026-02-27 10:30:00"
```

Used by `firewall-harden restore` and `uninstall.sh` to revert all changes.
Deleted after a successful restore.

## CLI — `firewall-harden`

Requires root. Refuses to run over SSH.

```
firewall-harden                     Interactive wizard
firewall-harden status              Show current firewall state
firewall-harden show-config         Show saved configuration
firewall-harden apply               Apply config to firewall
firewall-harden apply --dry-run     Preview changes without applying
firewall-harden restore             Restore pre-hardening state
firewall-harden -h, --help          Show help
```

### Interactive wizard (default)

1. Shows current zone, services, ports, log-denied
2. Zone selection (public, FedoraWorkstation, home, drop)
3. Per-service removal confirmation (from active services)
4. Custom ports to open (e.g. `1714-1764/tcp` for KDE Connect)
5. FedoraWorkstation port range closure (if applicable)
6. Denied packet logging toggle
7. Summary of all changes
8. Confirmation → write config + apply

### Apply engine — `configure-firewall.sh`

Reads `firewall.conf` and applies rules via `firewall-cmd --permanent`. All
operations are idempotent (query before each action). Supports `--dry-run`.

Flow:
1. Source config
2. Pre-flight (firewalld running, no SSH)
3. Snapshot state (first run only)
4. Apply zone change
5. Remove services → Add services
6. Close ports → Open ports
7. Set log-denied
8. Reload firewall

## Install / Uninstall

### Install

1. Installs `/usr/local/bin/firewall-harden`
2. Copies `firewall.conf.default` → `/etc/system-scripts/firewall.conf` (only if absent)
3. Runs `configure-firewall.sh` (snapshots state, applies config)
4. Registers in module registry

### Uninstall

1. Restores firewall state from `firewall.state` (if exists)
2. Removes `/usr/local/bin/firewall-harden`
3. Preserves `firewall.conf` (user is notified)
4. Removes `firewall.state`
5. Unregisters from module registry

## Safety

- **SSH protection**: Both `configure-firewall.sh` and `firewall-harden` refuse
  to run when `SSH_CONNECTION` is set
- **Idempotent**: Every action queries current state before modifying
- **Dry-run**: `--dry-run` flag shows all planned changes without applying
- **Restore**: Full undo via state file snapshot
- **Config preserved**: Uninstall keeps `firewall.conf` for potential reinstall

## Firewalld reference

Common zones (most to least restrictive): `drop` → `block` → `public` →
`FedoraWorkstation` → `home` → `trusted`.

FedoraWorkstation opens ports 1025-65535 by default — the main reason for
hardening.

Common desktop ports:
- KDE Connect: `1714-1764/tcp` + `1714-1764/udp`
- Syncthing: `22000/tcp` + `21027/udp`
- Chromecast/DLNA: `1900/udp` (SSDP) + mDNS service
- Network printing: `631/tcp` (IPP) + mDNS service
