# setup.sh — Interactive System Tools Manager

The entry point for managing the modules: its menu and CLI flags, how it finds modules and the
library, what each action applies to, the self-update, and the bootstrap and complete uninstall
around it, `install.sh` and `uninstall.sh`. What a module's installer then does is in
[submodule.sh](../lib/submodule.md); the registry it reads, in [registry.sh](../lib/registry.md).

**Location:** `setup.sh` (project root), or `/usr/local/bin/system-tools`, a link to
`/opt/fedora-system-tools/setup.sh` after the bootstrap
**Requires:** non-root user (uses `sudo` internally when needed), `yq`

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
./setup.sh --upgrade clamav               # Upgrade the outdated clamav subs
./setup.sh --upgrade clamav/quarantine    # Upgrade one submodule

# Reinstall
./setup.sh --reinstall                    # Interactive reinstallation
./setup.sh --reinstall clamav             # Reinstall all installed clamav subs
./setup.sh --reinstall clamav/quarantine  # Reinstall one submodule

# Uninstall
./setup.sh --uninstall                    # Interactive uninstallation
./setup.sh --uninstall clamav             # Uninstall all clamav submodules
./setup.sh --uninstall clamav/quarantine  # Uninstall one submodule

# Update the suite installed under /opt/fedora-system-tools
./setup.sh --self-update
```

A flag naming a module acts on the whole module, as its `make` target does; the menu asks which
submodules. An unknown option, a missing target, or an unknown module or submodule is an error.

---

## What Each Action Applies To

| Action | Submodules |
|---|---|
| Install | those not installed, or installed at an older version |
| Upgrade | those installed at an older version; a submodule not installed is an error |
| Reinstall | those installed, with `--force`; a submodule not installed is an error |
| Uninstall | those installed; in the menu, with every installed submodule depending on one picked, at any depth |

A standalone module is installed, upgraded, reinstalled or uninstalled whole. `setup.sh` passes
the submodules to the module's installer with `--only`, under `sudo` for a `system` module, so
the engine's deps resolution and protection apply.

---

## Architecture

### The Library

`setup.sh` sources `lib/core.sh`, `lib/registry.sh` and `lib/ui.sh` from beside itself, so the
library's messages, menus, registry readers and `version_compare` serve before the library is
installed. Every mode but `--list` first runs `ensure_lib()`: it installs the library, which
installs `yq` and `gum`, when the system registry holds no `lib` entry, and upgrades it when the
copy beside `setup.sh` is newer, after asking in the menu. `--list` needs `yq` already there.

### Module Discovery

Modules are discovered from `modules/*/module.yml`: no list of modules is kept. Discovery fills
`MODULE_DESC`, `MODULE_TYPE`, `MODULE_DEPS` (inter-module deps), `MODULE_STANDALONE`,
`MODULE_DIR_MAP` and `MODULES_ORDER`. Submodules come in the order `module.yml` lists them; those
of `kind: hook` show under their own heading in the status.

### Versions

An installed version is read from the system registry, then from the user's, for a module or a
`module/submodule` section; the available one from `module.yml`.

---

## Safety Mechanisms

**Inter-module dependencies.** `install_module()` installs a module's missing `module_deps`
first, after asking in the menu; `uninstall_module()` refuses a module another installed module
depends on.

**Minimum library version.** `install_module()` refuses a module whose `min_lib_version` is
above the library's.

**Selection before sudo.** In the menu, `_select_submodules <action> <module>` lists the
module's submodules with their state and lets the user pick among those the action applies to,
before any `sudo`; a single installed submodule is taken without asking. It sets
`SUBMODULE_SELECTION` and returns 1 when there is nothing to pick or nothing was picked. Without
`gum`, `ui_choose_many` reads numbers or `all`, and an empty answer picks nothing.

---

## Interactive Menu

| Option | Action |
|---|---|
| Status | Display all modules and submodule versions |
| Install | Select and install new modules/submodules |
| Update | Update the suite (from `/opt/fedora-system-tools` only), then upgrade installed modules |
| Uninstall | Remove installed modules/submodules |
| Info | Show detailed module/submodule information |
| Reinstall | Force reinstall installed submodules |
| Colors | Customize UI color theme |
| Quit | Exit |

---

## Color Customization

The Colors menu writes the user's choices to `~/.config/system-scripts/color.conf`, over the
system's `/etc/system-scripts/color.conf`, and applies them at once with `color_reload()`:
accent, header border and text, selection title, selection, and error. Values accept ANSI
0–255, `#RGB` or `#RRGGBB`; an empty header, selection title or selection color falls back to
the accent or the default. "Reset to defaults" removes the user's file.

---

## Self-Update

Only an install under `/opt/fedora-system-tools` updates itself, from the newest `vX.Y.Z`
GitHub release; a checkout says to `git pull` instead. The release's tarball is downloaded with
`curl --fail` and read as an archive before anything installed is touched, then replaces `lib/`,
`modules/`, `setup.sh` and `Makefile`, and the library is reinstalled. `latest_project_tag` and
`download_release` are the same in `install.sh`, which `tests/unit/install.bats` checks.

---

## Bootstrap And Complete Uninstall

`install.sh`, the `curl … | bash` one-liner, installs the newest release under
`/opt/fedora-system-tools`, links `system-tools` to its `setup.sh` and installs the library; with
arguments, it passes them to `system-tools`, whether it installed or found an install.

`sudo ./uninstall.sh [--yes]`, from a checkout or from `/opt/fedora-system-tools`, lists what it
removes and asks, then runs each installed module's uninstaller, found from `modules/*/module.yml`
and either registry: as root for a `system` module, as the user for a `user` module. It then
removes the library, `/etc/system-scripts`, the `system-tools` link, the user registry file
(its folder only once empty) and `/opt/fedora-system-tools`. The user's own files in the home —
module configs, `bookmarks.conf`, `color.conf` — stay, and so do `yq` and `gum`.

---

## Internal Functions

| Function | Purpose |
|---|---|
| `_discover_module` / `_discover_modules` | Read one `module.yml`, or all of them |
| `_installed_version` | Installed version of a module or `module/submodule`, from either registry |
| `_available_version` / `_sub_available_version` | Versions declared in `module.yml` |
| `_submodules` | A module's submodules, all, main or hooks |
| `_candidates` | Submodules an action applies to |
| `_has_update` | A module with an outdated installed part |
| `_with_dependents` | A selection, with the installed submodules depending on it |
| `install_module` / `uninstall_module` | Run a module's installer or uninstaller |
| `_upgrade_module` / `_reinstall_module` | Upgrade or reinstall a whole module |
| `ensure_lib` | Install or upgrade the library |
| `show_status` / `show_info` | Status table and detailed view |
| `parse_args` / `validate_target` | CLI options and target |
| `cli_upgrade` / `cli_reinstall` | The CLI's upgrade and reinstall |
| `check_remote_version` / `apply_self_update` / `self_update` | The self-update |

`setup.sh` and `uninstall.sh` run `main` only when executed, so that `tests/unit/setup.bats` and
`tests/unit/uninstall.bats` can source them and test these functions alone.
