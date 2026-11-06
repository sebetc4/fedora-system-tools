# Phase 1: Shared Foundation

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Bring the shared library, `setup.sh`, the installers and the release path to the review standard,
since every module builds on them.

### Out of Scope
The modules themselves (phases 2 to 6).

---

## Tasks

### Library
- [ ] Review each `lib/` file against the checklist, with `bats` tests for its pure functions (`registry.sh`, `submodule_sort_uninstall`, `yaml.sh`, `validate.sh`, `format.sh`)
  Proof: medium, test — the registry and dependency-order tests, each watched failing then passing
- [ ] Review `lib/submodule.sh`, the install and uninstall engine, against the checklist: every removal stays within what the module declared
  Proof: high, test — an uninstall on a VM removes the declared files and nothing else
- [ ] Replace `eval echo ~user` in `lib/notify.sh` and `uninstall.sh` with `getent passwd`
  Proof: low, check — `git grep` finds no `eval` left

### Bootstrap
- [ ] In `lib/install.sh`, install `gum` from Fedora's repositories, remove the Charm repository and its heredoc, and install `yq`, which every installer requires and `README.md` wrongly says is automatic
  Proof: medium, a run on a fresh VM snapshot holding neither `yq` nor `gum`
- [ ] Review `setup.sh`, `install.sh` and `uninstall.sh` against the checklist, splitting `setup.sh` (2188 lines) if the review calls for it
  Proof: medium, use — install, list, upgrade, reinstall and uninstall of one module on both VMs

### Release
- [ ] Fix the release path: a module tag (`release.yml`) becomes `releases/latest`, which `install.sh` and `setup.sh --self-update` cannot read; drop module tags or select the newest `v*` release
  Proof: medium, test — version detection against a release list holding a module tag

---

## Technical Details

### Files to Modify
```
lib/
setup.sh
install.sh
uninstall.sh
.github/workflows/release.yml
tests/
```

### Dependencies
Phase 0: the checklist, `make test`, and the VM harness.

### Constraints
No migration code, per `docs/core/conventions.md`. A lib change follows `docs/core/versioning.md`.
