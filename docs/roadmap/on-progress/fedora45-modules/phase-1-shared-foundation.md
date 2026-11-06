# Phase 1: Shared Foundation

---

## Status

**Current Status:** 🟡 In Progress (38% — 3/8)
**Started:** 2026-11-06
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
- [x] Replace `eval echo ~user` in `lib/notify.sh` and `uninstall.sh` with `getent passwd`
  Proof: low, check — `git grep` finds no `eval` left
- [x] Fix the registry's two defects the VM harness showed: each `registry_set` leaves one more blank line in the file, and the user registry and its folder stay once their last entry is removed
  Proof: medium, test — `bats` tests of both, watched failing then passing

### Bootstrap
- [x] In `lib/install.sh`, install `gum` from Fedora's repositories, remove the Charm repository and its heredoc, and install `yq`, which every installer requires and `README.md` wrongly says is automatic
  Proof: medium, a run on a fresh VM snapshot holding neither `yq` nor `gum`
- [ ] Review `setup.sh`, `install.sh` and `uninstall.sh` against the checklist, splitting `setup.sh` (2188 lines) if the review calls for it
  Proof: medium, use — install, list, upgrade, reinstall and uninstall of one module on both VMs
- [ ] Seed each config file a submodule installs from `my-config/`, laid out like the repository's tree (`my-config/modules/backup/vps/config.yml` for `modules/backup/vps/config.yml`), when a copy is kept there, from the module's default otherwise, and never overwrite an installed config file
  Proof: medium, test — a VM install with a copy in `my-config/` installs the copy, and a second install leaves an edited config untouched

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
