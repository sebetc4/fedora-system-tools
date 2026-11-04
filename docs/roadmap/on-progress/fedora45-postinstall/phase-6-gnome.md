# Phase 6: GNOME

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/7)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-5-flatpaks.md` and `phase-5-flatpaks-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-6-gnome-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Restore the chosen GNOME extensions and settings as the desktop user.

---

## Overview

### Why This Phase Matters
Extensions and dconf settings are what makes the desktop feel like the old one, and they are the
part the old script never handled. Fedora 45 ships GNOME 51, which some extensions may not
support on release day.

### What It Enables
A desktop restored in one run plus a re-login.

### Out of Scope
Desktops other than GNOME: these steps are skipped when GNOME is not detected.

---

## Tasks

### Extensions
- [ ] Triage the 10 enabled extensions with the user: keep or drop
- [ ] Install the kept extensions that Fedora packages as RPMs (`dash-to-dock`, `blur-my-shell`, `user-theme`)
- [ ] Install the other kept extensions from extensions.gnome.org by UUID for the running GNOME Shell version, and report those not yet available for it
- [ ] Enable the extensions, handling the re-login needed by newly installed ones

### Settings
- [ ] Select from the phase 0 dconf dump the keys worth keeping (favorites, keyboard shortcuts, extension settings, Nautilus, Ptyxis, interface), excluding machine-specific and history keys
- [ ] Store the selected keys in the profile as one dconf keyfile per subtree
- [ ] Step `gnome-settings`: `dconf load` each subtree as the desktop user

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (gnome-extensions, gnome-settings)
postinstall/profiles/    (extension list, dconf keyfiles)
```

### Dependencies
Phase 1 root/user split; phase 0 dconf dump.

### Constraints
The profile's dconf files are committed: no personal data (recent files, history, hostnames,
device identifiers).

---

## Acceptance Criteria

- [ ] On the Fedora 45 VM, after the steps and a re-login, the kept extensions are enabled and the settings applied
- [ ] An extension without support for the running GNOME Shell version is reported, not fatal
- [ ] The profile's dconf files contain no personal data
- [ ] A second run changes nothing
