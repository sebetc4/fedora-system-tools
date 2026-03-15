# setup.sh — Interactive System Tools Manager

> Main entry point for managing Fedora system tools. Provides an interactive menu
> and CLI flags for installing, upgrading, reinstalling, uninstalling, and inspecting
> modules and submodules.

**Location:** `setup.sh` (project root)
**Requires:** non-root user (uses `sudo` internally when needed)

---

## Usage

```bash
# Interactive
./setup.sh                                # Interactive menu

# Install
./setup.sh --all                          # Install all modules
./setup.sh --install clamav               # Install all clamav submodules
./setup.sh --install clamav/quarantine    # Install one submodule

# Status & info
./setup.sh --list                         # List installed modules + submodules
./setup.sh --info clamav                  # Show module details
./setup.sh --info clamav/quarantine       # Show submodule details

# Upgrade
./setup.sh --upgrade                      # Upgrade all installed items
./setup.sh --upgrade clamav/quarantine    # Upgrade one submodule

# Reinstall
./setup.sh --reinstall                    # Interactive reinstallation
./setup.sh --reinstall clamav             # Reinstall all installed clamav subs
./setup.sh --reinstall clamav/quarantine  # Reinstall one submodule

# Uninstall
./setup.sh --uninstall                    # Interactive uninstallation
./setup.sh --uninstall clamav/quarantine  # Uninstall one submodule
```

---

## Architecture

### Pre-Lib Fallback UI

`setup.sh` cannot source the shared lib before installing it. It provides its own
local UI helpers (`warn()`, `error()`, `success()`, `info()`, `ui_confirm()`,
`ui_header()`, `ui_choose()`) with the same conventions (colors + typed messages).

Once the lib is installed, `ensure_lib()` sources `core.sh` and `ui.sh` for enhanced
features (Gum integration, color theming).

### Module Discovery

Modules are auto-discovered from `modules/*/module.yml` files. No hardcoded module
list exists. Discovery populates:

| Variable | Type | Content |
|---|---|---|
| `MODULE_DESC` | assoc array | Module descriptions |
| `MODULE_TYPE` | assoc array | `system` or `user` |
| `MODULE_DEPS` | assoc array | Inter-module deps (space-separated) |
| `MODULE_STANDALONE` | assoc array | `true` or `false` |
| `MODULE_DIR_MAP` | assoc array | Module directory paths |
| `MODULES_ORDER` | indexed array | Discovery order |

### Library Bootstrap

`ensure_lib()` handles three scenarios:

1. **Lib not installed** — auto-installs via `lib/install.sh`
2. **Lib outdated** — prompts for upgrade (interactive) or auto-upgrades (CLI)
3. **Lib current** — sources `core.sh` and `ui.sh` for enhanced features

The function checks the install exit code and aborts on failure.

---

## Safety Mechanisms

### CLI Target Validation

When a CLI target is provided (`--install clamav`, `--uninstall clamav/quarantine`),
the module name is validated against discovered modules before any action. Unknown
modules produce an error with the list of available modules.

### Inter-Module Dependency Protection

**On install:** `install_module()` checks `MODULE_DEPS` and auto-installs missing
dependencies before proceeding. In interactive mode, prompts for confirmation first.

**On uninstall:** `uninstall_module()` performs reverse-dependency checking. If any
installed module declares the target module in its `module_deps`, uninstall is blocked
with an error listing the dependent modules.

### Submodule Selection Return Check

All three `_interactive_select_*` functions set the global `SUBMODULE_SELECTION`
variable and return 0 (success) or 1 (cancelled/nothing to do). Every caller checks
the return value before using `SUBMODULE_SELECTION`:

```bash
if _interactive_select_submodules "$module"; then
    if [[ -n "$SUBMODULE_SELECTION" ]]; then
        install_module "$module" "$SUBMODULE_SELECTION"
    else
        install_module "$module"
    fi
fi
```

When `SUBMODULE_SELECTION` is empty (standalone modules, no yq fallback), the module
is installed with `--all`. When non-empty, only the selected submodules are installed.

### Minimum Library Version

`install_module()` reads `min_lib_version` from `module.yml` and compares against the
installed lib version. If the lib is too old, installation is blocked with a message
to run `make install-lib`.

---

## Interactive Submodule Selection

For submodule-based modules, three selection functions handle pre-sudo interactive
selection:

| Function | Purpose | SUBMODULE_SELECTION |
|---|---|---|
| `_interactive_select_submodules()` | Install — shows available (not yet installed) | Comma-separated selected subs |
| `_interactive_select_submodules_uninstall()` | Uninstall — shows installed | Empty = all, or comma-separated |
| `_interactive_select_submodules_reinstall()` | Reinstall — shows installed | Empty = all, or comma-separated |

All three use Gum multi-select when available, with a numbered-list bash fallback.

### Auto-Add Dependents (Uninstall)

When uninstalling, if a dependency submodule (e.g. `core`) is selected, all submodules
that depend on it are automatically added to the selection.

---

## Interactive Menu

The main menu (`main_menu()`) provides a loop with options:

| Option | Action |
|---|---|
| Status | Display all modules and submodule versions |
| Install | Select and install new modules/submodules |
| Update | Upgrade installed modules with newer versions |
| Uninstall | Remove installed modules/submodules |
| Info | Show detailed module/submodule information |
| Reinstall | Force reinstall (with `--force` flag) |
| Colors | Customize UI color theme |
| Quit | Exit |

---

## Color Customization

The Colors menu allows per-user theme customization stored in
`~/.config/system-scripts/color.conf`. Customizable properties:

- Accent color
- Header border and text colors
- Selection title and cursor colors
- Error color

Values accept ANSI 0–255 or `#RRGGBB` hex codes. Changes are applied immediately
via `color_reload()` when the lib is loaded.

---

## Internal Functions

| Function | Purpose |
|---|---|
| `_discover_modules()` | Parse all `module.yml` files |
| `_version_compare()` | Compare two semver strings (returns `lt`, `eq`, `gt`) |
| `ensure_lib()` | Install/upgrade lib, source it |
| `install_module()` | Install a module with dependency resolution |
| `uninstall_module()` | Uninstall a module with reverse-dep protection |
| `show_status()` | Display installed/available versions |
| `show_info()` | Detailed module/submodule view |
| `get_available_version()` | Read version from `module.yml` |
| `get_module_installed_version()` | Read version from registry |

---

## Registry Interaction

`setup.sh` reads registries directly (without sourcing `lib/registry.sh`) using inline
`awk` commands. This allows `--list` and discovery to work even before the lib is
installed.

- **System registry:** `/etc/system-scripts/registry`
- **User registry:** `~/.config/system-scripts/registry`
