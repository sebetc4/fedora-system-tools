# Roadmap: review-skill

Builds the review of delivered code — agents independent of the writing session reviewing each phase's diff by hunk at its close, and one closing pass per roadmap, in a review-and-fix cycle that ends —, proven on the first two phases of roadmap `fedora45-modules`.

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
Phase 0  Design & Threat Model      🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/12)
Phase 1  Evals & Baseline           🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/3)
Phase 2  Scripts, Skill & Agents    🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/9)
Phase 3  Evaluation                 🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/4)
Phase 4  First Real Use             🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/3)
Phase 5  Fixes & Closing Pass       🔴 ░░░░░░░░░░░░░░░░░░░░   0%  (0/6)
TOTAL                                  ░░░░░░░░░░░░░░░░░░░░   0%  (0/37)
```

**Current Phase:** —
**Blocked By:** —

---

## Why This Roadmap Exists

Today the code a phase delivers is reviewed only by the session that wrote it, against the
[module review checklist](../../../core/module-review.md). The checklist's proofs are sound —
`make test`, `make shellcheck`, the VM harness —, but the author reviews their own work, and
reading alone misses things: in roadmap `fedora45-modules`, Phase 1 had to fix `lib/ui.sh`,
`lib/notify.sh` and `lib/registry.sh` again after they had been reviewed, because the harness and
a probe showed what reading had not.

Fourteen phases remain across the two open roadmaps, and roadmap `fedora45-postinstall` is about to
write a whole tool from scratch. Each phase that changes code should end with a review by agents
that did not write it, on that phase's diff alone, whose findings carry an effect and a floor, are
verified before they are fixed, and stop at one closing pass per roadmap instead of calling for the
next review.

Such a reviewer exists and was proven elsewhere through a full cycle of review, fixes and closing
pass. This roadmap ports it rather than designing one anew: what any repository shares is taken
over, what is specific to its first repository is replaced by this repository's own — its
language, its threat model, its tests, its commands. Its design, its decisions and its lessons are
read outside the repository, from the pointers in `notes/review-skill/reference.md` (untracked).

---

## Decisions Taken At Opening

- **Name:** `review-skill`. The skill's own name is set in Phase 0 by the skill naming rules.
- **Purpose:** a review at the close of each phase that changed code, on the phase's diff by hunk;
  one closing pass per roadmap; a full review only on request; no pass after the closing one, its
  fixes resting on their tests and their recorded mutants.
- **Port, not redesign:** the reference reviewer's workflow, finding format, floor, debt register,
  report writer, agents' rules, guard and fix method are taken over; Phase 0 decides each change
  this repository needs, each proposal resting on a figure of this repository or a probe.
- **Its scripts stay in Python,** ported and adapted rather than rewritten in Bash: they parse
  diffs, JSON and hook inputs, and the skill tooling they sit beside is Python.
- **A threat document before the skill:** the review's tier, its security axis and its severity
  anchors read a document saying who reaches what, which this repository lacks; Phase 0 writes it.
- **First real use:** roadmap `fedora45-modules`' Phases 0 and 1, from their start commit `52fa84f`
  to Phase 1's closure `befea3f` — the library, `setup.sh`, the installers, the tests and the VM
  harness, 46 files and 4,057 lines added outside `docs/` —, closed without an independent review.
  Their fixes and the closing pass are in this roadmap, since only a cycle that ends proves the
  stopping rule.
- **This roadmap runs first:** roadmap `fedora45-postinstall`'s Phase 1 and roadmap
  `fedora45-modules`' Phase 2 wait for it, so that every phase that follows ends with its review.
- **Method:** the skill tooling's procedure for a new skill. The evals' cases and a baseline
  without the skill come before the skill's files; scripts are written test-first; the static
  audit runs after every write of the skill or an agent. Paid runs start only after the user's
  yes, given on their count and an estimate.
- **What the tracked files name:** the repository is public; its tracked files name no source the
  port was read from, and no review record names a path another clone lacks, such as `my-config/`,
  `notes/` or `reviews/`.
- **A defect of the skill tooling** (`authoring-skills`, the roadmap skill, `usage.py`) is written
  as a design-feedback note to its owner, never edited from here.
- Repository conventions apply, no migration code included.

---

## Deliberately Out Of Scope

- The module reviews themselves (roadmap `fedora45-modules`) and `postinstall/` (roadmap
  `fedora45-postinstall`).
- A full review of the repository: the first real use reviews the diff of `fedora45-modules`'
  Phases 0 and 1 alone. A finding on a module's code outside that diff's items goes to that
  module's phase of roadmap `fedora45-modules`.
- Running the review in CI: CI keeps ShellCheck and the `bats` tests.
- Any direct change to the skill tooling.

---

## Phases

- [Phase 0: Design & Threat Model](phase-0-design-threat-model.md)
- [Phase 1: Evals & Baseline](phase-1-evals-baseline.md)
- [Phase 2: Scripts, Skill & Agents](phase-2-scripts-skill-agents.md)
- [Phase 3: Evaluation](phase-3-evaluation.md)
- [Phase 4: First Real Use](phase-4-first-real-use.md)
- [Phase 5: Fixes & Closing Pass](phase-5-fixes-closing-pass.md)

---

## Dependencies

- Each phase builds on the previous one; Phase 0's closure adjusts Phases 1 to 5 to its decisions.
- `authoring-skills`, its eval harness and `usage.py`, installed: Phases 1, 3, 4 and 5 start paid
  agent runs, each batch after the user's yes; the usage windows set the pace.
- The two Fedora 45 test VMs, for the verifiers' probes and the fixes' VM harness runs.
- Roadmap `fedora45-modules`' Phases 0 and 1, closed, for Phase 4's real use.

---

## Related Documentation

- [Module review checklist](../../../core/module-review.md)
- [Repository conventions](../../../core/conventions.md)
- [Testing and the VM harness](../../../core/testing.md)
- [Versioning rules](../../../core/versioning.md)

---

## Metadata

**Roadmap Status:** 🔴 Not Started
**Created:** 2026-11-06
