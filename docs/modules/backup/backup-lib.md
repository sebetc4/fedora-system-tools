# backup-lib.sh — Backup module shared library

> BTRFS operations, rsync helpers, FS-agnostic destination timeline, and tar.zst archives.

**Guard:** `_BACKUP_LIB_LOADED`
**Install path:** `/usr/local/lib/backup-scripts/backup-lib.sh` (installed by the `backup/core` submodule via `shared/setup-backup.sh`)
**Dependencies:** `core.sh`, `log.sh`, `fs.sh` (from `/usr/local/lib/system-scripts/`)
**Sourced by:** backup-local, backup-hdd, backup-hdd-both

Scripts source it with:

```bash
readonly LIB_DIR="/usr/local/lib/system-scripts"
readonly BACKUP_LIB_DIR="/usr/local/lib/backup-scripts"
source "$LIB_DIR/fs.sh"
source "$BACKUP_LIB_DIR/backup-lib.sh"
```

---

## BTRFS operations

All BTRFS functions respect `DRY_RUN=true` (prints what would happen).

### `btrfs_create_snapshot source snap_dir prefix`

Create a read-only BTRFS snapshot. No-op (warning) on non-BTRFS filesystems.

```bash
btrfs_create_snapshot "/mnt/hdd1" ".snapshots" "backup"
# Creates: /mnt/hdd1/.snapshots/backup-20260211-143022
```

### `btrfs_rotate_snapshots snap_dir prefix keep`

Delete old snapshots beyond the retention count.

```bash
btrfs_rotate_snapshots "/mnt/hdd1/.snapshots" "backup" 3
```

### `btrfs_run_scrub path label`

Run BTRFS integrity check (scrub). Blocking.

### `btrfs_show_stats path label`

Show compression stats via `compsize` (or `btrfs filesystem df` as fallback).

---

## Rsync helpers

### `rsync_safe args...`

Rsync wrapper treating exit codes 23 (partial) and 24 (vanished files) as non-fatal.

### `build_rsync_options`

Builds a space-separated options string from globals:

| Variable         | Default | Flag               |
|------------------|---------|--------------------|
| `RSYNC_ARCHIVE`  | `true`  | `-a`               |
| `RSYNC_DELETE`   | `true`  | `--delete`         |
| `RSYNC_PROGRESS` | `true`  | `--info=progress2` |
| `RSYNC_COMPRESS` | `false` | `-z`               |
| `RSYNC_PARTIAL`  | `false` | `--partial`        |
| `RSYNC_INPLACE`  | `false` | `--inplace`        |
| `DRY_RUN`        | `false` | `--dry-run`        |

Always appends `-v -h`.

### `build_exclude_args excludes`

Build `--exclude=…` arguments from a newline-separated pattern list.

---

## FS-agnostic destination timeline

Provides versioned history of the backup destination across all filesystems.
Dispatches automatically:

- **BTRFS** → native read-only subvolume snapshots (`btrfs_create_snapshot` +
  `btrfs_rotate_snapshots`)
- **Non-BTRFS** (ext4/xfs/…) → dated directories, two modes:
  - `backup-dir` (default): `rsync --backup --backup-dir=<dated>` — only
    changed/deleted files land in each timeline entry (SMR-friendly)
  - `link-dest`: post-sync hardlinked point-in-time copy of the destination

### `timeline_begin dest snap_dir prefix [mode]`

Populates the global `TIMELINE_RSYNC_ARGS` array with rsync args to inject.
Safe for paths containing spaces. On BTRFS, leaves the array empty.

### `timeline_end dest snap_dir prefix keep [mode]`

Finalizes the timeline entry and rotates old entries beyond retention.

### Usage flow

```bash
timeline_begin "$DEST" "$SNAP_DIR" "$PREFIX" "$MODE"
rsync "${rsync_opts[@]}" "${TIMELINE_RSYNC_ARGS[@]}" "$src/" "$DEST/"
timeline_end "$DEST" "$SNAP_DIR" "$PREFIX" "$KEEP" "$MODE"
```

### `dated_name prefix`

Produces `<prefix>-YYYYMMDD-HHMMSS`.

### `rotate_dated_dirs parent prefix keep`

Remove dated directories matching `<prefix>-*` beyond the retention count.

---

## Archive (tar + zstd)

SMR-friendly sequential write strategy for system paths with dispersed small
files. Uses `zstd -T0` multi-threaded with ACL + xattr preservation. Each
archive has a SHA-256 companion for integrity verification.

### `archive_create source dest_dir name_prefix [zstd_level] [excludes...]`

Creates `<dest_dir>/<name_prefix>-YYYY-MM-DD.tar.zst` (+ `.sha256`).

```bash
local excludes=("/proc/*" "/sys/*")
archive_create /etc /mnt/backup/archive etc 10 "${excludes[@]}"
```

### `archive_rotate dir prefix keep`

Keep the `keep` most recent archives; delete older ones (and their `.sha256`).
