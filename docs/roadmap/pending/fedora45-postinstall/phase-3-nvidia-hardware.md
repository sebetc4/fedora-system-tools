# Phase 3: NVIDIA & Hardware

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/7)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-2-repositories-multimedia.md` and `phase-2-repositories-multimedia-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-3-nvidia-hardware-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Install the proprietary NVIDIA driver on Secure Boot systems, apply profile-declared kernel
arguments, and report firmware updates.

---

## Overview

### Why This Phase Matters
The NVIDIA driver is the most fragile part of a reinstall: the akmods build must finish before a
reboot, and with Secure Boot enabled the module only loads once its signing key is enrolled, which
needs a confirmation at boot.

### What It Enables
A working GPU on the real machine, which phase 8 validates.

### Out of Scope
Building or signing a custom kernel (`build-kernel`), which Fedora 45's signature enforcement
affects separately.

---

## Tasks

### NVIDIA Driver
- [ ] Step `nvidia`: skipped unless an NVIDIA GPU is detected; installs `akmod-nvidia` and, per profile, `xorg-x11-drv-nvidia-cuda`
- [ ] Wait for the akmods build to finish and check the module version before reporting success
- [ ] Secure Boot: detect with `mokutil --sb-state`; when enabled, generate the akmods key (`kmodgenca`), queue its enrollment (`mokutil --import`), and print the boot-time enrollment instructions
- [ ] Check that the driver package added the `nouveau` and `nova_core` blacklist arguments, without adding them by hand

### Kernel & Firmware
- [ ] Step `kernel-args`: apply the profile's kernel arguments with `grubby --update-kernel=ALL --args` (personal profile: `snd_intel_dspcfg.dsp_driver=3`)
- [ ] Step `firmware`: `fwupdmgr refresh` and report the available updates, without flashing anything

### Personal Profile
- [ ] Decide with the user whether the CUDA toolkit, `gcc15`, and `nvidia-container-toolkit` belong to the personal profile, and record the decision in the report

---

## Technical Details

### Files to Modify
```
postinstall/steps/       (nvidia, kernel-args, firmware)
postinstall/profiles/    (personal profile: NVIDIA and kernel settings)
```

### Dependencies
Phase 2: the RPM Fusion nonfree repository.

### Constraints
- Secure Boot stays enabled; the step never suggests disabling it.
- MOK enrollment cannot be automated: the step prepares it and explains the reboot screen.

---

## Acceptance Criteria

- [ ] On the Fedora 45 VM (no NVIDIA GPU), the `nvidia` step is skipped with a clear message
- [ ] On the current Fedora 44 machine, `postinstall.sh --dry-run --only nvidia,kernel-args` detects the NVIDIA GPU and Secure Boot and lists the intended actions
- [ ] A second run of `kernel-args` leaves each argument present once in `grubby --info=ALL`

---

## Testing Strategy

The VM has no NVIDIA GPU: this phase is validated by the VM skip and the dry-run on the current
machine. The real install and `nvidia-smi` check happen in phase 8.
