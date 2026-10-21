# Phase 0: Framing & Architecture

---

## Status

**Current Status:** 🟡 In Progress (0% — 0/15)
**Started:** 2026-10-21
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## While Working

Keep `phase-0-framing-architecture-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Establish the facts and the design the rest of the roadmap builds on: an inventory of the current
Fedora 44 workstation, the architecture of the new `postinstall/` tool, and a Fedora 45 test VM.

---

## Overview

### Why This Phase Matters
The old script was written for one machine and grew by accretion; its lists are already stale
(2 of the 26 installed Flatpaks are listed, and those 2 are no longer installed). A generic tool
needs its step model, profile format, and root/user split decided before any code, otherwise each
later phase reinvents them.

### What It Enables
Phase 1 implements the framework against a written design. Phases 4 to 7 triage from a recorded
inventory instead of guessing from memory.

### Out of Scope
Implementing any step. Triaging individual packages, Flatpaks, or extensions (phases 4 to 6).

---

## Tasks

### Inventory
- [ ] Record the current system facts in the report: Fedora version, GPU and CPU, Secure Boot state, enabled repositories with their owning package, repository overrides
- [ ] Export the explicitly installed packages (reason `User` and `External User`) with their origin repository to a local inventory folder outside the repository
- [ ] Export the Flatpak apps with their origin remote, and the enabled GNOME extensions with their install location (user or system)
- [ ] Export the modified `/etc` config files (`rpm -Va`) and the unowned files in `/etc/systemd/system`, `/etc/logrotate.d`, `/etc/snapper/configs`, `/etc/dnf/repos.override.d`
- [ ] Dump the GNOME dconf tree (`dconf dump /`) for the selection made in phase 6

### Architecture
- [ ] Decide the `postinstall/` layout: entry point, steps folder, profiles folder, shared helpers
- [ ] Decide the step model: one file per step with a check/apply contract, ordering, selection by name
- [ ] Decide the profile format (plain list files or YAML read with `yq`) and how a profile overrides the generic defaults
- [ ] Decide the root/user split: which steps run as root, which as the desktop user, and how one invocation drives both
- [ ] Decide the hardware detection rules steps may query (GPU vendors, Secure Boot, btrfs root, desktop environment)
- [ ] Decide how `lib/` is reused from the repository checkout before it is installed system-wide
- [ ] Decide the logging location, the dry-run semantics, and the failure policy (a failed step does not stop the run; summary at the end)
- [ ] Decide the versioning of `postinstall/` per `docs/core/versioning.md`
- [ ] Write the decisions with their rationale in `postinstall/README.md`

### Test Environment
- [ ] Create a Fedora 45 Workstation VM (Beta or RC image) in virt-manager, on btrfs, with a clean-install snapshot to roll back to

---

## Technical Details

### Files to Modify
```
postinstall/README.md   (to be created)
```

### Dependencies
A Fedora 45 Beta or RC Workstation image for the VM.

### Constraints
- Code and documentation in English, per `CLAUDE.md`.
- The inventory holds personal data (dconf history, hostnames, device names): it stays outside the
  repository; only its location and a summary go in the report.

---

## Acceptance Criteria

- [ ] The inventory covers packages, Flatpaks, extensions, dconf, and `/etc` changes, and its location is recorded in the report
- [ ] Every architecture decision listed above is written in `postinstall/README.md` with its rationale
- [ ] The Fedora 45 VM boots to a fresh GNOME session and has a restorable snapshot
