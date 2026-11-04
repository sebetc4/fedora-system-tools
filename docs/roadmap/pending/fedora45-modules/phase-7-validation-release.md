# Phase 7: Validation & Release

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/4)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** roadmap `fedora45-postinstall`, Phase 7

---

## Objective

Remove the `firewall` module, validate every kept module together on both desktops, bring the
documentation in line, and release.

### Out of Scope
The real machine's reinstall (roadmap `fedora45-postinstall`, Phase 8).

---

## Tasks

### Removal
- [ ] Remove the `firewall` module from the repository: its folder, Makefile targets, documentation and `README.md` entry
  Proof: medium, check — `make shellcheck` and `setup.sh --list` pass, and `git grep` finds no reference left

### Validation
- [ ] Run the install, upgrade, reinstall and uninstall of every kept module on a fresh snapshot of both VMs, through the harness
  Proof: high, test — the harness reports success on both VMs, and each uninstall leaves none of the module's declared files

### Documentation And Release
- [ ] Update `README.md`, `docs/` and `CLAUDE.md` to match the kept modules: names, submodules, tested Fedora versions, requirements
  Proof: medium, the module lists checked against `setup.sh --list`
- [ ] Bump the versions per `docs/core/versioning.md` and publish the release
  Proof: medium, use — the bootstrap one-liner, from the new release, on a fresh VM snapshot

---

## Technical Details

### Files to Modify
```
modules/firewall/   (removed)
Makefile
README.md
docs/
VERSION
modules/*/module.yml
```

### Dependencies
The `firewall` step of roadmap `fedora45-postinstall`, Phase 7, before the module goes.

### Constraints
`modules/firewall/uninstall.sh` restores the pre-hardening firewall state: never run it on a hardened
machine to get rid of the module.
