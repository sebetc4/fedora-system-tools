# Roadmap: fedora45-modules

Reviews every fedora-system-tools module for Fedora 45: settles what stays, then optimizes, tests, secures and personalizes what does, validated on GNOME and KDE Plasma test VMs.

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
Phase 0  Framing & Test Harness     🟡 █░░░░░░░░░░░░░░░░░░░   0%  (0/8)
Phase 1  Shared Foundation          🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
Phase 2  Notifications              🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/5)
Phase 3  ClamAV                     🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/9)
Phase 4  Backup                     🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/7)
Phase 5  Torrent                    🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
Phase 6  Nautilus & Build-Kernel    🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/7)
Phase 7  Validation & Release       🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/4)
TOTAL                                  ░░░░░░░░░░░░░░░░░░░░   0%  (0/52)
```

**Current Phase:** Phase 0: Framing & Test Harness
**Blocked By:** —

---

## Why This Roadmap Exists

The repository review of 2026-11-04 found confirmed bugs (`quarantine list` and `purge` and
`clamav-manage diagnose` abort under `set -e`), a USB scanner that never scanned (all 11 insertions
since 2026-10-07 timed out), documentation that is wrong on a fresh install, and no test at all.
The usage inventory made the same day shows that several modules are hardly used. The user wants
every module kept to be reviewed, optimized, tested, secured and personalized, then validated on
VMs, on Fedora 45.

---

## Decisions Taken At Opening

- `torrent`, `notifications` and `backup` stay, every `backup` submodule included: `hdd-both` is not
  used today but may be.
- ClamAV stays, refocused on where files enter the machine: downloads, finished torrents, USB drives
  and on-demand scans. The daily scan goes, the weekly one shrinks to the user's data, `clamd` runs
  on demand instead of holding 1.2 GB permanently, and community signatures are added. The engine
  works (it detects EICAR); no positive in months is expected on Linux, and the files worth checking
  are those that may reach the user's Windows VMs.
- The `firewall` module goes: its hardening is real but applied once, so it becomes a declarative
  step in roadmap `fedora45-postinstall`, Phase 7.
- `build-kernel` stays generic and dormant: useful to test a hardware fix before Fedora ships it. Its
  `aw88399` hook goes once Fedora's kernel 7.3 is validated on the Legion 7, and its adaptation to
  Fedora 45's RPM signature enforcement waits for its first real need.
- `nautilus` is settled in Phase 6: it is GNOME-only and was used once.
- Every kept module works on GNOME and on KDE Plasma, preferably by removing the dependency on the
  desktop rather than by writing two versions.
- One review checklist, written in Phase 0, applies to every module; each phase's proof comes from
  tests and from the VMs.
- Repository conventions apply, no migration code included.

---

## Deliberately Out Of Scope

- `postinstall/` and the Fedora 45 reinstall (roadmap `fedora45-postinstall`).
- The `firewall` step and the Legion 7's audio firmware step (roadmap `fedora45-postinstall`).
- Adapting `build-kernel` to RPM signature enforcement, beyond a test and a written plan.
- New modules, such as the ideas under `notes/` (untracked).

---

## Phases

- [Phase 0: Framing & Test Harness](phase-0-framing-test-harness.md) — review checklist, personal settings policy, `bats` tests, VM harness, complete lint
- [Phase 1: Shared Foundation](phase-1-shared-foundation.md) — `lib/`, `setup.sh`, installers, bootstrap prerequisites, release path
- [Phase 2: Notifications](phase-2-notifications.md) — daemon and manager review, log volume, both desktops
- [Phase 3: ClamAV](phase-3-clamav.md) — bug fixes, refocus on entry points, working USB scanner, `clamd` on demand
- [Phase 4: Backup](phase-4-backup.md) — every submodule reviewed with a restore proof, `vps` independent of the desktop's SSH agent
- [Phase 5: Torrent](phase-5-torrent.md) — review, VPN kill switch, secrets, Podman 6, scan integration
- [Phase 6: Nautilus & Build-Kernel](phase-6-nautilus-build-kernel.md) — fate of `nautilus`, generic builder, `aw88399` hook removed
- [Phase 7: Validation & Release](phase-7-validation-release.md) — `firewall` module removed, every module on both VMs, documentation, release

---

## Dependencies

- The two Fedora 45 test VMs (roadmap `fedora45-postinstall`, Phase 0), ready on 2026-11-06, for
  this roadmap's Phase 0 onward.
- A Fedora kernel 7.3 or later, expected within weeks, for Phase 6's validation on the Legion 7.
- The `firewall` step (roadmap `fedora45-postinstall`, Phase 7), before Phase 7 removes the module.

---

## Related Documentation

- [Repository conventions](../../../core/conventions.md)
- [Versioning rules](../../../core/versioning.md)
- [Shared library overview](../../../lib/overview.md)

---

## Metadata

**Roadmap Status:** 🟡 In Progress
**Created:** 2026-11-04
