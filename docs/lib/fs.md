# fs.sh — Filesystem Helpers

> Generic filesystem utilities: mount checks, BTRFS detection, disk usage, and sudo-aware user/home resolution.

**Guard:** `_LIB_FS_LOADED`
**Dependencies:** `core.sh`, `log.sh`
**Sourced by:** backup module scripts, and any module needing FS introspection.

---

## Functions

### `detect_real_user`

Sets `REAL_USER` and `REAL_HOME`, resolving through `SUDO_USER` if present.

```bash
detect_real_user
echo "$REAL_USER"  
echo "$REAL_HOME"   
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

## See also

Backup-specific helpers (BTRFS ops, rsync helpers, timeline, archive) live in
the backup module's own library, not in `lib/`. See
[`docs/modules/backup/backup-lib.md`](../modules/backup/backup-lib.md).
