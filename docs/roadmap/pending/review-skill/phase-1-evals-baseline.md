# Phase 1: Evals & Baseline

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/3)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Write the cases the skill must pass, run them without the skill, and turn each failure the runs
show into an assertion, so that Phase 2 writes only what answers them.

### Out of Scope
The skill, its agents and its scripts.

---

## Tasks

### Cases
- [ ] Build the fixture offline and test-first: a repository made from `main` before this roadmap, without the review skill and this roadmap's files, which hold the answer keys, and a fictitious phase of a few commits of Bash carrying planted defects of the classes this repository met, each commit passing `make shellcheck` and `make test`
  Proof: medium, test — the fixture builder's tests watched failing on their assertion, then passing; the checks green at each of the fixture's commits
- [ ] Write the cases Phase 0 planned, and the trigger queries: review requests and near requests that must not trigger, in equal numbers
  Proof: medium, `authoring-skills`' `scripts/workspace.py` validates `evals/evals.json` and its triggers

### Baseline
- [ ] Run the cases without the skill after the user's yes on the batch, grade the runs, class each failure, and write the assertions from the failures, each named after what it checks
  Proof: high, measure — every run ended, by `scripts/run.py --status`; the grading and the classes recorded in the report

---

## Technical Details

### Files to Modify
```
the skill's evals/ folder, where Phase 0 placed the skill
```

### Dependencies
Phase 0: the moments, the finding format, the evals' plan and the probes of the harness.

### Constraints
The fixture's planted defects never reappear as examples in the skill or its agents. Each paid
batch starts after the user's yes on its count and estimate.
