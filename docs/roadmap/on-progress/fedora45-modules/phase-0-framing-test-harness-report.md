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
`git ls-files` finds a real clone. The job keeps its id, `shellcheck`. Proof: the run of commit
`5bd7f9d` on GitHub is green, every step passed, the unit tests included.

`checks = ["make shellcheck", "make test"]` is declared at the top of `.agent-conventions.toml`,
and `conventions.py roadmap` prints both.

The user set the documentation's convention, a `[docs]` table with `root = "docs"` and
`notes = "notes"`, and chose where personal settings live (see Decisions). `check_docs.py` then
reports 6 errors in documents this phase has not touched: no README in `docs/`, `docs/core/`,
`docs/lib/`, `docs/modules/` and `docs/modules/backup/`, and a broken link in
`docs/modules/backup/local.md` to `../bitwarden/README.md`. The checklist and the conventions
rules wait on their migration, which goes to the user as a plan.

The user approved the plan and the documentation is migrated: `docs/README.md` is the entry
point with the convention's rules, and `docs/core/`, `docs/lib/`, `docs/modules/` and
`docs/modules/backup/` each have a README listing their documents. No document moved. The dated
footers are gone (`Last Updated` in ten documents, `Version` in three backup documents),
`local.md` links `bitwarden.md`, the Related block of `hdd-both.md` links `hdd.md` and
`local.md` instead of stale paths, and the repository's `README.md` links `docs/README.md`.
`check_docs.py` reports 0 errors and 0 warnings. `build-kernel` still has no document.

The user's `my-config/` already exists, laid out like the repository's tree, not by installed
path as the personal settings decision first said: the decision and Phase 1's seeding task now
follow it. It still holds `modules/backup/system/`, the name `local` had before 0.6.0, which
Phase 4 meets when it reviews `local`.

`docs/core/conventions.md` gains the rules the repository review showed missing: arithmetic
under `set -e`, increments written `n=$((n + 1))` and `(( ))` kept for conditions; the user's
home from `getent passwd`, never `eval echo ~user`; installers without heredocs, packages from
Fedora's repositories, no key import followed by `|| true`, no installed config overwritten; and
the personal settings rule, with its decision entry. Proof: beside the rule,
`bash -c 'set -e; n=0; ((n++)); echo reached'` prints nothing and exits 1, the same with
`n=$((n + 1))` prints `reached`, and `((n += 1))` from `-1` exits 1 as well. The rule turns many
existing counters into rewrites: outside `for ((…))` headers, `git grep` finds 91 `++`, `--`,
`+=` or `-=` arithmetic statements in 18 scripts, which each module's review converts.

The review checklist is written in `docs/core/module-review.md`: correctness, optimization,
tests, security (root boundaries, quoting and input, temporary files, secrets, external sources,
systemd hardening), personalization, documentation and VM validation, each item with what
passing means. Its last item commits the VM harness to a comparison of the VM before and after
the uninstall. The user reviewed and approved it as written.

The user installed `bats` (1.13.0) on this machine: `make test` passes its six tests there, and
`make shellcheck` passes, so both declared checks run green locally.

---

## Decisions

- **The repository's `checks` are `make shellcheck` and `make test`.** Agreed by the user on
  2026-11-06. They are declared in `.agent-conventions.toml` once `make test` exists, since a
  declared check runs at every phase closure of every roadmap in this repository, roadmap
  `fedora45-postinstall` included.
- **Personal settings live on the machine, never in the repository.** Chosen by the user on
  2026-11-06 over keeping them in the installed files alone and over the postinstall `personal`
  profile. The repository holds generic defaults only, such as the `my-vps` placeholder of
  `backup/vps`. The user's values live in the config files a module installs (`~/.config/…`,
  `/etc/…`), which an install or upgrade never overwrites; copies of them are kept in the ignored
  `my-config/` at the checkout's root, laid out like the repository's tree
  (`my-config/modules/backup/vps/config.yml` for `modules/backup/vps/config.yml`), as the
  user's `my-config/` already is, to restore them after a reinstall. The postinstall `personal` profile keeps only choices fit to publish: packages,
  Flatpaks, desktop settings. The public repository never holds a secret (password, token, API
  key, private key, VPN credentials), the name or address of the user's hosts, an account name or
  email, or a path or value of the user's own. Commits Phase 1 to the seeding of config files from
  `my-config/` (task added), and every module phase to checking its defaults against this list.
- **The documentation follows the writing-documentation convention**, `[docs]` with
  `root = "docs"` and `notes = "notes"`, set by the user on 2026-11-06: one README per folder of
  documents, a settled decision under its domain document's Decisions, and no link from a
  document to a note.

---

## Deviations

- `phase-1-core-framework.md` of roadmap `fedora45-postinstall`: the task "Add the `postinstall/`
  scripts to the Makefile `shellcheck` target" now reads "Check that `make shellcheck` lints the
  `postinstall/` scripts…", and `Makefile (shellcheck target)` left its Files to Modify, since
  the target picks up new scripts on its own.
- `phase-1-shared-foundation.md`: task added under Bootstrap, seeding each config file a submodule
  installs from `my-config/` and never overwriting an installed one, from the personal settings
  decision; Phase 1 goes from 6 to 7 tasks.
- The documentation's migration to the `[docs]` convention, not planned in this phase, was
  done in it before the checklist, on the plan the user approved.
- The bats proof ran in a Fedora 45 container instead of on this machine, where `bats` was not
  installed yet; closed once the user installed it and `make test` passed locally.

---

## Assessment
