# Roadmaps

Written by the roadmap skill's `scripts/roadmaps.py` from each roadmap's README and phase files: change those, never this file.

---

## Order Of Execution

1. `fedora45-postinstall`, Phases 0 to 8: in progress
2. `fedora45-modules`, Phases 0 to 7: waits for roadmap `fedora45-postinstall`, Phase 0

---

## Open

| Roadmap | Description | State | Created |
|---|---|---|---|
| [`fedora45-postinstall`](on-progress/fedora45-postinstall/README.md) | Builds `postinstall/`, a generic, idempotent tool that brings a fresh Fedora 45 install to a deliberate target state from a chain of profiles, and uses it for the Legion 7's reinstall. | Phase 0 — Framing & Architecture | 2026-10-18 |
| [`fedora45-modules`](pending/fedora45-modules/README.md) | Reviews every fedora-system-tools module for Fedora 45: settles what stays, then optimizes, tests, secures and personalizes what does, validated on GNOME and KDE Plasma test VMs. | Not started | 2026-11-04 |

---

## Completed

None.
