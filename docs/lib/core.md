# core.sh — Base Module

> Colors, typed messages, root check, dependency check, Gum detection.

**Guard:** `_LIB_CORE_LOADED`
**Dependencies:** none
**Sourced by:** all other lib modules, all module scripts

---

## Constants

### `LIB_VERSION`

Current library version (`"0.1.0"`).

### Color Variables

All prefixed with `C_` to avoid conflicts.

| Variable     | Semantic              | ANSI Code      |
|--------------|-----------------------|----------------|
| `C_RED`      | Errors                | `\033[0;31m`   |
| `C_GREEN`    | Success               | `\033[0;32m`   |
| `C_YELLOW`   | Warnings              | `\033[1;33m`   |
| `C_CYAN`     | Headers / borders     | `\033[0;36m`   |
| `C_BLUE`     | Informational         | `\033[0;34m`   |
| `C_MAGENTA`  | Special contexts      | `\033[0;35m`   |
| `C_BOLD`     | Emphasis, prompts     | `\033[1m`      |
| `C_DIM`      | Debug output          | `\033[2m`      |
| `C_NC`       | Reset                 | `\033[0m`      |

Colors are automatically disabled when stdout is not an interactive terminal (`[[ ! -t 1 ]]`).

---

## Functions

### `error msg [exit]`

Print a red error message to stderr. Pass `"exit"` as second argument to also `exit 1`.

```bash
error "File not found"
error "Critical failure" "exit"
```

### `warn msg`

Print a yellow warning to stderr.

```bash
warn "Low disk space"
```

### `success msg`

Print a green success message with `✓` prefix.

```bash
success "Backup completed"
```

### `info msg`

Print a blue informational message.

```bash
info "Starting scan..."
```

### `debug msg`

Conditional debug output (dim). Only prints when `DEBUG=1` or `DEBUG=true`.

```bash
debug "Variable=$var"
```

### `check_root`

Exit with error if not running as root.

```bash
check_root  # exits if EUID != 0
```

### `check_deps cmd...`

Check that all specified commands are available. Exits with list of missing commands.

```bash
check_deps yq rsync btrfs
```

### `has_gum`

Returns 0 if `gum` is installed, 1 otherwise.

```bash
if has_gum; then
    gum confirm "Ready?"
fi
```
