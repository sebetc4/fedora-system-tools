# Phase 3: Evaluation

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/4)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Show that the skill removes the failures Phase 1 observed without adding others: the same cases
graded against the baseline, iterated until each failure is gone or recorded with its reason, the
description's trigger rates measured, and the skill judged by `skill-auditor`. The fix method is
proven in real use, by Phases 4 and 5.

### Out of Scope
A review of this repository's code, which Phase 4 makes.

---

## Tasks

### Runs
- [ ] Run the cases on the skill, each batch after the user's yes, the phase's-close case first
  Proof: high, run — every run ended, by `scripts/run.py --status`, its result recorded in the report
- [ ] Grade against the baseline, class each failure — skill, world, assertion, tool —, and fix it at its source, until the skill beats the baseline clearly and each failure left has its reason
  Proof: high, measure — `scripts/benchmark.py`' table for each iteration, the classes in `classes.json`

### Description And Audit
- [ ] Measure the description's trigger rates, and the rules skill's on the review requests, which must not trigger it
  Proof: high, measure — `scripts/triggers.py`' rates recorded in the report
- [ ] Have `skill-auditor` judge the skill and the rules skill, one pass each
  Proof: medium, review — `VERDICT: PASS` for each, or each point of a `FAIL` answered at its source

---

## Technical Details

### Files to Modify
```
the skill's folder and its agents
```

### Dependencies
Phase 2: the skill, its agents and its scripts.

### Constraints
A failed eval is classed before any change; no skill or assertion is bent around a gap of the
harness.
