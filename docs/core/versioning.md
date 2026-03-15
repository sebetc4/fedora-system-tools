# Versioning

This project uses [SemVer](https://semver.org/) (`major.minor.patch`) across three
independent levels: **lib**, **module**, and **submodule**.

## The Four Levels

```
project       → v0.1.0   release snapshot (VERSION file)
  lib         → v0.1.0   shared infrastructure (lib/)
    module    → v0.1.0   orchestration (install.sh, shared/, module.yml structure)
      submodule → v0.1.0 individual script + its service/timer/config
```

Each level has its own version declared in its respective source of truth:

| Level | Declared in | Variable |
|---|---|---|
| project | `VERSION` (root) | git tag `v*` |
| lib | `lib/core.sh` | `LIB_VERSION` |
| module | `module.yml` → `version:` | `MODULE_VERSION` |
| submodule | `module.yml` → `submodules.<name>.version:` | `version` field |

## SemVer Rules

| Bump | When |
|---|---|
| **patch** (0.0.x) | Bugfix, typo correction, documentation-only change |
| **minor** (0.x.0) | New feature, improvement, new parameter/option |
| **major** (x.0.0) | Breaking change, removal of feature, API incompatibility |

## Pre-1.0 Phase

While any version starts with `0.`, the API is **not guaranteed stable**. Breaking
changes may appear in minor bumps (e.g. `0.1.0 → 0.2.0`) without requiring a major
bump. This allows rapid iteration before stability is declared.

**`1.0.0` marks API stability** — from that point, breaking changes require a major bump.

## Independence — No Cascade

Versions evolve independently. There is **no automatic cascade**:

- **Lib bump → no forced module/submodule bump** — modules continue working as long
  as their `min_lib_version` is satisfied.
- **Module bump → no forced submodule bump** — module infrastructure changed, scripts
  did not.
- **Submodule bump → no forced module bump** — the script evolved, the orchestration
  did not.
- **Core submodule bump → no forced bump of dependents** — only bump dependents
  manually if the core's interface changed in a way that affects them.

## What Each Level Covers

### lib

Changes to files in `lib/`. Bump when:

- New function added to any lib file → **minor**
- Function signature or return value changed → **major** (or **minor** in pre-1.0)
- Bug fixed in an existing function → **patch**
- Lib file refactored with no API change → **patch**

### module

Changes to module orchestration. Bump when:

- `install.sh` or `uninstall.sh` logic changed → **patch** or **minor**
- New submodule added to `module.yml` → **minor**
- Submodule removed from `module.yml` → **major** (or **minor** in pre-1.0)
- `shared/` hook scripts (setup/cleanup) changed → **patch** or **minor**
  - Also bump the `core` submodule version if the hooks changed

### submodule

Changes to the submodule script and its associated files. Bump when:

- Bug fixed in the script → **patch**
- New feature or option added → **minor**
- Script behavior fundamentally changed → **minor** or **major**
- Associated service/timer/config changed → same bump as the script change that drove it

## Compatibility: `min_lib_version`

Every `module.yml` declares the minimum required lib version:

```yaml
name: clamav
version: 0.1.0
min_lib_version: 0.1.0   # Minimum lib version required
```

This is validated at install time by:
- `lib/submodule.sh` — for submodule-based modules
- `modules/<standalone>/install.sh` — for standalone modules
- `setup.sh` `install_module()` — for all modules via `setup.sh`

**Error message on failure:**
```
ERROR: Module clamav requires lib >= 0.2.0 (installed: 0.1.0). Run: make install-lib
```

When to update `min_lib_version`:
- When your module uses a lib function introduced in a specific lib version
- Update to match the exact lib version that introduced the required feature

## How to Bump a Version

### Bumping a submodule

1. Edit `modules/<module>/module.yml` — update the submodule's `version:` field
2. Update the `# Version:` header in the submodule's script

Example — bumping `clamav/daily-clamscan` from `0.1.0` to `0.2.0`:
```yaml
# modules/clamav/module.yml
  daily-clamscan:
    version: 0.2.0    # ← changed
```
```bash
# modules/clamav/scripts/services/daily-clamscan.sh
# Version: 0.2.0     # ← changed
```

### Bumping a module

1. Edit `modules/<module>/module.yml` — update the top-level `version:` field
2. Update the `# Version:` header in `install.sh` and `uninstall.sh`

The module version in the registry tracks the highest-installed submodule set version,
but the module itself has its own independent version for orchestration changes.

### Bumping the lib

1. Edit `lib/core.sh` — update `LIB_VERSION`
2. Update the `# Version:` header in `lib/install.sh`
3. If the change requires modules to update, bump `min_lib_version` in affected
   modules' `module.yml` files

## Project Version & Release Rule

The project version (`VERSION` file) is the **distribution snapshot**. It determines
what users receive via `system-tools --self-update`.

**Rule: any change to a deliverable component requires a project version bump and tag.**

This includes: submodule bump, module bump, lib bump, setup.sh change, new module.
The project version is the vehicle that delivers changes to users — without a new
project tag, `--self-update` reports "Already up to date" even if components changed.

### Bumping the project version

1. Edit `VERSION` — update the version number
2. Commit all changes
3. Tag: `git tag v0.2.0 && git push --tags`
4. CI creates the release tarball automatically

### Project bump guidelines

| Change | Project bump |
|---|---|
| Bugfix in one submodule | **patch** (0.1.0 → 0.1.1) |
| New feature in a module | **minor** (0.1.0 → 0.2.0) |
| New module added | **minor** |
| Breaking change in setup.sh or lib API | **major** (or **minor** in pre-1.0) |
| Documentation-only change | No bump needed (not in tarball) |

## Release Tags

Two types of git tags trigger GitHub releases:

### Project-level tags (`v*`)

```
v0.1.0              # full project release
v0.2.0              # next project release
```

The release tarball contains everything: `lib/`, `modules/`, `setup.sh`, `Makefile`.
This is what `install.sh` and `--self-update` download.

### Module-level tags (`<module>-v*`)

```
lib-v0.2.0          # lib release (changelog only)
clamav-v0.3.0       # clamav module release (changelog only)
```

Module-level tags create per-module tarballs and changelogs. They are optional and
complementary to project tags — useful for detailed changelogs but not required for
user distribution.

## Scenarios

### "I fixed a bug in daily-clamscan.sh"
→ Bump `clamav/daily-clamscan` submodule: `0.1.0 → 0.1.1`
→ No change to module version or lib version

### "I added a --dry-run flag to quarantine"
→ Bump `clamav/quarantine` submodule: `0.1.0 → 0.2.0`
→ No change to module version

### "I added a new lib function `validate_path()`"
→ Bump lib: `0.1.0 → 0.2.0`
→ Modules that use `validate_path()` must set `min_lib_version: 0.2.0`
→ No version bump required for modules that don't use it

### "I added a new submodule `clamav/realtime-scan`"
→ Bump clamav module: `0.1.0 → 0.2.0`
→ The new submodule starts at `0.1.0`
→ No change to lib or existing submodules

### "The core submodule setup script now creates a new directory"
→ Bump `clamav/core` submodule: `0.1.0 → 0.2.0`
→ Bump clamav module if the install.sh orchestration changed: `0.1.0 → 0.1.1`
→ Other submodules (`daily-clamscan`, etc.) don't need bumping unless their behavior changed
