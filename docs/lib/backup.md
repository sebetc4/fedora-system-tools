# backup.sh — Backup Utilities

> BTRFS operations, rsync helpers, filesystem checks, and sudo-aware user detection.

**Guard:** `_LIB_BACKUP_LOADED`
**Dependencies:** `core.sh`, `log.sh`
**Sourced by:** backup module scripts (system, hdd-to-hdd, hdd-to-both-hdd, bitwarden)

---

## Functions

### `detect_real_user`

Sets `REAL_USER` and `REAL_HOME`, resolving through `SUDO_USER` if present.

```bash
detect_real_user
echo "$REAL_USER"   # seb (even when running under sudo)
echo "$REAL_HOME"   # /home/seb
```

### `is_btrfs path`

Returns 0 if `path` resides on a BTRFS filesystem.

```bash
is_btrfs "/mnt/hdd1" && echo "BTRFS detected"
```

### `is_mounted path`

Returns 0 if `path` is a mount point.

```bash
is_mounted "/mnt/backup" || error "Drive not mounted" "exit"
```

### `get_disk_usage path`

Prints human-readable disk usage.

```bash
get_disk_usage "/mnt/hdd1"
# Output: Used: 1.2T / 2.0T (60%)
```

### `check_disk_space source dest`

Compares source usage vs destination available space. Warns if destination would be >90% full after backup.

```bash
check_disk_space "/mnt/source" "/mnt/backup"
```

---

## BTRFS Operations

All BTRFS functions respect `DRY_RUN=true` (prints what would happen without doing it).

### `btrfs_create_snapshot source snap_dir prefix`

Create a read-only BTRFS snapshot. Skips gracefully on non-BTRFS filesystems.

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

Run BTRFS integrity check (scrub). Blocking operation.

```bash
btrfs_run_scrub "/mnt/hdd1" "Backup HDD"
```

### `btrfs_show_stats path label`

Show BTRFS compression statistics using `compsize` (if available), falls back to `btrfs filesystem df`.

```bash
btrfs_show_stats "/mnt/hdd1" "Backup HDD"
```

---

## Rsync Helpers

### `rsync_safe args...`

Rsync wrapper that treats exit codes 23 (partial transfer) and 24 (vanished files) as non-fatal warnings instead of errors.

```bash
rsync_safe -aAXHv --delete /source/ /dest/
```

### `build_rsync_options`

Build rsync options string from global variables. Outputs space-separated options.

| Variable           | Default  | Flag             |
|--------------------|----------|------------------|
| `RSYNC_ARCHIVE`    | `true`   | `-a`             |
| `RSYNC_DELETE`     | `true`   | `--delete`       |
| `RSYNC_PROGRESS`   | `true`   | `--info=progress2` |
| `RSYNC_COMPRESS`   | `false`  | `-z`             |
| `DRY_RUN`          | `false`  | `--dry-run`      |

Always adds `-v -h`.

```bash
read -ra opts <<< "$(build_rsync_options)"
rsync "${opts[@]}" /source/ /dest/
```

### `build_exclude_args excludes`

Build `--exclude=` arguments from a newline-separated string.

```bash
exclude_args=$(build_exclude_args "$EXCLUDES")
rsync $rsync_opts $exclude_args /source/ /dest/
```
