# Phase 4: Packages

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/8)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-3-nvidia-hardware.md` and `phase-3-nvidia-hardware-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-4-packages-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Turn the roughly 120 explicitly installed packages of the Fedora 44 machine into a short,
deliberate package list per profile, and install it.

---

## Overview

### Why This Phase Matters
The point of the reinstall is a clean system with only what is needed. Importing the old list in
bulk would carry over Live-image leftovers, one-off build dependencies, and packages Fedora 45
removes.

### What It Enables
A reproducible package set, and a generic default list other machines can start from.

### Out of Scope
Flatpaks (phase 5) and GNOME extensions packaged as RPMs (phase 6).

---

## Tasks

### Triage
- [ ] Classify the phase 0 package inventory into keep, drop, and to-decide, by category (development, kernel build, Fedora packaging, virtualization, storage, security, CLI tools, desktop)
- [ ] Review the to-decide items with the user, one category at a time
- [ ] Drop the Live-image leftovers (`anaconda-live`, `livesys-scripts`, `dracut-live`), old `kmod-nvidia-*` packages, and `slirp4netns` (removed with Podman 6 in Fedora 45)
- [ ] Use a DNF group where one matches the need (for example `@virtualization`) instead of listing its members
- [ ] Decide, for each edition (Workstation, KDE Plasma Desktop), which of its default packages the personal profile removes

### Implementation
- [ ] Define the package list format: categories, comments, install and remove entries, groups, per-desktop lists
- [ ] Step `packages`: one install transaction with `--skip-unavailable`, one `dnf remove` transaction, unavailable names reported at the end
- [ ] Write the generic default list (minimal) and the personal lists, common and per desktop

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (packages)
postinstall/profiles/    (package lists)
```

### Dependencies
Phase 0 inventory; phase 2 repositories.

### Constraints
Every entry of the personal list is approved by the user; nothing is added in bulk.

---

## Acceptance Criteria

- [ ] Every package in the personal list has a category and was approved by the user
- [ ] On both Fedora 45 VMs, the step installs the lists, reports unavailable names without failing, and a second run changes nothing
- [ ] No listed package is already provided by the edition's default install or by a listed group
