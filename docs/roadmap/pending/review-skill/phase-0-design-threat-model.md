# Phase 0: Design & Threat Model

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/12)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Decide with the user, block by block, how the reference reviewer becomes this repository's: what
is taken over unchanged, what is replaced, and where each part lives. Write the threat document
the review's tier, security axis and severity anchors read. The session proposes, each proposal
resting on a figure of this repository or a probe; the user decides; the decisions go into this
phase's Design section before their commit, and Phases 1 to 5 are adjusted to them.

### Out of Scope
The skill, its agents, its scripts and its evals, written from Phase 1 on. Any paid run but the
probes the user accepts.

---

## Tasks

### Where It Lives
- [ ] Decide where the skill, its agents, the guard's hooks, the reviews, the debt register and the recorded mutants live, and which of them git tracks, given that `.claude/`, `CLAUDE.md` and `/reviews` are ignored and the repository is public; adjust `.gitignore` to the decision
  Proof: medium, the user's review of the Design section; `git check-ignore -v` on each path giving the decided answer

### The Workflow
- [ ] Write the moments and the stopping rule — a review at the close of each phase that changed code, on the phase's diff; one closing pass per roadmap; a full review only on request; no pass after the closing one — and the trigger, a `closing_tasks` entry of `.agent-conventions.toml`'s `[roadmap]` table
  Proof: medium, the user's review of the Design section
- [ ] Decide the go-ahead and the tier: one go-ahead per review, its agents counted with an estimate from `usage.py`; the tier taken from the surface the threat document guards before the scope's size; the session's triage, the user asked only the hard cases
  Proof: medium, the user's review of the Design section

### Findings And Scope
- [ ] Take over the structured finding — its effect, severity, floor and fingerprint —, the debt register and the report written from `findings.json`, naming each change this repository needs
  Proof: medium, the user's review; one finding of `reviews/2026-11-04-repository-review.md` (untracked) rewritten in the format, no field left empty
- [ ] Specify the scope by hunk for this repository: the Bash items that hold a hunk — a function, a script's top level —, and the routes of the other files: `module.yml`, systemd units and their templates, logrotate files, the `Makefile`, `docs/`, `tests/`
  Proof: medium, measure — the lines a scope by hunk hands the reviewers on `52fa84f..befea3f`, counted against a scope by file

### Agents, Guard And Mutants
- [ ] Decide the axes and what each reviewer checks here, from `docs/core/conventions.md` and the module review checklist: errors under `set -e`, quoting, root boundaries, installed files, the no-migration rule; and whether a dependency axis exists or the external sources — container images, third-party repositories, downloads, CI actions — stay with security
  Proof: medium, the user's review of the Design section
- [ ] Decide the guard: the commands a review agent may run (read-only git, ShellCheck, `bats`, `make shellcheck`, `make test`, the read forms of `systemctl` and `rpm`) and those it never runs (`sudo`, `dnf`, the installers, `setup.sh`, the modules' scripts, `tests/vm/run.sh`); a run on a test VM made a `PROBE` the session runs from a snapshot
  Proof: high, probe — the project settings' `PreToolUse` and `SubagentStop` hooks seen receiving a subagent's calls with its `agent_type`, after the user's yes
- [ ] Decide the mutants: whether a mutation tool for Bash and `bats` exists and holds on this repository; otherwise the kinds a fix applies by hand — `set -e` lost, a quote removed, an `|| true` added, a test inverted, a `${var:?}` guard removed, a `local` dropped —, recorded and run again at a roadmap's close
  Proof: medium, probe — the tool run on one file of `lib/`, or the search that found none recorded in the report

### Threat Model
- [ ] Write `docs/core/security.md`: what the tool protects — the system, the user's files and backups, the secrets it handles —, who reaches what — the user, root through `sudo` and the services, another local account, a hostile file arriving by download, torrent or USB drive, the network through the torrent client and its VPN, the release tarball and the bootstrap —, and what the tool promises against each
  Proof: high, the user's review; each statement of who reaches what checked against the code or the units it names
- [ ] Write in it the severity anchors and the attack classes of a Bash tool run as root: option and command injection through file names, quoting, `eval`, a sourced file another account can write, temporary files and symlinks, `rm -rf` on an empty variable, files written as root in the home, secrets in command lines and logs, downloads and their keys, the units' hardening; link it from `docs/core/README.md` and the checklist's Security section
  Proof: medium, the user's review; each security point of `reviews/2026-11-04-repository-review.md` (untracked) rated by the anchors

### Evals And Adjustment
- [ ] Plan the evals by severity: the cases, the phase's close given its own run, the fixture's planted defects; probe first what the skill uses in the eval harness — `usage.py`, an agent's `skills:` preload, the project's hooks —; no request carries personal data
  Proof: medium, the user's review of the plan; the probes' results recorded in the report
- [ ] Adjust Phases 1 to 5 to the decisions
  Proof: low, the user's review of the phase files

---

## Technical Details

### Files to Modify
```
.gitignore
docs/core/security.md          (new)
docs/core/README.md
docs/core/module-review.md
this roadmap's phase files
notes/review-skill/            (untracked)
```

### Dependencies
None: the reference reviewer is read from `notes/review-skill/reference.md` (untracked).

### Constraints
Each block is proposed, decided and written into the Design section before its commit. Probes of
the harness run in scratch, each after the user's yes when it starts an agent. The Design names no
source the port was read from.
