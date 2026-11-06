# submodule.sh — Submodule Engine

The install, uninstall and update engine for the submodules a `module.yml` declares: the keys it
reads, what an install writes and an uninstall removes, and its functions. Module installers are
thin orchestrators calling it. The registry it writes to is in [registry.sh](registry.md), the
notification tags in [notify.sh](notify.md), and every path a module installs in
[State, Configuration & Installed Paths](../core/state-and-paths.md).

**Guard:** `_LIB_SUBMODULE_LOADED`
**Dependencies:** `core.sh`, `registry.sh`, `notify.sh`, `yq`, `rpm`, `dnf`, `runuser`
**Sourced by:** module `install.sh` / `uninstall.sh` (clamav, backup, build-kernel)

---

## Architecture

```
module.yml (WHAT) → submodule.sh (HOW) → install.sh orchestrator (WHEN/flow)
```

Module installers call `submodule_run_install` / `submodule_run_uninstall`, under `sudo`, which
handle:
1. CLI argument parsing (`--all`, `--only <names>`, `--force`, or interactive selection)
2. Submodule listing and dependency resolution
3. The installation or uninstallation loop, with the module's callbacks

---

## Submodule Keys

What `submodule_install` does with each key of a submodule in `module.yml`, in this order:

| Key | Install | Uninstall |
|-----|---------|-----------|
| `version` | required; equal to the registry's, nothing is done without `--force` | — |
| `type` | `user` or `system`, the module's `type` by default | — |
| `deps` | each dependency not installed is installed first | refused while an installed submodule depends on it |
| `required_commands` | a command found in neither root's nor the user's login `PATH` gets a warning with its `install_hint`; the install goes on | — |
| `system_deps` | the packages nothing installed provides (`rpm -q --whatprovides`) are installed with `dnf install -y`, without asking | kept |
| `source` + `bin_name` | installed mode 755 in the bin directory | removed |
| `hooks.install` / `hooks.uninstall` | the script runs as root; a declared script missing stops the install | the script runs as root, after the units and binary are gone |
| `services` / `timers` | installed in the unit directory, a `.tpl` rendered; timers enabled, services enabled with `--now` when the submodule has no timer | stopped, disabled when enabled, a timer's persistent stamp cleaned, files removed |
| `dirs` | created with their `mode` (755 by default) | removed with their content, deepest first, when the removal guard allows |
| `configs` | a missing file copied mode 644 from the user's copy in `my-config/` when there is one, from the module's default otherwise; an installed file is never overwritten, and one that differs from its copy is said | kept, and listed at the end of the uninstall |
| `hook_scripts` | each `<event>/<name>.sh` of the folder installed mode 755 to `hooks.d/<event>/` | those files removed, then each folder left empty |
| `logrotate` | installed to `/etc/logrotate.d/<name>`; a `.tpl` rendered to `/etc/logrotate.d/<user>-<name>` | removed |
| `notifications` | each `tag` registered with its `icon` and `level` | each tag unregistered |

A template (`.tpl`) has `__HOME__` and `__USER__` replaced by the user's home and name;
`download-clamscan.service.tpl` gets its `ReadWritePaths=` from `paths.conf` instead. A service
template unit (`name@.service`) is never enabled: its instances are started by their trigger and
stopped at the uninstall. `hooks.d` is `/usr/local/lib/system-scripts/hooks.d`, or
`SUBMODULE_HOOKS_DIR` when set.

A config's copy sits in `my-config/` at the root of the checkout the install runs from, at the
path of the default it replaces: `my-config/modules/backup/vps/config.yml` for
`modules/backup/vps/config.yml`. `MY_CONFIG_DIR` points elsewhere. The rule behind it is in
[Conventions](../core/conventions.md), Personal settings.

---

## User Context

The engine runs as root and acts for `SUDO_USER`, whose home comes from `getent passwd`; an
unknown user stops the install. A submodule of `type: user` installs to `~/.local/bin` and
`~/.config/systemd/user/`, runs `systemctl --user` as the user, and is recorded in the user's
registry.

Whatever the type, every file and folder written in the user's home is written by the user
through `runuser`, its missing parents included, so nothing there belongs to root: a
`system` submodule's config under `~/.config` as much as a `user` submodule's binary. A path in
`module.yml` starting with `~/` lies in that home.

---

## What An Uninstall Removes

An uninstall removes what the submodule's keys declare and nothing else:

- **Declared directories** go with their content only when the removal guard allows: an absolute
  path with no `.` or `..` component, two levels deep at least, two levels below the user's home
  when it lies in it, and owned by no package. A directory the guard refuses is kept with a
  warning.
- **Hook scripts** go by name, the scripts the module ships alone: a script the user added to
  `hooks.d/<event>/` stays.
- **Folders of the user's home** that the removed files needed — `~/.local/bin`, `~/.local/log`,
  `~/.config/systemd/user` and its `*.wants`, `~/.local/share/systemd/timers` — are removed while
  empty, never a direct child of the home such as `~/.config` or `~/.local`.
- **Config files** stay, and the uninstall lists those it leaves. `notify_unregister` removes the
  notification files once no tag of their own remains.

---

## Orchestrators (Public API)

### `submodule_run_install module_dir [options]`

Install orchestration: `--all` installs every submodule, `--only a,b` the named ones,
`--force` reinstalls those already at their version, and no option asks which, with `gum` or a
numbered list. An unknown option, `--only` without a list, or an unknown submodule name is an
error. It lists each submodule's state, installs the selection in order, then the installed
submodules, and calls `_module_post_install`.

```bash
# In module install.sh:
submodule_run_install "$SCRIPT_DIR" "$@"
```

### `submodule_run_uninstall module_dir [options]`

Uninstall orchestration: `--all`, `--only a,b`, or no option to choose among the installed
submodules; `--force` is an error. The selection is sorted by `submodule_sort_uninstall`, each
submodule uninstalled, and `_module_post_uninstall` called.

```bash
# In module uninstall.sh:
submodule_run_uninstall "$SCRIPT_DIR" "$@"
```

### Optional Callbacks

Define these functions in your `install.sh`/`uninstall.sh` before calling the orchestrators:

| Callback                           | Called when                        |
|------------------------------------|------------------------------------|
| `_module_post_install module_name` | After all submodules installed     |
| `_module_post_uninstall module_name` | After all submodules uninstalled |

---

## Lower-Level Functions

### `submodule_install module_dir submodule [yml_path]`

Install one submodule, per Submodule Keys. `SUBMODULE_FORCE=true` reinstalls it at its version;
`SUBMODULE_PROGRESS_CURRENT` and `SUBMODULE_PROGRESS_TOTAL` number its header.

### `submodule_uninstall module_dir submodule [yml_path]`

Uninstall one submodule, per Submodule Keys and What An Uninstall Removes; it returns 1 while an
installed submodule depends on it.

### `submodule_sort_uninstall yml_path submodules...`

Sort submodules for safe uninstall order: no submodule comes before one that depends on it, at
any depth (`report` → `scanner` → `core` for a chain), and independent submodules keep the order
given. A dependency that is not selected holds nothing back; the uninstall's deps protection
deals with it.

```bash
mapfile -t sorted < <(submodule_sort_uninstall "$MODULE_YML" "${selected[@]}")
```

### YAML Parsing Helpers

| Function | Prints |
|----------|--------|
| `module_get field [yml_path]` | a top-level field, empty when absent |
| `submodule_get submodule field [yml_path]` | a submodule's field, `hooks.install` included |
| `submodule_list [yml_path]` | the submodule names, one per line |
| `submodule_get_array submodule field [yml_path]` | an array field, one value per line |

```bash
version=$(submodule_get "quarantine" "version" "$MODULE_YML")
mapfile -t deps < <(submodule_get_array "quarantine" "deps" "$MODULE_YML")
```

---

## Internal Functions

| Function | Purpose |
|----------|---------|
| `_submodule_type` | A submodule's type, else the module's, else `system` |
| `_submodule_user` / `_submodule_user_home` | `SUDO_USER`, or the caller by `id -un`, and that user's home |
| `_submodule_resolve_context` | Set `_sub_type`, `_real_user`, `_real_home`, `_real_uid`, declared local by the caller |
| `_as_user` | Run a command as the user (`runuser` under root) |
| `_submodule_owner_run` | Run a command as the user for a path in the user's home |
| `_submodule_write` | Write stdin to a file with a mode, as its owner |
| `_submodule_render` | Replace `__HOME__` and `__USER__` in a template |
| `_systemctl_cmd` | `systemctl`, or `systemctl --user` as the user |
| `_submodule_bin_path` / `_submodule_systemd_dir` | Bin and unit directories of the type |
| `_submodule_expand_path` | Expand a leading `~/` to the user's home |
| `_submodule_logrotate_dest` | Destination of a logrotate config or template |
| `_submodule_units` | Unit names a submodule installs, timers first |
| `_submodule_registry` | Run a registry function on the registry of a submodule's type |
| `_is_sub_installed` / `_get_sub_version` | Installed state and version of a submodule |
| `_submodule_dependents` | Installed submodules depending on a submodule |
| `_submodule_missing_packages` | Packages nothing installed provides |
| `_submodule_has_command` | A command in root's or the user's login `PATH` |
| `_submodule_removable_dir` | The removal guard of declared directories |
| `_submodule_prune_home_dir` | Remove empty folders of the home, up to its direct children |
| `_submodule_parse_args` / `_submodule_check_names` / `_submodule_pick` | Orchestrator options, names and selection |
| `_sub_success` / `_sub_info` / `_sub_warn` / `_sub_error` | Indented messages |
| `_show_preserved_configs` | List the config files an uninstall leaves |
| `_install_service_template` | Render and install a `.tpl` unit |
| `_install_submodule_configs` | Install the `configs:` files, from `my-config/` first |
| `_install_submodule_hooks` / `_uninstall_submodule_hooks` | Install and remove the `hook_scripts:` files |

---

## Decisions

### 2026-11-06 — An uninstall removes only what a submodule declares, behind a guard

Decided in roadmap `fedora45-modules`, Phase 1, in the engine's review against the module review
checklist; it shapes What An Uninstall Removes. Hook scripts go by name, declared directories
pass the removal guard, and the empty folders of the user's home that the install created go
too, never a direct child of the home.

- Set aside: removing `hooks.d/pre-backup` and `hooks.d/post-backup` whole, which deleted any
  script the user added there, as `docs/modules/backup/local.md` invites.
- Set aside: keeping the empty folders of the home, which the VM harness reports as left behind.
- Facts: on this machine, `hooks.d/pre-backup` held `btrfs-snapshot.sh`, a hook the repository no
  longer ships, which the former uninstall would have deleted; the review of 2026-11-06.

### 2026-11-06 — Missing packages are installed without asking, missing commands warn

Decided in the same review; it shapes Submodule Keys. `system_deps` are package names checked
with `rpm`, and those missing are installed with `dnf install -y`, as `lib/install.sh` installs
`yq` and `gum`. A `required_commands` entry missing gets a warning and the install goes on: the
script checks it again when it runs.

- Set aside: the `[y/N]` prompt, whose default skipped the packages, so an install without a
  terminal left the submodule broken; and `command -v` on package names, which never found
  `inotify-tools`.
- Set aside: stopping the install on a missing command, which stopped `make install-backup` at
  `bitwarden` without `bw`, leaving `vps` uninstalled.
