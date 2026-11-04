# Phase 6: Desktop

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/12)
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

Keep `phase-6-desktop-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Restore the chosen desktop settings as the desktop user, on GNOME and on KDE Plasma.

---

## Overview

### Why This Phase Matters
Extensions and dconf settings are what makes the desktop feel like the old one, and they are the
part the old script never handled. Fedora 45 ships GNOME 51, which some extensions may not
support on release day. Plasma has no dconf: its settings are INI files under `~/.config`, and
its panel layout holds generated ids. Most of what the GNOME extensions add is native in Plasma.

### What It Enables
A desktop restored in one run plus a re-login, on either desktop, on a laptop
or a test VM.

### Out of Scope
Desktops other than GNOME and KDE Plasma: every desktop step is skipped on them.

---

## Tasks

### GNOME Extensions
- [ ] Triage the 10 enabled extensions with the user: keep or drop
- [ ] Install the kept extensions that Fedora packages as RPMs (`dash-to-dock`, `blur-my-shell`, `user-theme`)
- [ ] Install the other kept extensions from extensions.gnome.org by UUID for the running GNOME Shell version, and report those not yet available for it
- [ ] Enable the extensions, handling the re-login needed by newly installed ones

### GNOME Settings
- [ ] Select from the phase 0 dconf dump the keys worth keeping (favorites, keyboard shortcuts, extension settings, Nautilus, Ptyxis, interface), excluding machine-specific and history keys
- [ ] Store the selected keys in the profile as one dconf keyfile per subtree
- [ ] Step `gnome-settings`: `dconf load` each subtree as the desktop user

### KDE Plasma
- [ ] Configure Plasma once by hand on the KDE VM, starting from the native equivalents of the 9 enabled user GNOME extensions, and record in the report each equivalent and each extension without one
- [ ] Select from `~/.config` the keys worth keeping (`kdeglobals`, `kwinrc`, `kglobalshortcutsrc`, `kxkbrc`, `dolphinrc`, `konsolerc`, …), excluding machine-specific and history keys
- [ ] Store the selected keys in the profile's `kde/` folder, one INI fragment per config file
- [ ] Step `kde-settings`: apply each key with `kwriteconfig6` as the desktop user, check them with `kreadconfig6`, and report a needed re-login as a pending action
- [ ] Decide with the user whether the panel layout is scripted through Plasma's `evaluateScript` or left manual, and implement the choice

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (gnome-extensions, gnome-settings, kde-settings)
postinstall/profiles/    (extension list, dconf keyfiles, Plasma settings)
```

### Dependencies
Phase 1 root/user split; phase 0 dconf dump; the KDE VM for the Plasma settings.

### Constraints
The profile's dconf and Plasma files are committed: no personal data (recent files, history, hostnames,
device identifiers).

---

## Acceptance Criteria

- [ ] On the GNOME VM, after the steps and a re-login, the kept extensions are enabled and the settings applied
- [ ] On the KDE VM, after the steps and a re-login, the Plasma settings are applied
- [ ] Each VM skips the other desktop's steps with a clear message
- [ ] An extension without support for the running GNOME Shell version is reported, not fatal
- [ ] The profile's dconf and Plasma files contain no personal data
- [ ] A second run changes nothing on either VM
