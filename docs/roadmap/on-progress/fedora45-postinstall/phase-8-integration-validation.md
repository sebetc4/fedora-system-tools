# Phase 8: Integration & Validation

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-7-system-settings.md` and `phase-7-system-settings-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-8-integration-validation-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Validate the whole tool on a fresh VM, then use it for the real Fedora 45 reinstall.
fedora-system-tools is installed on its own, with `make` or `setup.sh`, not by a post-install step.

---

## Overview

### Why This Phase Matters
Each step has been tested on its own. Only a full run on a fresh system, then the real reinstall,
shows what is still missing or still manual.

### What It Enables
The real machine on Fedora 45 with the `legion-7` profile applied, and a tool other Fedora installs
can use.

### Out of Scope
The installation itself (Anaconda, partitioning, LUKS).

---

## Tasks

### Bootstrap
- [ ] Document the bootstrap from a fresh install: clone the repository, then run `postinstall.sh`

### Validation
- [ ] Run the full tool on a fresh Fedora 45 VM snapshot, then run it a second time to confirm nothing changes
- [ ] Run it on the real machine after the Fedora 45 release, on a fresh install that keeps the `code`, `vm`, and `ai` subvolumes and `/data`
- [ ] Record what had to be done by hand during the real install, and turn what can be automated into steps

### Wrap-Up
- [ ] Write the user documentation in `postinstall/README.md`: usage, profiles, steps, adding a step
- [ ] Decide with the user whether to delete `study/fedora-config` or keep it as an archive

---

## Technical Details

### Files to Modify
```
postinstall/README.md
```

### Dependencies
Fedora 45 general availability (released on 2026-11-03) for the real-machine run.

build-kernel working on Fedora 45 (locally built RPMs installable under RPM signature
enforcement, kernel signed for Secure Boot): the Legion 7's audio needs its custom kernel, so the
real-machine run waits for it. That adaptation stays outside this roadmap.

### Constraints
Back up before the real install; the `restore-system` tooling stays within reach.

---

## Acceptance Criteria

- [ ] A fresh Fedora 45 VM reaches the target state with `postinstall.sh` plus the documented manual steps (fedora-system-tools install, MOK enrollment, re-login)
- [ ] The real machine runs Fedora 45 with the `legion-7` profile applied and `nvidia-smi` working with Secure Boot enabled
- [ ] `make shellcheck` passes
