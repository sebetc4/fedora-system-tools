# Local Backup with Hook System

Modular backup solution for Linux systems. Pure rsync backup driven by YAML config,
with a pluggable hook system for BTRFS operations, Bitwarden export, or any custom task.

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Hooks](#hooks)
- [Usage](#usage)
- [Creating Custom Hooks](#creating-custom-hooks)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Dynamic paths** — backup any number of directories, each with its own exclusions
- **Hook system** — pre/post-backup hooks, each autonomous with its own config
- **Atomic consistency** — optional BTRFS read-only snapshot before rsync
- **Versioned snapshots** — pre-backup snapshots preserve last known-good state
- **Lock file** — prevents concurrent backups
- **Dry-run mode** — test everything without writing
- **Desktop notifications** — on success/failure
- **Log rotation** — via logrotate
- **`--yes` flag** — skip all confirmations for automation

---

## Architecture

```
backup-local (main script)
│
├── Config: dynamic paths[] + hooks declaration
│
├── [PRE-BACKUP HOOKS]
│   └── btrfs-save-structure.sh   → documents BTRFS layout
│
├── RSYNC / ARCHIVE BACKUP (loop over enabled paths[])
│   └── Destination timeline (built-in snapshots: section)
│
├── [POST-BACKUP HOOKS]
│   └── backup-bitwarden          → Bitwarden vault export
│
└── Final report
```

### Destination timeline (versioned history)

Built into `backup-local` via the `snapshots:` config section — no hook
required. Dispatches by destination filesystem:

- **BTRFS** → native read-only subvolume snapshots under `<backup_root>/.snapshots/`
- **ext4 / xfs / other** → dated directories (`backup-dir` or `link-dest` mode)

Retention is enforced automatically.

### Separation of Concerns

| Component | Responsibility |
|-----------|---------------|
| `backup-local` | rsync/archive backup, timeline, hook orchestration |
| `btrfs-save-structure.sh` | BTRFS subvolume documentation (pre-backup) |
| `backup-bitwarden` | Bitwarden vault export (post-backup, standalone) |

### Hook Autonomy

Each hook is a **fully autonomous script**:
- Hardcodes its own `DEFAULT_CONFIG` path internally
- Can be tested standalone: `sudo btrfs-save-structure.sh --dry-run`
- Receives only `--dry-run` and `-y` flags from the orchestrator
- Reads environment variables: `BACKUP_ROOT`, `BACKUP_MOUNT`, `DRY_RUN`, `LOG_FILE`

---

## Installation

```bash
# Via Makefile
make install-backup

# Or directly
sudo ./modules/backup/local/install.sh
```

This installs:
- `backup-local` → `/usr/local/bin/`
- Hook scripts → `/usr/local/lib/system-scripts/hooks.d/pre-backup/`
- Example configs → `~/.config/backup/` and `~/.config/backup/hooks/`

---

## Configuration

### Main config: `~/.config/backup/local.yml`

```yaml
backup:
  hdd_mount: /media/hdd1
  backup_root: /media/hdd1/backup-local

paths:
  - name: system
    source: /
    dest_subdir: root
    enabled: true
    btrfs_snapshot: true      # temp snapshot for rsync consistency
    exclusions:
      - /dev/*
      - /proc/*
      - /sys/*
      - /tmp/*
      - /run/*
      - /mnt/*
      - /media/*

  - name: home
    source: /home
    dest_subdir: home
    enabled: true
    exclusions:
      - .cache
      - .local/share/Trash
      - Downloads

  - name: code
    source: /code
    dest_subdir: code
    enabled: true
    exclusions:
      - node_modules
      - target
      - __pycache__

  - name: vm
    source: /vm
    dest_subdir: vm
    enabled: false            # disabled = skipped

# Hook declarations — each hook manages its own config internally
hooks:
  pre_backup:
    - name: btrfs-save-structure
      script: /usr/local/lib/system-scripts/hooks.d/pre-backup/btrfs-save-structure.sh
      enabled: true
      confirm: true

  post_backup:
    - name: bitwarden
      script: /usr/local/bin/backup-bitwarden
      enabled: false
      confirm: true

logging:
  file: /var/log/backup/backup-local.log

notifications:
  enabled: true

advanced:
  rsync_options: "-aAXHv --info=progress2 --no-xattrs --partial --timeout=300"
```

### Path entry fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Display name for logging |
| `source` | yes | Absolute path to backup |
| `dest_subdir` | yes | Subdirectory under `backup_root` |
| `enabled` | yes | `true`/`false` — toggle without editing exclusions |
| `exclusions` | no | List of rsync `--exclude` patterns |
| `btrfs_snapshot` | no | Create temp read-only snapshot for rsync consistency |

### Hook entry fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Display name |
| `script` | yes | Absolute path to hook executable |
| `enabled` | yes | `true`/`false` |
| `confirm` | no | Prompt `ui_confirm` before running (skipped with `--yes`) |

---

## Hooks

### Pre-backup: btrfs-save-structure

Saves BTRFS filesystem documentation for disaster recovery:
- Subvolume list and fstab backup
- File attributes (chattr)
- Additional disk documentation
- `recreate-subvolumes.sh` generation script
- System info snapshot

**Config**: `~/.config/backup/hooks/btrfs-save-structure.yml`

```yaml
output_dir: btrfs-structure
attribute_paths: [/, /home, /code]
subvolumes:
  - name: root
  - name: home
  - name: code
  - name: vm
    chattr: "+C"
additional_disks:
  - mount_point: /data
    description: "Data disk"
```

### Destination snapshots (built-in, not a hook)

Versioned history of the backup destination is built into `backup-local`
via the top-level `snapshots:` config section. See main config example above.

Dispatches by destination filesystem:

- **BTRFS** → native read-only subvolume snapshots under
  `<backup_root>/<directory>/` (requires `backup_root` to be a subvolume).
- **Non-BTRFS** → dated directories in `backup-dir` (default, SMR-friendly)
  or `link-dest` (hardlinked point-in-time view) mode.

Retention is enforced automatically. No pre-backup hook is required.

### Post-backup: bitwarden

Standalone Bitwarden vault export, callable as hook or independently.

**Config**: `~/.config/backup/bitwarden.yml`

```yaml
bitwarden:
  api_key_path: /media/hdd1/secrets/bw-api-key.age
  backup_path: /media/hdd1/backups/bitwarden
  retention: 3
```

> See [Bitwarden Vault Backup](bitwarden.md) for setup and standalone usage.

---

## Usage

```bash
# Standard backup (interactive confirmation for hooks)
sudo backup-local

# Dry run
sudo backup-local --dry-run

# Skip all confirmations
sudo backup-local --yes

# Custom config
sudo backup-local -c /path/to/config.yml

# With BTRFS scrub check
sudo backup-local --scrub

# With compression stats
sudo backup-local --stats
```

### Options

| Flag | Short | Description |
|------|-------|-------------|
| `--config <file>` | `-c` | Config file (default: `~/.config/backup/local.yml`) |
| `--dry-run` | `-n` | Simulate without writing |
| `--yes` | `-y` | Skip all confirmation prompts |
| `--scrub` | | Run BTRFS scrub after backup |
| `--stats` | | Show BTRFS compression stats |
| `--help` | `-h` | Show help |

---

## Creating Custom Hooks

A template is available at `templates/hook.sh`.

### 1. Create the hook script

```bash
#!/bin/bash
set -euo pipefail
trap 'echo "ERROR: my-hook failed at line $LINENO" >&2; exit 1' ERR

readonly LIB_DIR="/usr/local/lib/system-scripts"
source "$LIB_DIR/core.sh"
source "$LIB_DIR/log.sh"
source "$LIB_DIR/yaml.sh"
source "$LIB_DIR/validate.sh"

# Detect real user for config path
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
readonly DEFAULT_CONFIG="$REAL_HOME/.config/backup/hooks/my-hook.yml"

# Inherit environment from backup-local
BACKUP_ROOT="${BACKUP_ROOT:-}"
DRY_RUN="${DRY_RUN:-false}"

# Parse arguments: --dry-run, -y, -c <config>
# Load config: YAML_FILE="$config_file"
# Validate config: validation_reset + validate_* + validation_check
# Run hook logic

# IMPORTANT: use : "${VAR:=default}" for defaults (NOT [[ -z ]] && ...)
# The [[ -z ]] && pattern silently kills the script under set -e
# when it's the last statement in a function.
```

### 2. Create the hook config

```yaml
# ~/.config/backup/hooks/my-hook.yml
my_setting: value
my_path: /some/path
```

### 3. Declare it in the main config

```yaml
hooks:
  pre_backup:   # or post_backup
    - name: my-hook
      script: /path/to/my-hook.sh
      enabled: true
      confirm: false
```

### Hook interface

| Input | Type | Description |
|-------|------|-------------|
| `--dry-run` | Argument | Simulation mode |
| `-y` | Argument | Skip internal confirmations |
| `-c <file>` | Argument | Override config path (optional) |
| `BACKUP_ROOT` | Env var | Backup destination root |
| `BACKUP_MOUNT` | Env var | HDD mount point |
| `DRY_RUN` | Env var | `true`/`false` |
| `LOG_FILE` | Env var | Shared log file path |

### Hook contract

- Each hook hardcodes its own `DEFAULT_CONFIG` path
- Accept `-c <path>` to override config (for testing)
- Accept `--dry-run` and `-y` flags
- Exit 0 on success, non-zero on failure
- A failing hook logs a warning but does **not** abort the backup
- Use `set -euo pipefail` + ERR trap (project convention)
- Use `: "${VAR:=default}"` for defaults, **never** `[[ -z ]] && ...` as last function statement

---

## Files

```
backup-local/
├── backup.sh                          # Main backup script
├── config.yml                         # Example configuration
├── hooks.d/
│   └── pre-backup/
│       └── btrfs-save-structure.sh    # BTRFS structure documentation
├── hooks-config/
│   └── btrfs-save-structure.yml       # Example hook config
└── README.md                          # This file

bitwarden/
├── backup-bitwarden.sh                # Standalone Bitwarden script
└── config.yml                         # Example config

templates/
└── hook.sh                            # Hook template
```

**Installed locations**:
- Script: `/usr/local/bin/backup-local`
- Hooks: `/usr/local/lib/system-scripts/hooks.d/pre-backup/`
- User config: `~/.config/backup/local.yml`
- Hook configs: `~/.config/backup/hooks/`
- Bitwarden config: `~/.config/backup/bitwarden.yml`

---

## Troubleshooting

### "A backup is already running"

```bash
ps aux | grep backup-local
# If not running, remove stale lock:
sudo rm /run/lock/backup-local.lock
```

### Hook fails silently

Check that the ERR trap is present (project convention):
```bash
head -30 /usr/local/lib/system-scripts/hooks.d/pre-backup/my-hook.sh
# Must contain: trap 'echo "ERROR: ... failed at line $LINENO" >&2; exit 1' ERR
```

**Common cause**: `[[ -z "$VAR" ]] && VAR="default"` as the last statement
in a function. Under `set -e`, when `$VAR` is not empty, the `&&` list returns 1
and kills the script silently. Use `: "${VAR:=default}"` instead.

### Hook fails to execute

Check that the hook script is executable:
```bash
ls -la /usr/local/lib/system-scripts/hooks.d/pre-backup/
```

Check that the hook config exists:
```bash
ls -la ~/.config/backup/hooks/
```

### BTRFS snapshot: "not a subvolume"

The backup destination must be a BTRFS subvolume for snapshots:
```bash
# Check current state
btrfs subvolume show /media/hdd1/backup-local

# Convert existing directory to subvolume
sudo mv /media/hdd1/backup-local /media/hdd1/backup-local-old
sudo btrfs subvolume create /media/hdd1/backup-local
sudo rsync -aAXHv /media/hdd1/backup-local-old/ /media/hdd1/backup-local/
sudo rm -rf /media/hdd1/backup-local-old
```

### Dry run to test

Always test with `--dry-run` after config changes:
```bash
sudo backup-local --dry-run --yes
```
