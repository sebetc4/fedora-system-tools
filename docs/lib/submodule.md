# submodule.sh — Submodule Engine

> Install/uninstall/update engine for submodules declared in `module.yml`. Module installers become thin orchestrators calling these functions.

**Guard:** `_LIB_SUBMODULE_LOADED`
**Dependencies:** `core.sh`, `registry.sh`, `notify.sh`
**Sourced by:** module `install.sh` / `uninstall.sh` (clamav, backup)

---

## Architecture

```
module.yml (WHAT) → submodule.sh (HOW) → install.sh orchestrator (WHEN/flow)
```

Module installers call `submodule_run_install` / `submodule_run_uninstall` which handle:
1. CLI argument parsing (`--all`, `--only <names>`, or interactive selection)
2. Submodule listing and dependency resolution
3. Installation/uninstallation loop with per-submodule callbacks

---

## YAML Parsing Helpers

### `module_get field [yml_path]`

Read a top-level field from `module.yml`.

```bash
name=$(module_get "name" "$MODULE_YML")          # "clamav"
version=$(module_get "version" "$MODULE_YML")     # "0.1.0"
```

### `submodule_get submodule field [yml_path]`

Read a submodule-level field.

```bash
version=$(submodule_get "daily-clamscan" "version" "$MODULE_YML")
source=$(submodule_get "daily-clamscan" "source" "$MODULE_YML")
```

### `submodule_list [yml_path]`

List all submodule names (one per line).

```bash
mapfile -t subs < <(submodule_list "$MODULE_YML")
```

### `submodule_get_array submodule field [yml_path]`

Read a submodule array field as newline-separated values.

```bash
mapfile -t deps < <(submodule_get_array "daily-clamscan" "deps" "$MODULE_YML")
mapfile -t services < <(submodule_get_array "daily-clamscan" "services" "$MODULE_YML")
```

---

## User-Type Submodule Support

Submodules can declare `type: user` in `module.yml` to override the module's default type. The engine transparently handles:

- Install target: `~/.local/bin` instead of `/usr/local/bin`
- Systemd: `~/.config/systemd/user/` with `systemctl --user`
- Registry: user registry via `REGISTRY_PATH_OVERRIDE`
- Ownership: files owned by real user, not root

---

## Orchestrators (Public API)

### `submodule_run_install module_dir [-- CLI args]`

Full install orchestration. Handles:
- Parsing CLI flags (`--all`, `--only name,name`, or interactive `gum` multi-select)
- Listing available submodules from `module.yml`
- Dependency resolution (auto-installs `deps: [core]` before dependents)
- Per-submodule install: script copy, service/timer install, logrotate, notify registration
- Registry updates

```bash
# In module install.sh:
submodule_run_install "$SCRIPT_DIR" "$@"
```

### `submodule_run_uninstall module_dir [-- CLI args]`

Full uninstall orchestration. Handles:
- Parsing CLI flags (`--all`, `--only name,name`, or interactive selection of installed subs)
- Dependency-aware ordering via `submodule_sort_uninstall` (dependents first, core last)
- Dependency protection (blocks removing core while dependents exist)
- Per-submodule uninstall: stop services, remove binaries/services/timers, hooks cleanup
- Registry cleanup

```bash
# In module uninstall.sh:
submodule_run_uninstall "$SCRIPT_DIR" "$@"
```

---

## Lower-Level Functions

### `submodule_install module_dir submodule yml_path`

Install a single submodule. Called by `submodule_run_install` for each selected submodule. Handles:
- Dependency auto-install (recursive)
- Skip if already installed at same version
- Binary install to target path
- Service/timer installation (including `.tpl` template expansion)
- Logrotate config installation
- Notify-daemon registration
- Directory creation (from `dirs:` in `module.yml`)
- Config file installation
- Hook script execution (`hooks.install`)
- Registry registration

### `submodule_uninstall module_dir submodule yml_path`

Uninstall a single submodule. Called by `submodule_run_uninstall` for each selected submodule. Handles:
- Dependency protection check
- Service/timer stop and removal
- Binary removal
- Logrotate config removal
- Notify-daemon unregistration
- Hook script execution (`hooks.uninstall`)
- Registry cleanup

### `submodule_sort_uninstall yml_path submodules...`

Sort submodules for safe uninstall order: dependents first, then deps targets (core last).

```bash
mapfile -t sorted < <(submodule_sort_uninstall "$MODULE_YML" "${selected[@]}")
```

---

## Optional Callbacks

Define these functions in your `install.sh`/`uninstall.sh` before calling the orchestrators:

| Callback                           | Called when                        |
|------------------------------------|------------------------------------|
| `_module_post_install module_name` | After all submodules installed     |
| `_module_pre_uninstall`            | Before uninstall loop starts       |
| `_module_post_uninstall module_name` | After all submodules uninstalled |

---

## Internal Functions

| Function                       | Purpose                                          |
|--------------------------------|--------------------------------------------------|
| `_submodule_resolve_context`   | Set `_sub_type`, `_real_user` from `module.yml`  |
| `_systemctl_cmd`               | Build `systemctl` command (system vs user)        |
| `_submodule_bin_path`          | Return bin install path for submodule type        |
| `_submodule_systemd_dir`       | Return systemd unit directory for submodule type  |
| `_submodule_expand_path`       | Expand `~` in paths for user-type submodules      |
| `_is_sub_installed`            | Check if submodule is currently installed          |
| `_get_sub_version`             | Get installed version of a submodule               |
| `_sub_success` / `_sub_info` / `_sub_error` | Prefixed logging for submodule context |
| `_install_service_template`    | Process and install `.tpl` service files           |
| `_install_submodule_configs`   | Install config files declared in `module.yml`      |
| `_install_submodule_hooks`     | Run install hook scripts                           |
| `_uninstall_submodule_hooks`   | Run uninstall hook scripts                         |
