# Phase 0 Report: Framing & Test Harness

**Phase:** [phase-0-framing-test-harness.md](phase-0-framing-test-harness.md)
**Start Commit:** 52fa84f

---

## Work Log

### 2026-11-06

Phase opened once roadmap `fedora45-postinstall` closed its Phase 0 with both test VMs. The user
agreed to declare `make shellcheck` and `make test` as the repository's `checks`.

`make shellcheck` now lints every `*.sh` file git tracks or sees as new and not ignored, 87
scripts instead of 76: `git ls-files --cached --others --exclude-standard`, filtered by
`$(wildcard)` so a file deleted but still in the index does not break the run. `--others` goes
beyond the task's `git ls-files '*.sh'` so that a script is linted before it is staged. Of the
11 scripts it adds, only `templates/script-header.sh` failed (SC2155 on
`readonly SCRIPT_NAME="$(basename "$0")"`); the template now declares and marks it readonly
separately, as the modules do. Proof: `make shellcheck` passes on the 87 scripts; with an
untracked `modules/zz-bad-probe.sh` holding an unquoted `[ $x == 1 ]`, it fails with SC2086 and
exit 2, then passes again once the file is removed.

Unit tests live under `tests/unit/`, mirroring the source tree, which leaves `tests/vm/` to the
harness; `make test` runs `bats --recursive tests/unit` and stops with the `dnf` command to run
when `bats` is missing. `make shellcheck` lints the `*.bats` files too. The first file,
`tests/unit/lib/registry.bats`, holds six tests of `version_compare`: equality, patch, minor and
major order, numeric rather than text comparison, a missing component read as 0. `bats` is not
installed on this machine and installing it needs the user's `sudo`, so the proof ran in a
`registry.fedoraproject.org/fedora:45` container (bats 1.14.0, ShellCheck 0.11.0, the local
version): the six tests pass; with `version_compare` comparing as text, "components compare as
numbers" fails on `0.10.0` against `0.9.0` (`lt` instead of `gt`) and `make test` exits 2; the
mutation reverted, all six pass. `setup.sh` keeps its own copy of the function,
`_version_compare`, which the tests do not cover: Phase 1 settles it with `setup.sh`.

CI now runs in the same `fedora:45` container, with Fedora's ShellCheck and bats, and runs
`make test` after `make shellcheck`; `git` is installed before the checkout so that
`git ls-files` finds a real clone. The job keeps its id, `shellcheck`.

---

## Decisions

- **The repository's `checks` are `make shellcheck` and `make test`.** Agreed by the user on
  2026-11-06. They are declared in `.agent-conventions.toml` once `make test` exists, since a
  declared check runs at every phase closure of every roadmap in this repository, roadmap
  `fedora45-postinstall` included.

---

## Deviations

- `phase-1-core-framework.md` of roadmap `fedora45-postinstall`: the task "Add the `postinstall/`
  scripts to the Makefile `shellcheck` target" now reads "Check that `make shellcheck` lints the
  `postinstall/` scripts…", and `Makefile (shellcheck target)` left its Files to Modify, since
  the target picks up new scripts on its own.

---

## Assessment
