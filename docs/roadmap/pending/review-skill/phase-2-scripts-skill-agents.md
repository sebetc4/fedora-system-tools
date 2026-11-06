# Phase 2: Scripts, Skill & Agents

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/9)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Port the scripts test-first, then write the skill, its agents' rules, its reviewers and its
verifier on them, from Phase 1's failures and Phase 0's decisions, so that the scope, the
findings, the report, the register and the regression run are computed rather than transcribed.

### Out of Scope
The runs that compare the skill with the baseline, which Phase 3 makes.

---

## Tasks

### Scripts
- [ ] `scope.py`: the scope by hunk, each hunk with the Bash item that holds it as `path:first-last (symbol)`, the routes of the other files, the lines handed to the reviewers counted, and each line's origin by `git blame -w`
  Proof: medium, test — tests on captured files and on a repository made in scratch, watched failing on their assertion, then passing
- [ ] `findings.py`: taken over with the changes Phase 0 named, every answer checked whole, a path another clone lacks refused in a record
  Proof: medium, test — its tests on this repository's formats watched failing, then passing; the fixture's review states given back byte for byte
- [ ] `regression.py`: each recorded mutant, an exact replacement, applied in a `git archive` copy and its killing `bats` test run, each one missed or gone reported
  Proof: medium, test — one mutant caught and one missed on a fixture repository, watched failing, then passing
- [ ] `guard.py`: the commands Phase 0 allowed and refused, and the tree's state checked at each agent's stop, wired in the project's `.claude/settings.json`
  Proof: high, test — hook inputs in the probed form, each refused command refused and a changed tree blocking the stop, watched failing, then passing
- [ ] Add the scripts' tests to the repository's checks, in `.agent-conventions.toml` and the `Makefile`
  Proof: low, check — every check runs green

### Skill And Agents
- [ ] Write `SKILL.md` by moment on the scripts, the session's own steps written with the care given to the agents': where the scope ends, how the tier is chosen, no write while an agent runs, what a stopped review keeps for the next session
  Proof: medium, `authoring-skills`' static audit clean; the steps read against Phase 1's cases
- [ ] Write the fix method for Bash, its later rules in from the start: each batch runs the whole record of mutants; a fix to what the code makes — an installed file, a unit, a registry entry — names what it made before; a test needing what a copy lacks is found before the first batch
  Proof: medium, static audit clean; the method read against the bugs of `reviews/2026-11-04-repository-review.md` (untracked)
- [ ] Write the agents' rules skill — where an agent works, reading the scope, severity by the threat document's anchors, the answer format —, preloaded by each agent, then the reviewers and the verifier for this repository's content, their examples taken from real reviews, never from the fixture
  Proof: medium, static audit clean on each; a search shows the rules in one file and none of the fixture's planted defects in the skill or its agents
- [ ] Write the skill's description for its moments
  Proof: medium, static audit clean on the description; its trigger rates measured in Phase 3

---

## Technical Details

### Files to Modify
```
the skill's folder, its agents and the project's .claude/settings.json, where Phase 0 placed them
.agent-conventions.toml
Makefile
```

### Dependencies
Phase 0's design; Phase 1's cases and failures.

### Constraints
A script is written test-first, each test watched failing on its assertion. The skill cites no
roadmap, phase or report, and a repository path only where a step reads, runs or writes it.
