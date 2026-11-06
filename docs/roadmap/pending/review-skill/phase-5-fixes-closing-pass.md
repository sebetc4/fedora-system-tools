# Phase 5: Fixes & Closing Pass

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Fix Phase 4's findings by the fix method, then end the cycle by its stopping rule: one closing pass
on the roadmap's diff, the recorded mutants run again, that pass's findings fixed or registered,
and no pass after. Then make the review a step of every phase that changes code in the two open
roadmaps.

### Out of Scope
A further review after the closing pass's fixes. The findings left in the debt register.

---

## Tasks

### Fixes
- [ ] Fix the findings above the floor, one batch per commit: the reproduction seen failing first, the sibling paths and the input class named, the mutants applied by hand and recorded, the whole record run after each batch, the checks green and the VM harness passing on both VMs where the batch touches what it checks
  Proof: high, test — each batch's entry in the report: its red test, its mutants, the checks
- [ ] Record each failure of the fix method seen in these fixes in the evals' `failures_in_use`, and fix it at the line that let it through
  Proof: medium, static audit clean after each fix

### Closing Pass
- [ ] Run the closing pass on the roadmap's diff — the security reviewer alone and the recorded mutants again —; fix what bears on the fixes or is medium or worse, register the rest, and run no pass after
  Proof: high, run — the pass's report; the regression run, every recorded mutant caught

### Adoption
- [ ] Declare the review at a phase's close and the closing pass at a roadmap's close as `closing_tasks` in `.agent-conventions.toml`, and add the closing task to each phase not done that changes code in roadmaps `fedora45-postinstall` and `fedora45-modules`
  Proof: medium, check — `conventions.py roadmap` prints the entries; `progress.py --check` clean on both roadmaps
- [ ] Write the review's page in `docs/core/` — its moments, where its records live, how a finding is fixed or registered — and link it from `docs/core/README.md` and the checklist
  Proof: low, the documentation check clean; the page read against the skill
- [ ] Write `shared-and-specific.md` in this roadmap's folder: what of the skill holds for any repository and what is this repository's, from Phase 0's decisions and this cycle's use
  Proof: low, the user's review

---

## Technical Details

### Files to Modify
```
lib/, setup.sh, install.sh, uninstall.sh, tests/ — as the batches require
the review's folder, the debt register, the recorded mutants
the skill's folder and its agents
.agent-conventions.toml
docs/core/
phase files of roadmaps fedora45-postinstall and fedora45-modules
```

### Dependencies
Phase 4: the report, its fix plan and the user's answers on the hard cases.

### Constraints
A fix that changes what a user sees or what a module installs is bumped per the versioning rules.
No pass follows the closing pass.
