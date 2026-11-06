# ui.sh — Interactive UI (Gum + Bash Fallback)

> Complete wrappers around [Gum](https://github.com/charmbracelet/gum) with automatic fallback to plain bash when Gum is not installed.

**Guard:** `_LIB_UI_LOADED`
**Dependencies:** `core.sh`, `color.sh`
**Sourced by:** module installers, standalone scripts, `setup.sh`

---

## Functions

### `ui_confirm prompt`

Yes/no confirmation. Returns 0 (yes) or 1 (no).

```bash
ui_confirm "Continue?" && do_thing
```

### `ui_press_enter [message]`

Pause for user to read output. Reads from `/dev/tty` (works even with stdin redirected).

```bash
ui_press_enter
ui_press_enter "Review the output above"
```

### `ui_choose items...`

Pick from a list. Supports Gum flags (`--header`, `--height`, etc.) which are stripped in fallback mode.

```bash
choice=$(ui_choose "Option A" "Option B" "Option C")
choice=$(ui_choose --header "Select module" "clamav" "backup" "torrent")
```

### `ui_input prompt [placeholder]`

Single-line text input with optional placeholder/default.

```bash
value=$(ui_input "Enter IP" "192.168.1.1")
```

### `ui_password prompt`

Silent password input (no echo).

```bash
pass=$(ui_password "Master password")
```

### `ui_filter [items...]`

Fuzzy filter a list. Works with args or piped stdin.

```bash
result=$(echo -e "item1\nitem2\nitem3" | ui_filter)
result=$(ui_filter "apple" "banana" "cherry")
```

### `ui_table [separator] rows...`

Display tabular data. Default separator is comma. Works with args or piped stdin.

```bash
ui_table "Name,Size,Date" "file1,1.2 GB,2024-01-15"
ui_table -s "|" "Col1|Col2" "val1|val2"
echo "csv data" | ui_table
```

### `ui_header title`

Styled header with colored border. Adds blank lines around it.

```bash
ui_header "TORRENT STACK READY"
# ╔═══════════════════════╗
# ║  TORRENT STACK READY  ║
# ╚═══════════════════════╝
```

### `ui_banner title lines...`

Multi-line success/info banner with border.

```bash
ui_banner "Setup complete!" \
    "VPN IP: 1.2.3.4" \
    "WebUI: http://localhost:8080"
```

### `ui_error_banner title lines...`

Error banner with red border.

```bash
ui_error_banner "ERROR" \
    "VPN not connected" \
    "Check logs: torrent logs"
```
