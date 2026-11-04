# Phase 2: Repositories & Multimedia

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/9)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-1-core-framework.md` and `phase-1-core-framework-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-2-repositories-multimedia-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Configure every package source and the full multimedia stack the way Fedora and RPM Fusion
document it, with signed installs only.

---

## Overview

### Why This Phase Matters
NVIDIA, packages, and Flatpaks all depend on the sources being right. Fedora 45 enforces RPM
signatures by default and moves packaged repository files to `/usr`, which breaks the old
script's `--nogpgcheck` install and any edit of `/etc/yum.repos.d`.

### What It Enables
Phases 3 to 5 install from sources that are already in place.

### Out of Scope
The NVIDIA driver itself (phase 3).

---

## Tasks

### Repositories
- [ ] Step `repos-third-party`: `fedora-third-party enable` (Chrome, NVIDIA driver, Steam, and PyCharm repositories, unfiltered Flathub)
- [ ] Step `repos-rpmfusion`: import the RPM Fusion keys shipped in `distribution-gpg-keys`, install the free and nonfree release packages with signature checking, install the appstream data; the tainted repository only when the profile asks for it
- [ ] Profile-declared extra repositories added with `dnf config-manager addrepo --from-repofile` (personal profile: VS Code, CUDA, nvidia-container-toolkit)
- [ ] Profile-declared repository options applied with `setopt` (personal profile: the CUDA `exclude=` list that keeps the RPM Fusion driver in place)
- [ ] Step `flatpak-remotes`: ensure Flathub exists (`--if-not-exists`) and apply the profile's policy for the Fedora remote
- [ ] One `dnf upgrade --refresh` once every repository is in place

### Multimedia
- [ ] Step `multimedia`: `dnf swap ffmpeg-free ffmpeg --allowerasing`, then `dnf update @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin`
- [ ] Hardware video acceleration by detected GPU: Intel swaps to `intel-media-driver`, AMD swaps to `mesa-va-drivers-freeworld`, NVIDIA installs `libva-nvidia-driver`
- [ ] `libdvdcss` from the tainted repository when the profile asks for it

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (new steps)
postinstall/profiles/    (repository and multimedia settings)
```

### Dependencies
Phase 1 runner and helpers.

### Constraints
- No `--nogpgcheck` or `--nosignature` anywhere in `postinstall/`.
- No step writes to `/etc/yum.repos.d/`; options go through `dnf config-manager`.
- The steps work on both editions: a tool or repository package that KDE Plasma Desktop does not
  ship by default, such as `fedora-third-party`, is installed by the step that needs it.

---

## Acceptance Criteria

- [ ] `grep` finds no `--nogpgcheck`, `--nosignature`, or write to `/etc/yum.repos.d/` in `postinstall/`
- [ ] On both Fedora 45 VMs, `ffmpeg -version` shows the RPM Fusion build and `gst-inspect-1.0 libav` lists H.264 and HEVC decoders
- [ ] On both VMs, the hardware acceleration step either installs the driver for the detected GPU or is skipped with a clear message
- [ ] A second run changes nothing

---

## Risk & Mitigation

- RPM Fusion release packages for Fedora 45 may lag on release day. The Fedora 45 RPM Fusion keys
  are already in `distribution-gpg-keys` (checked on Fedora 44); the step reports a missing
  release package instead of failing the run.
