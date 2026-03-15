# log.sh — Structured Logging

> Timestamped logging to stdout and optional log file, with file descriptor mode for high-frequency logging.

**Guard:** `_LIB_LOG_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** backup scripts, torrent, hook scripts

---

## Configuration

Set these variables before or after sourcing:

| Variable              | Default      | Description                    |
|-----------------------|--------------|--------------------------------|
| `LOG_FILE`            | `""`         | Path to log file (empty = no file logging) |
| `LOG_TIMESTAMP_FMT`   | `%H:%M:%S`  | `date` format for timestamps   |

---

## Functions

### `log_open_fd`

Open file descriptor 3 on `LOG_FILE` for high-frequency logging. No-op if `LOG_FILE` is empty or FD3 already open.

```bash
LOG_FILE="/var/log/backup.log"
log_open_fd
log "message"      # writes to FD3 + console
log_close_fd
```

### `log_close_fd`

Close FD3 if open.

### `log msg`

Log a message with timestamp to stdout and file (if configured).

```bash
log "Starting backup"
# Output: [14:30:05] Starting backup
```

### `log_error msg`

Red `[ERROR]` message to stderr + file.

```bash
log_error "Disk full"
```

### `log_success msg`

Green `✓` message to stdout + file as `[OK]`.

```bash
log_success "Backup completed"
```

### `log_warn msg`

Yellow `[WARN]` message to stderr + file.

```bash
log_warn "Partition nearly full"
```

### `log_section title`

Blue section separator with `═══` borders. Adds blank lines for readability.

```bash
log_section "PHASE 1: SNAPSHOT"
```

### `log_step msg`

Cyan `→` prefix for substeps.

```bash
log_step "Creating BTRFS snapshot..."
```

---

## Internal

### `_log_to_file msg`

Writes plain text to the log file using FD3 (if open) or direct append (if `LOG_FILE` set). Not for external use.
