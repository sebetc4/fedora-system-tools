# system/lib — Shared Bash Library

Modular library for system scripts. Provides colors, typed messages, logging, interactive UI (via [Gum](https://github.com/charmbracelet/gum) with bash fallback), YAML parsing, configuration validation, and formatting utilities.

## Installation

```bash
sudo ./lib/install.sh          # Install yq, Gum and the lib
sudo ./lib/install.sh --no-gum # Install yq and the lib, without Gum
```

Modules are deployed to `/usr/local/lib/system-scripts/`.

The installer installs yq and Gum from Fedora's repositories when they are missing. Without Gum
(`--no-gum`), scripts use their pure bash fallback.

## Modules

| Module | Description |
|--------|-------------|
| [core.sh](#coresh) | Colors, typed messages, common checks |
| [log.sh](#logsh) | Structured logging (stdout + file) |
| [config.sh](#configsh) | Configuration loading |
| [format.sh](#formatsh) | Size, date, and name formatting |
| [ui.sh](#uish) | Interactive Gum UI + bash fallback |
| [yaml.sh](#yamlsh) | YAML parsing via yq |
| [validate.sh](#validatesh) | Configuration validation with error accumulation |
| [fs.sh](#fssh) | Filesystem helpers: mount/BTRFS detection, disk usage, sudo-aware user |

## Quick Start

```bash
#!/bin/bash
set -euo pipefail

# Load the library
readonly LIB_DIR="/usr/local/lib/system-scripts"

source "$LIB_DIR/core.sh"      # Always required
source "$LIB_DIR/ui.sh"        # Optional — for interactions

check_root
info "Script started"

if ui_confirm "Continue?"; then
    success "Let's go!"
fi
```

> Scripts are installed to `/usr/local/bin` and use the absolute library path `/usr/local/lib/system-scripts`.

---

## core.sh

Base module required by all others. Provides colors, typed messages, and common checks.

### Colors

All prefixed with `C_` to avoid conflicts with local script variables.

| Variable | Semantic | Code |
|----------|----------|------|
| `C_RED` | Errors | `\033[0;31m` |
| `C_GREEN` | Success | `\033[0;32m` |
| `C_YELLOW` | Warnings | `\033[1;33m` |
| `C_BLUE` | Informational messages | `\033[0;34m` |
| `C_CYAN` | Headers / borders | `\033[0;36m` |
| `C_MAGENTA` | Special contexts | `\033[0;35m` |
| `C_BOLD` | Emphasis, prompts | `\033[1m` |
| `C_DIM` | Debug | `\033[2m` |
| `C_NC` | Reset | `\033[0m` |

> Colors are automatically disabled when stdout is not an interactive terminal.

### Typed Messages

```bash
error "File not found"              # Red on stderr
error "File not found" "exit"       # Red on stderr + exit 1
warn "Low disk space"               # Yellow on stderr
success "Operation completed"       # Green with checkmark
info "Scan in progress..."          # Blue
debug "variable=$val"               # Dim, only when DEBUG=1 or DEBUG=true
```

### Checks

```bash
check_root                     # Exit if not root
check_deps "curl" "jq" "yq"   # Exit if dependencies missing (with dnf install hint)
has_gum                        # Returns 0 if gum is installed
```

---

## log.sh

Structured logging with timestamp to stdout and optional file.

> **Note**: log.sh writes to stdout + file. It does **NOT** use `logger`/journald.
> Service scripts that need to write to journald should keep their own `log()`.

### Configuration

```bash
source "$LIB_DIR/log.sh"

LOG_FILE="/var/log/my-script.log"         # Enable file logging (optional)
LOG_TIMESTAMP_FMT="%Y-%m-%d %H:%M:%S"    # Timestamp format (default: %H:%M:%S)
```

### Functions

```bash
log "Standard message"           # [14:32:01] Standard message
log_success "Done"               # [14:32:01] ✓ Done                    (green)
log_error "Connection failed"    # [14:32:01] [ERROR] Connection failed (red, stderr)
log_warn "Retrying in 5s"        # [14:32:01] [WARN] Retrying in 5s    (yellow, stderr)
log_section "BACKUP START"       # ═══ BACKUP START ═══                 (blue, with spacing)
log_step "Syncing files..."      # → Syncing files...                   (cyan)
```

### FD Mode (optional, for high-frequency logging)

For scripts with many log calls (e.g. backup scripts), open a file descriptor once:

```bash
LOG_FILE="/var/log/my-backup.log"
log_open_fd                        # Opens FD3 on LOG_FILE
# ... all log_* calls write to FD3 instead of reopening the file ...
trap 'log_close_fd' EXIT           # Close FD3 on exit
```

Backward-compatible: if `log_open_fd` is not called, log functions fall back to `>> $LOG_FILE`.

---

## config.sh

Centralized loading of the `paths.conf` configuration file.

```bash
source "$LIB_DIR/config.sh"

load_config                              # Loads /etc/system-scripts/paths.conf
load_config "/etc/custom/app.conf"       # Loads a specific file
```

> Automatically exits with `error` if the file does not exist.

---

## format.sh

Formatting utilities for sizes, dates, and filenames.

```bash
source "$LIB_DIR/format.sh"

format_size 1073741824      # "1.0 GB"
format_size 2621440         # "2.5 MB"
format_size 512             # "512 B"

format_date 1700000000      # "2023-11-14"

truncate_name "a-very-long-file-name.tar.gz" 20   # "a-very-long-file..."
truncate_name "short.txt" 20                        # "short.txt"
```

---

## ui.sh

Complete interactive interface with [Gum](https://github.com/charmbracelet/gum) and automatic bash fallback. All scripts work without Gum installed.

### Confirmation

```bash
ui_confirm "Delete the file?" && rm "$file"
# Gum: interactive prompt | Bash: [y/N] prompt
```

### List Selection

```bash
action=$(ui_choose "Scan" "Delete" "Skip")
# Gum: interactive list | Bash: numbered 1/2/3

# With Gum options (ignored in fallback)
action=$(ui_choose --header "Action:" "Scan" "Delete" "Skip")
```

### Text Input

```bash
ip=$(ui_input "IP Address" "192.168.1.1")
pass=$(ui_password "Master password")
```

### Fuzzy Filter

```bash
# From arguments
result=$(ui_filter "item1" "item2" "item3")

# From stdin
result=$(find /etc -name "*.conf" | ui_filter)
```

### Table

```bash
ui_table "Name,Size,Date" "report.pdf,2.1 MB,2024-01-15" "scan.log,450 KB,2024-02-01"
# Gum: formatted table | Bash: column -t with bold header

# Custom separator
ui_table -s "|" "Col1|Col2" "val1|val2"

# From stdin
echo -e "Name,Size\nfile1,1.2 GB\nfile2,500 MB" | ui_table
```

### Header and Banners

```bash
# Simple header with border
ui_header "QUARANTINE MANAGER"

# Multi-line banner (success/info)
ui_banner "SCAN COMPLETE" "Files scanned: 42" "Threats: 0"

# Error banner (red border)
ui_error_banner "SCAN FAILED" "Connection refused" "Check clamd"
```

---

## yaml.sh

YAML file parsing via [yq](https://github.com/mikefarah/yq).

### Configuration

```bash
source "$LIB_DIR/yaml.sh"

YAML_FILE="$HOME/.config/backup/config.yml"
```

### Functions

```bash
# Read a single value
mount=$(parse_yaml "backup.hdd_mount")
enabled=$(parse_yaml "snapshots.enabled")

# Read an array (one element per line; returns 1 when empty, so never pipe it)
while read -r pattern; do
    echo "Exclude: $pattern"
done < <(parse_yaml_array "exclusions.home")

# Specific file (without using YAML_FILE)
value=$(parse_yaml "key.subkey" "/path/to/other.yml")
```

> Returns an empty string for `null` or missing values.

---

## validate.sh

Configuration validation with error accumulation. Useful for validating an entire config file before starting processing.

### Workflow

```bash
source "$LIB_DIR/validate.sh"

validation_reset

validate_required "backup.mount" "$MOUNT"
validate_boolean "snapshots.enabled" "$ENABLE_SNAPSHOTS"
validate_integer "snapshots.retention" "$RETENTION"
validate_path "backup.destination" "$DEST"
validate_pattern "backup.schedule" "$SCHEDULE" '^(daily|weekly|monthly)$' "must be daily, weekly or monthly"

validation_check "config.yml"
# If errors → displays all errors and exits 1
# If OK → continues
```

### Functions

| Function | Description |
|----------|-------------|
| `validation_reset` | Resets the error list |
| `validation_add_error "msg"` | Adds an error manually |
| `validation_check ["label"]` | Displays errors and exits if count > 0 |
| `validation_error_count` | Returns the error count (without exiting) |
| `validate_required key value` | Checks that the value is not empty |
| `validate_boolean key value` | Checks for `"true"` or `"false"` |
| `validate_integer key value` | Checks for a positive integer |
| `validate_path key value` | Checks for an absolute path (`/...`) |
| `validate_pattern key value regex [hint]` | Checks against a regex pattern |

---

## fs.sh

Generic filesystem utilities: mount checks, BTRFS detection, disk usage, and sudo-aware user/home resolution.

> Depends on: core.sh, log.sh

### User Detection

```bash
detect_real_user    # Sets REAL_USER and REAL_HOME (resolves through sudo)
```

### Filesystem Helpers

```bash
is_btrfs "/mnt/hdd1"                     # True if path is on BTRFS
is_mounted "/mnt/hdd1"                   # True if path is a mount point
get_disk_usage "/mnt/hdd1"               # "Used: 1.2T / 2.0T (60%)"
check_disk_space "/source" "/dest"       # Warns if destination >90% full
```

### Backup-specific helpers

BTRFS operations, rsync helpers, the FS-agnostic destination timeline, and tar.zst archives live in the **backup module's own library**, not in `lib/`. See [`docs/modules/backup/backup-lib.md`](../modules/backup/backup-lib.md).

---

## Architecture

```
lib/
├── core.sh         # Base: colors, messages, checks
├── log.sh          # Structured logging (depends on core.sh)
├── config.sh       # Config loading (depends on core.sh)
├── format.sh       # Formatting (standalone)
├── ui.sh           # Gum UI + fallback (depends on core.sh)
├── yaml.sh         # YAML parsing (depends on core.sh)
├── validate.sh     # Config validation (depends on core.sh)
├── fs.sh           # Filesystem helpers (depends on core.sh, log.sh)
├── install.sh      # Installation script
└── README.md       # This documentation
```

### Module Dependencies

```
core.sh ←── log.sh ←── fs.sh
        ←── config.sh
        ←── ui.sh
        ←── yaml.sh
        ←── validate.sh

format.sh (standalone, no dependencies)
```

Each module has a **double-sourcing guard** (`_LIB_*_LOADED`) — it is safe to source a module multiple times.

### External Dependencies

| Tool | Required by | Mandatory? |
|------|-------------|------------|
| [Gum](https://github.com/charmbracelet/gum) | ui.sh | No — pure bash fallback |
| [yq](https://github.com/mikefarah/yq) | yaml.sh, submodule.sh, every module installer | Yes — installed by `lib/install.sh` |

