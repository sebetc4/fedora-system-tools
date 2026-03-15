# format.sh — Size, Date & Name Formatting

> Formatting utilities for human-readable file sizes, dates, and truncated filenames.

**Guard:** `_LIB_FORMAT_LOADED`
**Dependencies:** none (standalone)
**Sourced by:** torrent scripts, quarantine, backup scripts

---

## Functions

### `format_size bytes`

Convert byte count to human-readable size with one decimal place.

```bash
format_size 1073741824   # "1.0 GB"
format_size 5242880      # "5.0 MB"
format_size 2048         # "2.0 KB"
format_size 512          # "512 B"
```

Uses `bc` for floating-point division. Thresholds: GB > MB > KB > B.

### `format_date timestamp`

Convert Unix timestamp to `YYYY-MM-DD` format.

```bash
format_date 1700000000   # "2023-11-14"
```

Returns `?` on invalid timestamps.

### `truncate_name string [max]`

Truncate a string to `max` characters (default: 38), appending `...` if truncated.

```bash
truncate_name "very-long-filename-that-exceeds-limit.tar.gz" 20
# "very-long-filenam..."

truncate_name "short.txt" 20
# "short.txt"
```
