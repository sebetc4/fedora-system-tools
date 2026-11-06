# Phase 1: Core Framework

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/14)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Before Starting This Phase

Read `phase-0-framing-architecture.md` and `phase-0-framing-architecture-report.md` in full before
touching anything here: the decisions already taken, the problems and
deviations recorded, and the changes made to this phase.

---

## While Working

Keep `phase-1-core-framework-report.md` current as the work happens — after each significant
step, and before every commit, pause, or end of session.

---

## Objective

Implement the runner every step plugs into, the shared helpers, and the first real step (DNF
configuration), with the defects of the old script designed out.

---

## Overview

### Why This Phase Matters
Every later phase adds steps. The runner settles once how steps are selected, logged, dry-run,
run as root or as the desktop user, and how a failure is handled.

### What It Enables
Phases 2 to 8 add steps without touching the framework.

### Out of Scope
Repositories (phase 2) and package lists (phase 4).

---

## Tasks

### Entry Point & Runner
- [ ] Create `postinstall/postinstall.sh` with `--profile`, `--only <step,...>`, `--skip <step,...>`, `--list`, `--dry-run`, `--help`
- [ ] Implement step discovery and ordering from the steps folder
- [ ] Implement the root/user split decided in phase 0: one invocation, user steps run as the desktop user with access to the session bus
- [ ] Implement per-step failure handling: a failed step is reported and the run continues; the final summary lists ok, changed, failed, and skipped steps; non-zero exit when a step failed
- [ ] Implement timestamped logging to a persistent location (not `/tmp`)
- [ ] Implement preflight checks: Fedora release, minimum version (dry-run allowed on an older release for testing), network reachability, not running from a Live session

### Shared Helpers
- [ ] Package helpers: install in one transaction with `--skip-unavailable`, remove with `dnf remove`, no `rpm -q` pre-check
- [ ] Repository option helper built on `dnf config-manager setopt`, never editing `.repo` files
- [ ] Reboot detection with `dnf needs-restarting`, without `dnf-utils`
- [ ] Hardware detection helpers implementing the phase 0 rules

### First Step
- [ ] Step `dnf-config`: set `max_parallel_downloads` and `defaultyes` from the profile; disable `countme` per repository with `setopt` when the profile asks for it; no `installonly_limit`, `fastestmirror`, or `deltarpm`

### Tooling & Profiles
- [ ] Check that `make shellcheck` lints the `postinstall/` scripts, which it picks up on its own since roadmap `fedora45-modules`, Phase 0
- [ ] Declare `POSTINSTALL_VERSION` (`0.1.0`) in `postinstall.sh`, and add `postinstall/` to `docs/core/versioning.md` as a component outside the release tarball, which needs no project bump
- [ ] Create the profile chain `default` → `personal` → machine (`legion-7`, `legion-5` skeletons), loaded through each `profile.conf`'s `PARENT`, with cycle and missing-parent errors, desktop-specific content (`packages.<desktop>.list`, `flatpaks.<desktop>.list`, `gnome/`, `kde/`) loaded only when the detected desktop matches

---

## Technical Details

### Files to Modify
```
postinstall/postinstall.sh        (to be created)
postinstall/steps/                (to be created)
postinstall/profiles/             (to be created)
```

### Dependencies
The phase 0 architecture decisions in `postinstall/README.md`.

### Constraints
- Repository conventions from `CLAUDE.md`: script header, `set -euo pipefail`, `[[ ]]`, `C_*` colors.
- Under `set -e`, a helper's failure must never abort the run: failures are caught at the step boundary.

---

## Acceptance Criteria

- [ ] `make shellcheck` passes
- [ ] On both Fedora 45 VMs, `postinstall.sh --dry-run` shows the detected desktop and lists the intended actions without changing the system
- [ ] A real run of `dnf-config` is idempotent: the second run reports no change
- [ ] With `countme` disabled in the profile, the Fedora repositories report `countme` off as libdnf5 resolves it, not only in `[main]`
- [ ] A deliberately failing step does not stop the run and appears in the summary
- [ ] None of the old script's defects remains: `dnf autoremove <pkg>`, `countme` in `[main]`, abort on the first package failure, all-or-nothing install batch, log in `/tmp`
