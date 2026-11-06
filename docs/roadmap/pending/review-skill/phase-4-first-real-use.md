# Phase 4: First Real Use

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/3)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Review the code roadmap `fedora45-modules` delivered in its Phases 0 and 1 with the skill, on its
diff by hunk: one report written by the report writer, its findings verified and triaged, the hard
cases put to the user, a fix plan for Phase 5.

### Out of Scope
The fixes, which Phase 5 makes. A full review of the repository.

---

## Tasks

### Review
- [ ] Review `52fa84f..befea3f` by hunk — the library, `setup.sh`, the installers, the tests and the VM harness —: one go-ahead with its tier and agents counted, the checks run, the reviewers and the verifiers
  Proof: high, run — each agent's answer accepted by `findings.py add`; the report and the register written

### Triage
- [ ] Give the clear verdicts, put the hard cases to the user, and write the fix plan; a finding on a module's code outside the scope's items routed to that module's phase of roadmap `fedora45-modules`
  Proof: medium, every finding with a verdict and an action; the user's answer on each hard case

### The Skill In Use
- [ ] Record each failure of the skill seen in this use in its evals' `failures_in_use`, with its source, and fix it at the line that let it through
  Proof: medium, static audit clean after each fix

---

## Technical Details

### Files to Modify
```
the review's folder, where Phase 0 placed the reviews
the skill's folder and its agents
phase files of roadmap fedora45-modules, for the findings routed there
```

### Dependencies
Phase 3: the skill evaluated. The two Fedora 45 test VMs, for the probes the user accepts.

### Constraints
No agent runs a command that changes the machine; a run on a VM is a `PROBE`, made by the session
from the VM's snapshot on the user's word.
