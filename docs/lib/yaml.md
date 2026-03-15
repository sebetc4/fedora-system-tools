# yaml.sh — YAML Configuration Parsing via yq

> Read scalar values, arrays, and indexed list elements from YAML files using [yq](https://github.com/mikefarah/yq).

**Guard:** `_LIB_YAML_LOADED`
**Dependencies:** `core.sh`, `yq` (external binary)
**Sourced by:** backup scripts, `lib/submodule.sh`

---

## Setup

Set `YAML_FILE` before calling functions, or pass the file path as an extra argument:

```bash
YAML_FILE="$HOME/.config/backup/config.yml"
value=$(parse_yaml "backup.hdd_mount")
# or
value=$(parse_yaml "backup.hdd_mount" "/path/to/config.yml")
```

---

## Functions

### `parse_yaml key [file]`

Read a single scalar value. Returns empty string for `null` or missing keys.

```bash
mount=$(parse_yaml "backup.hdd_mount")
```

### `parse_yaml_array key [file]`

Read an array, outputting one item per line. Filters out `null` entries.

```bash
parse_yaml_array "exclusions.home" | while read -r item; do
    echo "Excluding: $item"
done
```

### `parse_yaml_count key [file]`

Count elements in a list. Returns `0` for `null` or missing keys.

```bash
n=$(parse_yaml_count "paths")
```

### `parse_yaml_index key index field [file]`

Read a field from a list element by index (0-based). Returns empty string for `null` or missing.

```bash
name=$(parse_yaml_index "paths" 0 "name")
src=$(parse_yaml_index "paths" 0 "source")
```

### `parse_yaml_index_array key index field [file]`

Read an array field from a list element by index. One item per line.

```bash
parse_yaml_index_array "paths" 0 "exclusions" | while read -r excl; do
    echo "Skip: $excl"
done
```
