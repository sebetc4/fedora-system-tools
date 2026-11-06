# Roadmap: fedora45-postinstall

Builds `postinstall/`, a generic, idempotent tool that brings a fresh Fedora 45 install to a
deliberate target state from a chain of profiles, and uses it for the Legion 7's reinstall.

---

## Status Indicators

- 🔴 Not Started
- 🟡 In Progress
- 🟢 Done
- ⏸️ Blocked
- ⚠️ Needs Review

---

## Overall Progress

```
Phase 0  Framing & Architecture     🟢 ████████████████████ 100%  (16/16)
Phase 1  Core Framework             🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/14)
Phase 2  Repositories & Multimedia  🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/9)
Phase 3  NVIDIA & Hardware          🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/8)
Phase 4  Packages                   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/8)
Phase 5  Flatpaks                   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
Phase 6  Desktop                    🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/12)
Phase 7  System Settings            🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
Phase 8  Integration & Validation   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
TOTAL                                  ████░░░░░░░░░░░░░░░░  19%  (16/85)
```

**Current Phase:** —
**Blocked By:** roadmap `review-skill`

---

## Why This Roadmap Exists

The Fedora 45 release is the occasion for a clean reinstall of the workstation. The existing
post-install script, `study/fedora-config/fedora43-setup.sh`, covers a small fraction of the real
configuration (2 of 26 Flatpaks, 2 of about 120 explicitly installed packages, no NVIDIA driver, no
GNOME settings). It also carries four defects: removals never run under DNF5, the `countme`
setting is ignored, the run aborts on the first package failure, and package installs are
all-or-nothing. Finally, it repeats work Fedora now does by default.

This roadmap replaces it with a generic, idempotent post-install tool that brings a fresh Fedora
install to a deliberate, minimal target state, with a personal profile layer shared by the user's
machines and one profile per machine: `legion-7` for this workstation, `legion-5` for a second
laptop.

---

## Decisions Taken At Opening

- Rewrite from scratch in `postinstall/` at the repository root, versioned with the repository.
  `study/fedora-config/` (ignored by git) is reference material only.
- Generic tool with profiles: generic defaults plus a personal profile for this workstation.
  Hardware-dependent steps decide from detection (GPU vendors, Secure Boot, btrfs, desktop), never
  from hard-coded assumptions.
- Targets: Fedora 45 Workstation (GNOME) and Fedora 45 KDE Plasma Desktop, both tested, DNF5
  only. Detection chooses the desktop steps; on any other desktop they are skipped. Changed on
  2026-11-04 from Workstation alone: the owner's two laptops may run different desktops, and VMs
  of either desktop are used with the owner's configuration.
- Only what is needed: packages, Flatpaks, and extensions are triaged with the user, never
  imported in bulk from the old system.
- The old script's defects are design requirements, not patches: `dnf remove` instead of
  `dnf autoremove <pkg>`, `countme` set per repository, a failed step never stops the run,
  installs use `--skip-unavailable`, logs go to a persistent location, Flathub is ensured.
- Not carried over: `dnf-utils` (replaced by `dnf needs-restarting`), `installonly_limit` (the
  default), the pigz/lbzip2 symlinks in `/usr/local/bin`, the hand-picked GStreamer list (replaced
  by the RPM Fusion `@multimedia` procedure), the duplicate `gnome-extensions-app` RPM,
  `--nogpgcheck`, `fastestmirror`, `deltarpm`, `qgnomeplatform`.
- Fedora 45 constraints: signed installs only (RPM signature enforcement); packaged repository
  files are never edited, options go through `dnf config-manager`.
- Repository conventions from `CLAUDE.md` apply: English, script header, strict mode, `[[ ]]`,
  reuse of `lib/`.
- Every step is validated in a Fedora 45 VM before the real install.

---

## Deliberately Out Of Scope

- The installation itself: Anaconda, partitioning, LUKS, kickstart.
- Dotfiles (`~/.bashrc`, `~/.gitconfig`, `~/.ssh`).
- Adapting `build-kernel` to Fedora 45's RPM signature enforcement: deferred to its first real
  need (roadmap `fedora45-modules`). The Legion 7's audio comes from Fedora's kernel 7.3 or later.
- The review of the fedora-system-tools modules (roadmap `fedora45-modules`). Only the
  replacement of the `firewall` module by a step is here, in phase 7.
- An "export the current system to a profile" command: the inventory is a one-off in phase 0.
- Migrating GNOME Keyring secrets to oo7, the Fedora 45 Secret Service provider.
- Fedora Atomic desktops and spins other than Workstation and KDE Plasma Desktop as tested
  targets.
- Running the tool on the Legion 5: its `legion-5` profile is created, but its real run comes after
  this roadmap. Only the Legion 7 and the test VM are validated here.

---

## Phases

- [Phase 0: Framing & Architecture](phase-0-framing-architecture.md) — inventory of the Fedora 44 machine, design of `postinstall/`, Fedora 45 test VMs (GNOME and KDE Plasma)
- [Phase 1: Core Framework](phase-1-core-framework.md) — runner, helpers, logging, dry-run, root/user split, `dnf-config` step
- [Phase 2: Repositories & Multimedia](phase-2-repositories-multimedia.md) — third-party and RPM Fusion repositories with signed installs, extra repositories, full multimedia stack, hardware video acceleration
- [Phase 3: NVIDIA & Hardware](phase-3-nvidia-hardware.md) — NVIDIA driver with Secure Boot key enrollment, kernel arguments, the Legion 7's audio firmware, firmware report
- [Phase 4: Packages](phase-4-packages.md) — triage of the explicitly installed packages, package list format and step
- [Phase 5: Flatpaks](phase-5-flatpaks.md) — triage of the Flatpak apps, remote policy, Flatpak step
- [Phase 6: Desktop](phase-6-desktop.md) — GNOME extensions and dconf settings, KDE Plasma settings and panel layout
- [Phase 7: System Settings](phase-7-system-settings.md) — firewall, tuned, snapper, btrfsmaintenance, owner for every modified `/etc` file
- [Phase 8: Integration & Validation](phase-8-integration-validation.md) — full runs on both VMs, real Fedora 45 reinstall, bootstrap and user documentation

---

## Dependencies

- Roadmap `review-skill`, before Phase 1: every phase that changes code ends with the review
  of its diff, which that roadmap builds.
- Fedora 45 final release images for the test VMs (phase 0 onward): Workstation and KDE Plasma
  Desktop, in `/vm/iso`.
- Fedora 45 general availability, reached on 2026-11-03, for the real-machine run (phase 8).
- A Fedora kernel 7.3 or later for the Legion 7's audio (phase 8): the AW88399 driver is in
  mainline from 7.3 on, provided Fedora enables `CONFIG_SND_HDA_SCODEC_AW88399_I2C`.
- NVIDIA and Secure Boot behavior can only be validated on the real hardware (phases 3 and 8).

---

## Related Documentation

- [Repository conventions](../../../core/conventions.md)
- [Versioning rules](../../../core/versioning.md)
- [Shared library overview](../../../lib/overview.md)

---

## Metadata

**Roadmap Status:** 🟡 In Progress
**Created:** 2026-10-18
