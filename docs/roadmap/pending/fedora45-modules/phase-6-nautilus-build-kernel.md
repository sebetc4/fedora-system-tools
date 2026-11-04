# Phase 6: Nautilus & Build-Kernel

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/7)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Settle the fate of `nautilus`, and turn `build-kernel` into a generic, dormant builder once Fedora's
own kernel serves the Legion 7's audio.

### Out of Scope
Adapting `build-kernel` to RPM signature enforcement, beyond the test and plan below.

---

## Tasks

### Nautilus
- [ ] Decide with the user whether `nautilus` stays GNOME-only, gains a Dolphin backend (`~/.local/share/user-places.xbel`) or goes, given its single recorded use
  Proof: medium, the user's decision recorded in the report
- [ ] Apply the decision and, if the module stays, review it against the checklist
  Proof: medium, use on the VMs concerned

### Build-Kernel
- [ ] Validate Fedora's own kernel 7.3 or later on the Legion 7: speakers and microphone, with the firmware installed, `CONFIG_SND_HDA_SCODEC_AW88399_I2C` enabled, no custom kernel and no `snd_intel_dspcfg.dsp_driver=3`
  Proof: high, use on the real machine — audio works after a cold boot and after a suspend
- [ ] Remove the `aw88399` hook and its install and cleanup scripts, once that validation passes
  Proof: medium, check — `build-kernel --help` and an install on a VM work without it
- [ ] Make the builder generic and fix the defects in `study/build-kernel.md` (untracked): work done in `/root`, `.unsigned` kernels left in `/boot`, the stale `SUPPORTED_KERNEL_MAJORS` default
  Proof: medium, a build with a trivial patch on Fedora 44, leaving no such residue
- [ ] Test on the Fedora 45 VM whether `dnf install` accepts a locally built unsigned RPM under signature enforcement, and write the result and the port's plan (signing with `rpm-setup-autosign`) in `docs/modules/build-kernel.md`, to be created
  Proof: medium, test — a dummy unsigned RPM on the VM
- [ ] Decide with the user whether akmods and `build-kernel` share one MOK key or enroll one each, and record it in the same page (moved from roadmap `fedora45-postinstall`, Phase 3)
  Proof: low, the user's decision in the page

---

## Technical Details

### Files to Modify
```
modules/nautilus/
modules/build-kernel/
docs/modules/nautilus.md
docs/modules/build-kernel.md   (to be created)
Makefile
```

### Dependencies
A Fedora kernel 7.3 or later, and the firmware step of roadmap `fedora45-postinstall`, Phase 3, or the
firmware already installed on the machine.

### Constraints
The `aw88399` hook stays until the validation on the real machine passes: it is what gives the Legion 7
its sound today.
