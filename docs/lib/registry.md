# registry.sh — Module Registry

> INI-style registry for tracking installed modules, submodules, and versions.

**Guard:** `_LIB_REGISTRY_LOADED`
**Dependencies:** none (standalone)
**Sourced by:** `submodule.sh`, `install.sh`, standalone module installers, `setup.sh`

---

## Registry Files

| Scope  | Path                                    | Used for                        |
|--------|-----------------------------------------|---------------------------------|
| System | `/etc/system-scripts/registry`          | Root-installed modules          |
| User   | `~/.config/system-scripts/registry`     | User-level submodules (e.g. backup/vps) |

Registry format (INI-style):

```ini
[clamav]
version=0.1.0
installed=2026-02-15 10:30:45

[clamav/daily-clamscan]
version=0.1.0
installed=2026-02-15 10:30:46
```

---

## Constants

| Constant           | Value                                |
|--------------------|--------------------------------------|
| `SYSTEM_REGISTRY`  | `/etc/system-scripts/registry`       |
| `USER_REGISTRY`    | `~/.config/system-scripts/registry`  |

---

## Functions

### Path & Init

#### `registry_get_path`

Returns the registry file path: system if root, user otherwise.
Override with `REGISTRY_PATH_OVERRIDE` env var (used by submodule engine for user-type submodules under sudo).

#### `registry_init`

Ensure registry file exists. Creates the file with a header comment if absent. Called automatically by `registry_set`.

---

### Module-Level Operations

#### `registry_set module version`

Register or update a module. Creates a timestamped entry.

```bash
registry_set "clamav" "0.1.0"
```

#### `registry_remove module`

Remove a module entry from the registry.

```bash
registry_remove "clamav"
```

#### `registry_get_version module`

Get the installed version of a module. Returns 1 if not found.

```bash
version=$(registry_get_version "clamav")  # "0.1.0"
```

#### `registry_is_installed module`

Returns 0 if the module is registered, 1 otherwise.

```bash
if registry_is_installed "clamav"; then
    echo "ClamAV is installed"
fi
```

---

### Submodule-Level Operations

#### `registry_set_submodule module submodule version [module_version]`

Register a submodule. Auto-creates the parent module entry if `module_version` is provided and not already registered.

```bash
registry_set_submodule "clamav" "daily-clamscan" "0.1.0" "0.1.0"
```

#### `registry_remove_submodule module submodule`

Remove a submodule entry. Auto-removes the parent module entry when the last submodule is removed.

```bash
registry_remove_submodule "clamav" "daily-clamscan"
```

#### `registry_get_submodule_version module submodule`

Get the installed version of a submodule.

```bash
version=$(registry_get_submodule_version "clamav" "daily-clamscan")
```

#### `registry_is_submodule_installed module submodule`

Returns 0 if the submodule is registered.

```bash
if registry_is_submodule_installed "clamav" "quarantine"; then
    echo "Quarantine is installed"
fi
```

#### `registry_list_submodules module`

List installed submodule names for a module (one per line, without module prefix).

```bash
registry_list_submodules "clamav"
# daily-clamscan
# quarantine
```

#### `registry_count_submodules module`

Count installed submodules for a module.

```bash
count=$(registry_count_submodules "clamav")  # 3
```

---

### Version Comparison

#### `version_compare version_a version_b`

Compare two SemVer versions. Prints `lt`, `eq`, or `gt`.

```bash
result=$(version_compare "0.1.0" "0.2.0")  # "lt"
result=$(version_compare "1.0.0" "1.0.0")  # "eq"
result=$(version_compare "2.0.0" "1.9.9")  # "gt"
```
