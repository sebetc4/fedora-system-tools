# Phase 5: Flatpaks

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-4-packages.md` and `phase-4-packages-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-5-flatpaks-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Triage the 26 installed Flatpak apps into a deliberate list with a declared origin per app, and
install it.

---

## Overview

### Why This Phase Matters
Four apps currently come from the Fedora remote and the rest from Flathub, without a deliberate
choice. Some apps duplicate RPMs, such as the GNOME Extensions app.

### What It Enables
A reproducible app set with a clear remote policy.

### Out of Scope
App data and settings inside `~/.var/app`.

---

## Tasks

### Triage
- [ ] Classify the 26 installed apps into keep, drop, and to-decide, and review them with the user
- [ ] Decide the remote policy: Flathub only, or the Fedora remote allowed per app
- [ ] Remove duplicates between RPMs and Flatpaks (GNOME Extensions app, Extension Manager)

### Implementation
- [ ] Define the list format with the origin per app (`remote:app.id`)
- [ ] Step `flatpaks`: install the missing apps from their declared remote, remove the listed apps, then `flatpak uninstall --unused`
- [ ] Per-app permission overrides from the profile (`flatpak override`), when the profile declares any

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (flatpaks)
postinstall/profiles/    (Flatpak lists)
```

### Dependencies
Phase 2 `flatpak-remotes` step.

### Constraints
Every app of the personal list is approved by the user and declares its remote.

---

## Acceptance Criteria

- [ ] Every app in the personal list was approved by the user and declares its remote
- [ ] On the Fedora 45 VM, the step installs the list, reports an unknown app id without failing, and a second run changes nothing
