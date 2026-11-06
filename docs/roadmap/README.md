# Roadmaps

Written by the roadmap skill's `scripts/roadmaps.py` from each roadmap's README and phase files: change those, never this file.

---

## Order Of Execution

1. `review-skill`, Phases 0 to 5: ready
2. `fedora45-postinstall`, Phases 1 to 8: waits for roadmap `review-skill`
3. `fedora45-modules`, Phases 2 to 7: waits for roadmap `review-skill`

---

## Open

| Roadmap | Description | State | Created |
|---|---|---|---|
| [`fedora45-postinstall`](on-progress/fedora45-postinstall/README.md) | Builds `postinstall/`, a generic, idempotent tool that brings a fresh Fedora 45 install to a deliberate target state from a chain of profiles, and uses it for the Legion 7's reinstall. | Phase 1: Core Framework, next | 2026-10-18 |
| [`fedora45-modules`](on-progress/fedora45-modules/README.md) | Reviews every fedora-system-tools module for Fedora 45: settles what stays, then optimizes, tests, secures and personalizes what does, validated on GNOME and KDE Plasma test VMs. | Phase 2: Notifications, next | 2026-11-04 |
| [`review-skill`](pending/review-skill/README.md) | Builds the review of delivered code — agents independent of the writing session reviewing each phase's diff by hunk at its close, and one closing pass per roadmap, in a review-and-fix cycle that ends —, proven on the first two phases of roadmap `fedora45-modules`. | Not started | 2026-11-06 |

---

## Completed

None.
