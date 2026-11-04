# Phase 7: System Settings

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/5)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-6-gnome.md` and `phase-6-gnome-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-7-system-settings-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Apply the system-level settings that fedora-system-tools does not own: power profile, btrfs
snapshots, and btrfs maintenance.

---

## Overview

### Why This Phase Matters
The Fedora 44 machine carries settings changed by hand over time (tuned profile, snapper
configurations, btrfsmaintenance periods). Without a step, each one is forgotten or redone by hand.

### What It Enables
Every modified `/etc` file from the inventory ends with an owner: a step, a fedora-system-tools
module, or an explicit drop.

### Out of Scope
Files that fedora-system-tools modules install (clamav, backup, notifications, firewall).

---

## Tasks

### Steps
- [ ] Step `tuned`: set the profile's tuned profile (personal profile: `throughput-performance`); without a profile value, leave the Fedora default
- [ ] Step `snapper`: when the root filesystem is btrfs, create the `root` and `home` configurations with the profile's limits, and enable the timeline and cleanup timers
- [ ] Step `btrfsmaintenance`: install it and set the balance and scrub periods and mountpoints from the profile

### Decisions
- [ ] Assign an owner to each modified `/etc` file of the phase 0 inventory (step, fedora-system-tools module, or drop), and record it in the report
- [ ] Decide whether the user crontab entry (user logrotate) becomes a step or is left to fedora-system-tools

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (tuned, snapper, btrfsmaintenance)
postinstall/profiles/    (system settings)
```

### Dependencies
Phase 0 `/etc` inventory; phase 4 packages.

### Constraints
Steps skip cleanly when their precondition is absent (no btrfs root, no tuned).

---

## Acceptance Criteria

- [ ] On the Fedora 45 VM, the snapper configurations exist with their timers enabled, and the active tuned profile matches the profile
- [ ] Every modified `/etc` file from the inventory has an owner recorded in the report
- [ ] A second run changes nothing
