# Phase 0: Framing & Test Harness

---

## Status

**Current Status:** 🟡 In Progress (0% — 0/8)
**Started:** 2026-11-06
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Set the standard every module is reviewed against and the tools that prove it: a review checklist,
a policy for personal settings, unit tests, a VM harness, and complete lint coverage.

### Out of Scope
Reviewing any module (phases 1 to 6).

---

## Tasks

### Review Standard
- [ ] Write the module review checklist in `docs/core/module-review.md`: correctness, optimization, tests, security (root boundaries, quoting, temporary files, secrets, systemd hardening), personalization, documentation and VM validation, each with what passing means
  Proof: medium, the user's review of the checklist
- [ ] Add to `docs/core/conventions.md` the rules the repository review showed missing, starting with counters under `set -e` (`((n++))` from 0 aborts the script)
  Proof: low, the rule read beside its reproduction command
- [ ] Decide with the user where personal settings live (module config files, the ignored `my-config/`, the postinstall `personal` profile) and what the public repository must never hold
  Proof: medium, the user's decision recorded in the report

### Tests
- [ ] Add `bats` tests under `tests/` with a `make test` target, starting with `version_compare` from `lib/registry.sh`
  Proof: medium, test — a test watched failing on a deliberately wrong comparison, then passing
- [ ] Write the VM harness under `tests/vm/`: restore a VM's snapshot, copy the checkout, run a module's install, its checks, a second install and its uninstall, and report per desktop
  Proof: medium, a run on both VMs for one module, a deliberately failing check reported as failed

### Lint And CI
- [ ] Replace the Makefile's hand-written `shellcheck` list with `git ls-files '*.sh'`, which adds the 11 scripts it misses
  Proof: medium, check — `make shellcheck` passes, and fails on a deliberately bad new script
- [ ] Run CI's ShellCheck at the local version instead of Ubuntu's, and add `make test` to CI
  Proof: medium, a green CI run on GitHub
- [ ] Declare `checks` in `.agent-conventions.toml`, on the user's agreement (`make shellcheck`, `make test`), so that each phase closure runs them
  Proof: low, check — `conventions.py roadmap` prints them

---

## Technical Details

### Files to Modify
```
docs/core/module-review.md   (to be created)
docs/core/conventions.md
tests/                       (to be created)
Makefile
.github/workflows/ci.yml
.agent-conventions.toml
```

### Dependencies
The two Fedora 45 VMs of roadmap `fedora45-postinstall`, Phase 0, with their `clean-install` snapshots.

### Constraints
- The harness acts on the test VMs only, never on the host.
- It keeps the `clean-install` snapshots intact: what it needs in a VM, such as SSH or the guest
  agent, goes in a snapshot of its own.
