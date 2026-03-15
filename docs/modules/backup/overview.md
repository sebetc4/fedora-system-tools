# Backup Module

Comprehensive backup solution with 5 independent submodules: system rsync,
HDD mirrors, VPS off-site pull, and Bitwarden vault exports.

## Architecture

```
modules/backup/
├── module.yml                          Module metadata (6 submodules)
├── install.sh                          Orchestrator (submodule multi-select)
├── uninstall.sh                        Orchestrator (deps-aware ordering)
├── logrotate/
│   └── backup-scripts                  System-level log rotation
├── system/                             System backup (rsync + hooks)
│   ├── backup.sh                       → /usr/local/bin/backup-system
│   ├── config.yml                      → ~/.config/backup/system.yml
│   ├── hooks.d/pre-backup/             Hook scripts
│   └── hooks-config/                   Hook configs
├── hdd-to-hdd/                         Simple HDD mirror
│   ├── backup.sh                       → /usr/local/bin/backup-hdd
│   └── config.yml                      → ~/.config/backup/hdd.yml
├── hdd-to-both-hdd/                    Split backup across 2 drives
│   ├── backup.sh                       → /usr/local/bin/backup-hdd-both
│   └── config.yml                      → ~/.config/backup/hdd-both.yml
├── bitwarden/                          Bitwarden vault export
│   ├── backup-bitwarden.sh             → /usr/local/bin/backup-bitwarden
│   └── config.yml                      → ~/.config/backup/bitwarden.yml
└── vps/                                VPS off-site backup (user-level)
    ├── backup-vps.sh                   → ~/.local/bin/backup-vps
    ├── config.yml                      → ~/.config/backup/vps.yml
    ├── services/backup-vps.service     User systemd service
    ├── timers/backup-vps.timer         Daily at 16:00
    ├── hooks/                          Install/cleanup hooks
    └── logrotate/user-logs.tpl         Per-user logrotate template
```

## Submodules

| Submodule | Binary | Type | Purpose | Deps |
|-----------|--------|------|---------|------|
| **core** | — | system | Shared log dir + logrotate | — |
| **system** | `backup-system` | system | Rsync backup with hook system | core, yq, rsync |
| **hdd** | `backup-hdd` | system | Simple 1:1 HDD mirror | core, yq, rsync |
| **hdd-both** | `backup-hdd-both` | system | Split backup across 2 drives | core, yq, rsync |
| **bitwarden** | `backup-bitwarden` | system | Vault export with age encryption | core, age, jq, bw |
| **vps** | `backup-vps` | **user** | VPS pull via SSH + GFS rotation | core, yq, rsync |

All submodules depend on **core** (auto-installed via `deps: [core]`).

The **vps** submodule overrides the module type with `type: user` — it installs
to `~/.local/bin`, uses user systemd units, and registers in the user registry.

---

## System backup — `backup-system`

Full rsync backup with YAML config and pluggable hook system.

```bash
sudo backup-system [OPTIONS]
  -c, --config <file>    Config file (default: ~/.config/backup/system.yml)
  -n, --dry-run          Simulate backup
  -y, --yes              Skip hook confirmations
  --scrub                BTRFS scrub after backup
  --stats                BTRFS compression stats
  -h, --help             Show help
```

### Configuration — `system.yml`

```yaml
backup:
  hdd_mount: /media/hdd1
  backup_root: /media/hdd1/backups

paths:
  - name: system
    source: /
    dest_subdir: root
    enabled: true
    btrfs_snapshot: true            # Snapshot source before rsync
    exclusions: [proc, sys, dev, run, tmp, ...]

  - name: home
    source: /home
    dest_subdir: home
    enabled: true
    exclusions: [.cache, .local/share/Trash, ...]

hooks:
  pre_backup:
    - name: btrfs-save-structure
      script: /usr/local/lib/system-scripts/hooks.d/pre-backup/btrfs-save-structure.sh
      enabled: true
      confirm: true

    - name: btrfs-snapshot
      script: /usr/local/lib/system-scripts/hooks.d/pre-backup/btrfs-snapshot.sh
      enabled: true
      confirm: true

  post_backup:
    - name: bitwarden
      script: /usr/local/bin/backup-bitwarden
      enabled: false
      confirm: true
      run_as_user: true             # Drop sudo for this hook

logging:
  file: /var/log/backup/backup-system.log

advanced:
  rsync_options: "-aAXHv --info=progress2 --no-xattrs --partial --timeout=300"
```

### Hook system

Hooks are standalone scripts that run before (`pre_backup`) or after
(`post_backup`) the rsync operation:

- Each hook can be tested independently
- `confirm: true` prompts before execution (skipped with `-y`)
- `run_as_user: true` drops root privileges for the hook
- Hook failure logs a warning but does not stop the backup
- Environment variables `BACKUP_ROOT` and `DRY_RUN` are passed to hooks

**Included hooks:**

| Hook | Phase | Purpose |
|------|-------|---------|
| `btrfs-save-structure` | pre | Document BTRFS layout for disaster recovery |
| `btrfs-snapshot` | pre | Create read-only snapshot of backup state |
| `backup-bitwarden` | post | Export Bitwarden vault (optional) |

### Lock file

`/run/lock/backup-system.lock` prevents concurrent runs.

---

## HDD backup — `backup-hdd`

Simple 1:1 mirror between two drives.

```bash
sudo backup-hdd [OPTIONS]
  -c, --config <file>    Config (default: ~/.config/backup/hdd.yml)
  -n, --dry-run          Simulate
  -y, --yes              Skip confirmation
  --snapshot             Force BTRFS snapshots
  --no-snapshot          Disable snapshots
  --scrub                BTRFS integrity check
  --stats                Compression stats
  -h, --help             Show help
```

### Configuration — `hdd.yml`

```yaml
source:
  path: /mnt/storage
  label: "Storage (4TB)"

backup:
  path: /mnt/backup
  label: "Backup (4TB)"

directories:
  - /                               # Entire drive or specific folders

exclude:
  - ".Trash-*"
  - "lost+found"

snapshots:
  enabled: false
  directory: ".snapshots"
  retention: 3

rsync:
  delete: true                       # Mirror mode
  progress: true
  archive: true

safety:
  confirm_before_start: true
  check_disk_space: true
```

---

## Split HDD backup — `backup-hdd-both`

Backup a source drive across two destination drives with per-drive folder
selection.

```bash
sudo backup-hdd-both [OPTIONS]
  -c, --config <file>    Config (default: ~/.config/backup/hdd-both.yml)
  -d, --drive <num>      Target: 1, 2, or both (default: both)
  -n, --dry-run          Simulate
  -y, --yes              Skip confirmation
  --snapshot             Force snapshots
  --no-snapshot          Disable snapshots
  --scrub                Integrity check
  --stats                Compression stats
  -h, --help             Show help
```

### Configuration — `hdd-both.yml`

```yaml
source:
  path: /mnt/storage

backup_drive_1:
  path: /mnt/backup1
  label: Backup1
  folders:
    - path: Documents
      subfolders: [Personal, Work]
    - path: Photos
      subfolders: [2024]

backup_drive_2:
  path: /mnt/backup2
  label: Backup2
  folders:
    - path: Music
    - path: Videos

exclude:
  - "*.tmp"
  - ".Trash-*"

snapshots:                           # Per-drive snapshot config
  enabled: false
  retention: 3
```

---

## Bitwarden backup — `backup-bitwarden`

Bitwarden vault export with age encryption and automatic rotation.
See [bitwarden.md](bitwarden.md) for full documentation.

```bash
backup-bitwarden [OPTIONS]
  -c, --config <file>    Config (default: ~/.config/backup/bitwarden.yml)
  -n, --dry-run          Simulate
  -h, --help             Show help
```

### Configuration — `bitwarden.yml`

```yaml
bitwarden:
  api_key_path: /media/hdd1/secrets/bw-api-key.age
  backup_path: /media/hdd1/backups/bitwarden
  retention: 3
  export_mode: both                  # both | age_json | encrypted_json
```

### How it works

1. Decrypt API key from age-encrypted file (interactive passphrase)
2. Prompt for master password
3. Login via Bitwarden API key
4. Unlock vault and export:
   - JSON export → encrypted with `age` (master password or interactive passphrase)
   - Bitwarden encrypted JSON (native re-importable format, up to 3 retries)
5. Rotate old exports (keep N per `retention`)
6. Cleanup: shred all temporary files (trap handler)

Can also run as a **post-backup hook** for `backup-system` with
`run_as_user: true`. No confirmation prompt — handled by the caller.

### Initial setup

```bash
# Get API key from Bitwarden web vault: Settings > Security > Keys > API Key
# Encrypt it with age
age -p -o /path/to/bw-api-key.age bw-api-key.json
shred -u bw-api-key.json
```

---

## VPS backup — `backup-vps`

Off-site VPS backup via SSH pull with GFS (Grandfather-Father-Son) rotation.

**User-level submodule** — installs to `~/.local/bin`, runs as invoking user
without sudo.

```bash
backup-vps [OPTIONS]
  -c, --config <file>    Config (default: ~/.config/backup/vps.yml)
  -n, --dry-run          Simulate
  -h, --help             Show help
```

### Configuration — `vps.yml`

```yaml
connection:
  ssh_host: "main-vps"
  remote_backup_dir: "/root/backups"

storage:
  local_backup_dir: "~/.backups/vps"

retention:
  keep_daily: 7
  keep_weekly: 4
  keep_monthly: 6

logging:
  file: "~/.local/log/backup-vps/backup-vps.log"

notifications:
  enabled: true
  on_success: true
  on_error: true

advanced:
  rsync_options: "-avz --partial --timeout=300"
```

### GFS rotation

Keeps 7 daily, 4 weekly, and 6 monthly snapshots. Old backups are automatically
pruned after each successful run.

### Systemd timer

Runs daily at 16:00 with 15-minute randomized delay. Uses `gcr-ssh-agent` for
SSH key access. Resource limits: 500MB memory, 50% CPU, 15-minute timeout.

### Logrotate

Per-user logrotate config generated from template at install time:
`/etc/logrotate.d/{username}-backup-vps`.

---

## Log paths

| Submodule | Log file |
|-----------|----------|
| system | `/var/log/backup/backup-system.log` |
| hdd | `/var/log/backup/backup-hdd.log` |
| hdd-both | `/var/log/backup/backup-hdd-both.log` |
| bitwarden | (uses backup-system log when called as hook) |
| vps | `~/.local/log/backup-vps/backup-vps.log` |

System logs rotated by `/etc/logrotate.d/backup-scripts` (core submodule).

## Notifications

All scripts use `logger -t notify-<tag>` for desktop notifications:

| Tag | Submodule |
|-----|-----------|
| `notify-backup-system` | system |
| `notify-backup-hdd` | hdd |
| `notify-backup-hdd-both` | hdd-both |
| `notify-backup-vps` | vps |

## Install / Uninstall

### Install

Interactive multi-select or `--all` / `--only <names>`:

```bash
sudo ./modules/backup/install.sh
sudo ./modules/backup/install.sh --all
sudo ./modules/backup/install.sh --only system,vps
```

Config files are installed with no-overwrite (preserves existing user configs).

### Uninstall

Removes binaries, services, logrotate configs. **Preserves:**
- User configs in `~/.config/backup/`
- Hook configs in `~/.config/backup/hooks/`
- Downloaded data and backups

---

*Last Updated: March 9, 2026*
