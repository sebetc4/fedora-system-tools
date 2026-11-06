# Module Review

The checklist a module is reviewed against, the shared library and installers included, before it
counts as ready: what each area checks and what passing means. The coding rules it applies are in
[Conventions](conventions.md), version bumps in [Versioning](versioning.md), and the files a
module may install in [State, Configuration & Installed Paths](state-and-paths.md).

## How A Review Runs

A review covers one module whole: its `module.yml`, scripts, installer and uninstaller, hooks,
units, config files and document. Each item below ends passed, failed, or not applicable with the
reason. A failed item is fixed during the review, or recorded with where it goes; the module passes
when no item is left failed. Passing rests on a proof — `make test`, `make shellcheck`, a run of
the VM harness on both desktops, a measurement —, never on reading the code alone.

## Correctness

- **Strict mode.** Every script runs `set -euo pipefail` with the ERR trap, or omits `-e` with
  the comment the strict mode exceptions ask for. Passes when each script's header shows one or
  the other.
- **No silent abort.** Nothing ends a script under `set -e` without a message: no arithmetic
  command as a statement (see [Conventions](conventions.md), Arithmetic under `set -e`), no
  `[[ … ]] && …` or `grep` as a function's last command when it may fail. Passes when each hit
  of `git grep -nE '\(\(.*(\+\+|--|\+=|-=)'` in the module is a `for ((…))` header, and every
  failure path prints what failed.
- **Every entry point works.** Each command-line option, menu entry, service and timer does what
  its `--help` and its document say, and fails with a non-zero status and a message naming the
  cause. Passes when each one has run, in a test or on a VM.
- **Install, reinstall, uninstall.** A second install changes nothing and succeeds; an upgrade
  keeps the user's config; an uninstall removes what `module.yml` and its hooks declare, nothing
  else, and keeps the user's config and data unless asked. Passes on the VM harness's second
  install and uninstall checks.
- **Dependencies.** Every command the module calls is checked by `check_deps` or installed by
  its installer, and the install needs no manual step beyond those its document names. Passes
  when an install from the `clean-install` snapshot succeeds.
- **Fedora 45.** Nothing relies on what Fedora 45 changed: DNF5 syntax, packaged repository
  files under `/usr/share/dnf5/repos.d`, RPM signature enforcement. Passes when the module runs
  on both Fedora 45 VMs.

## Optimization

- **Resident cost.** A service runs permanently only when its use needs it; otherwise it starts
  on demand (timer, path, socket or udev activation). Passes when each resident unit's memory
  and CPU at rest is measured and justified.
- **Work done once.** No full scan or walk where an event, a cache or a narrower path would do,
  and every schedule matches how the user works. Passes when each scheduled or repeated task has
  its reason.
- **Logs.** Each log has its rotation (see [Logrotate](logrotate.md)) and says what happened
  without repeating itself: routine events at debug level, one line per action at info. Passes
  when a day of normal use is measured in lines per log and in the journal.
- **No duplicate, no dead code.** No copy of a library function, no unused function, option or
  file. Passes when every function is called and `git grep` finds no second definition of a
  library function.

## Tests

- **Unit tests.** Pure functions — parsing, comparing, computing, ordering — have `bats` tests
  under `tests/unit/`, at the path of their source. Each bug fixed in the review gets a test
  watched failing on the bug before the fix. Passes when `make test` passes and each new test
  was seen failing.
- **VM checks.** What needs root, systemd, a desktop session or a mount is checked by the VM
  harness under `tests/vm/`. Passes when the module's checks pass on both VMs.
- **What no test reaches.** Real hardware, the user's own servers, NVIDIA: each such part is
  named with how it was tested instead. Passes when none is left unnamed.

## Security

- **Root boundaries.** A script runs as root only for what needs it, and a `type: user`
  submodule never does. Under `sudo`, the user comes from `detect_real_user`, never from root's
  `$HOME`, and files written in the user's home belong to the user. Passes when every root path
  is listed with its reason and the ownership of written files is checked on a VM.
- **Quoting and input.** Every expansion is quoted, ShellCheck passes with no new `disable`,
  and there is no `eval` but a documented one. A path read from a config or an argument is
  checked before `rm`, `mv` or `rsync --delete` acts on it, and `rm -rf` never takes a variable
  that may be empty (`"${dir:?}"`). Passes when `make shellcheck` passes and each `eval`, `rm -r`
  and `--delete` is reviewed.
- **Temporary files.** Created by `mktemp`, mode 600 when they hold anything sensitive, and
  removed by an `EXIT` trap. Passes when each `mktemp` has its trap and no sensitive file is
  readable by another user.
- **Secrets.** Never in a tracked file, a command line (visible in `ps`), a log or the journal;
  a file holding one is mode 600 and belongs to its user. Passes when `git grep` finds none of
  the module's secrets and the logs of a VM run hold none.
- **External sources.** Packages come from Fedora's repositories; a third-party repository,
  download or container image is used only when Fedora lacks the software, with its key,
  checksum or digest verified (see [Conventions](conventions.md), Installers). Passes when each external source is listed with
  its verification.
- **Systemd hardening.** Each service carries the sandboxing it can bear: `NoNewPrivileges=`,
  `ProtectSystem=strict` with `ReadWritePaths=`, `ProtectHome=` when it does not read homes,
  `PrivateTmp=`. Passes when `systemd-analyze security <unit>` is recorded before and after,
  and each option left out has its reason.

## Personalization

- **Personal settings.** Defaults are generic, the user's values live in the installed config
  files, and nothing that [Conventions](conventions.md), Personal settings, excludes is tracked. Passes when `git grep` on
  the module finds none of the user's values and a second install leaves an edited config
  untouched.
- **Configurable, not hardcoded.** Paths, schedules, thresholds and hosts are read from the
  module's config, never written into a script. Passes when no script holds a value of the
  user's or of one machine.
- **Both desktops.** The module works on GNOME and on KDE Plasma, preferably by depending on
  neither; where a desktop is unavoidable, both are handled. Passes when the VM harness passes
  on both VMs.

## Documentation

- **The module's document.** Its document under `docs/modules/` gives the current state: what
  it does, its submodules, install, configuration, the files it installs, troubleshooting.
  Passes when its commands run as written on a VM and the repository's `README.md` claims
  nothing it does not do.
- **Installed files and versions.** [State, Configuration & Installed Paths](state-and-paths.md)
  lists every file the module installs, `module.yml` descriptions match the scripts, and each
  changed level is bumped per [Versioning](versioning.md). Passes when the list matches a VM
  install and the bumps match the changes.
- **Headers and help.** Each script's header and `--help` match what it does. Passes when they
  are read beside a run.

## VM Validation

- **The full cycle on both desktops.** The VM harness runs, from each VM's `clean-install`
  snapshot, the install, the module's checks, a second install and the uninstall, and reports
  per desktop. Passes when the report shows every step passed on GNOME and on KDE Plasma.
- **Nothing left behind.** After the uninstall, no file, unit, timer, user or registry entry of
  the module is left but those its document says are kept. Passes when the harness's
  comparison before and after finds nothing else.
