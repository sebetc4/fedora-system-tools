# Roadmap: fedora45-postinstall

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
Phase 0  Framing & Architecture     🟡 █░░░░░░░░░░░░░░░░░░░   0%  (0/15)
Phase 1  Core Framework             🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/13)
Phase 2  Repositories & Multimedia  🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/9)
Phase 3  NVIDIA & Hardware          🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/7)
Phase 4  Packages                   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/8)
Phase 5  Flatpaks                   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
Phase 6  GNOME                      🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/7)
Phase 7  System Settings            🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/5)
Phase 8  Integration & Validation   🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/7)
TOTAL                                  ░░░░░░░░░░░░░░░░░░░░   0%  (0/77)
```

**Current Phase:** Phase 0 — Framing & Architecture
**Blocked By:** —
**Next Milestone:** Phase 0 — Framing & Architecture

---

## Why This Roadmap Exists

The Fedora 45 release is the occasion for a clean reinstall of the workstation. The existing
post-install script, `study/fedora-config/fedora43-setup.sh`, covers a small fraction of the real
configuration (2 of 26 Flatpaks, 2 of about 120 explicitly installed packages, no NVIDIA driver, no
GNOME settings). It also carries four defects: removals never run under DNF5, the `countme`
setting is ignored, the run aborts on the first package failure, and package installs are
all-or-nothing. Finally, it repeats work Fedora now does by default.

This roadmap replaces it with a generic, idempotent post-install tool that brings a fresh Fedora
install to a deliberate, minimal target state, with a personal profile for this workstation.

---

## Decisions Taken At Opening

- Rewrite from scratch in `postinstall/` at the repository root, versioned with the repository.
  `study/fedora-config/` (ignored by git) is reference material only.
- Generic tool with profiles: generic defaults plus a personal profile for this workstation.
  Hardware-dependent steps decide from detection (GPU vendors, Secure Boot, btrfs, desktop), never
  from hard-coded assumptions.
- Target: Fedora 45 Workstation (GNOME), DNF5 only. GNOME steps are skipped on other desktops.
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
- Adapting `build-kernel` to Fedora 45's RPM signature enforcement: locally built kernel and
  `kmod-nvidia` packages installed with `--nogpgcheck` will be refused. This is separate work, to
  do before using the custom kernel on Fedora 45.
- An "export the current system to a profile" command: the inventory is a one-off in phase 0.
- Migrating GNOME Keyring secrets to oo7, the Fedora 45 Secret Service provider.
- Fedora Atomic desktops and non-GNOME spins as tested targets.

---

## Phases

- 🟡 [Phase 0: Framing & Architecture](phase-0-framing-architecture.md) — inventory of the Fedora 44 machine, design of `postinstall/`, Fedora 45 test VM
- 🔴 [Phase 1: Core Framework](phase-1-core-framework.md) — runner, helpers, logging, dry-run, root/user split, `dnf-config` step
- 🔴 [Phase 2: Repositories & Multimedia](phase-2-repositories-multimedia.md) — third-party and RPM Fusion repositories with signed installs, extra repositories, full multimedia stack, hardware video acceleration
- 🔴 [Phase 3: NVIDIA & Hardware](phase-3-nvidia-hardware.md) — NVIDIA driver with Secure Boot key enrollment, kernel arguments, firmware report
- 🔴 [Phase 4: Packages](phase-4-packages.md) — triage of the explicitly installed packages, package list format and step
- 🔴 [Phase 5: Flatpaks](phase-5-flatpaks.md) — triage of the Flatpak apps, remote policy, Flatpak step
- 🔴 [Phase 6: GNOME](phase-6-gnome.md) — extension triage and install, dconf settings
- 🔴 [Phase 7: System Settings](phase-7-system-settings.md) — tuned, snapper, btrfsmaintenance, owner for every modified `/etc` file
- 🔴 [Phase 8: Integration & Validation](phase-8-integration-validation.md) — fedora-system-tools install step, full VM run, real Fedora 45 reinstall, documentation

---

## Dependencies

- Fedora 45 Beta or RC image for the test VM (phase 0 onward).
- Fedora 45 general availability, scheduled for 2026-10-27, for the real-machine run (phase 8).
- NVIDIA and Secure Boot behavior can only be validated on the real hardware (phases 3 and 8).

---

## Related Documentation

- [Repository conventions](../../../core/conventions.md)
- [Versioning rules](../../../core/versioning.md)
- [Shared library overview](../../../lib/overview.md)
- [Project instructions](../../../../CLAUDE.md)

---

## Metadata

**Roadmap Status:** 🔴 Not Started
**Location:** `docs/roadmap/pending/fedora45-postinstall/`
**Version:** 1.0.0
**Created:** 2026-10-18
**Last Updated:** 2026-10-18

---

## Changelog

### 1.0.0 (2026-10-18)

Roadmap created with 9 phases: framing and architecture, core framework, repositories and
multimedia, NVIDIA and hardware, packages, Flatpaks, GNOME, system settings, integration and
validation.
