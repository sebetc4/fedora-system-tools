# Phase 1 Report: Shared Foundation

**Phase:** [phase-1-shared-foundation.md](phase-1-shared-foundation.md)
**Start Commit:** f97d0d8

---

## Work Log

### 2026-11-06

Phase opened on the user's word, ahead of roadmap `fedora45-postinstall`, Phase 1: `postinstall/`
sources the repository's `lib/` from the checkout, so its runner should build on a library this
phase has already reviewed and tested.

Registry defects first. Six `bats` tests of the registry's layout, written in a registry under
the test's temporary folder through `REGISTRY_PATH_OVERRIDE`, and five of them failed on the
code as it stood: rewriting the last entry added a blank line each time (three after two
rewrites), rewriting the only entry left two blank lines under the header, and removing the
last entry, through `registry_remove` or `registry_remove_submodule`, left the file. The cause
of the blank lines: the section removal kept the blank line before a section, which belongs
to the previous one in the file's reading, and `registry_set` added its own. `lib/registry.sh`
now rewrites the file through `_registry_drop_section`, which drops blank lines and writes one
before each section; `registry_remove` deletes the file once no section is left and its folder
with `rmdir --ignore-fail-on-non-empty`, which keeps `/etc/system-scripts` and a user folder
holding `color.conf` or `bookmarks.conf`. `registry_set` calls the section removal directly, so
rewriting the only entry never deletes the file it is about to append to. All twelve tests
pass. On both VMs, `tests/vm/run.sh notifications` now finds 3 leftovers instead of 5: the
user registry and its folder are gone, and the 3 left are the empty `~/.config/systemd/user`
and `~/.local/log` that Phase 2 owns.

The review of `registry.sh` also showed a defect no task named: the rewrite went through a
fixed `registry.tmp` moved over the file, so under `sudo` the user registry of a `type: user`
submodule became root's after its first write. A probe in a `fedora:45` container running as
root, two `registry_set_submodule` calls under `SUDO_USER` with `REGISTRY_PATH_OVERRIDE`, gives
`root:root` with the old code and `u:u` with the new one: the temporary file now comes from
`mktemp` beside the registry and takes the file's mode, and under root its owner. This machine's
own `~/.config/system-scripts/registry` is `root:root` since 2026-03-15, from the `backup/vps`
install; the next write as the user (a `notifications` install) replaces it with a file of
the user's, and `sudo chown "$USER:" ~/.config/system-scripts/registry` does it at once.
`registry_init` now gives created files to `SUDO_USER:`, the user's login group, instead of a
group named after the user. Lib bumped to 0.5.1, a patch. `docs/lib/registry.md` and
`docs/core/state-and-paths.md` say how the file is kept, and the latter no longer lists
`registry_list` and `registry_get_date`, which do not exist.

`eval echo ~user` replaced with `getent passwd` in `lib/notify.sh` and `uninstall.sh`. The
`eval` ran the user name as shell: a `bats` test with `SUDO_USER="nobody;touch <file>"` saw
`_notify_resolve_home` create the file, then, fixed, create nothing and fail. An unknown user
now stops both with a message instead of resolving to an empty home, which in `notify_register`
would have written under `/.config/notify-daemon`. In `uninstall.sh`, a probe of the new lookup
gives the user's home for a real user and stops on the same hostile name without running it.
`git grep -n eval` on the scripts, `*.bats` and the Makefile finds nothing. `uninstall.sh` goes
to 0.1.1; the lib stays at 0.5.1, this phase's patch. Its review, with `setup.sh`'s, has one
more thing to settle: its step 5 removes the whole `~/.config/system-scripts`, where the user's
`color.conf` and `bookmarks.conf` also live.

Bootstrap. Fedora 45 ships both tools: `gum` 2.0.2 and `yq` 4.53.3 (mikefarah's) in `fedora` and
`updates`. Gum's jump from 0.17 to 2.0 was checked first in a `fedora:45` container: every flag
the scripts pass to `choose`, `style`, `input`, `spin`, `table`, `log`, `join` and `format`, and
the nine `GUM_*_FOREGROUND` variables, are still in gum 2.0.2's help; the menus' behaviour under
gum 2 waits for `ui.sh`'s review. `lib/install.sh` now installs, before the library and in one
`dnf` transaction, whichever of `yq` and `gum` is missing, without asking: the `[y/N]` prompt
went with the Charm repository, its heredoc, its `rpm --import … || true`, and the `apt-get`
branch, Fedora being the only target. `--no-gum` still skips Gum. The script gained the ERR
trap it lacked. Lib bumped to 0.6.0, a minor: the installer does more. `tests/vm/prereqs.list`
keeps `make` alone. Proof: `tests/vm/run.sh notifications` from `clean-install` on both VMs,
neither holding `yq` nor `gum`: the `lib` step installs `yq-4.53.3-2.fc45` and
`gum-2.0.2-1.fc45` and prints both versions, then the install, both checks and the uninstall
pass, the leftovers the same 3 folders as before. `README.md` no longer says `yq` installs on
its own and names `make`, and `docs/lib/install.md` and `docs/lib/overview.md` describe the new
step.

Release path, choosing to select the newest `v*` release over dropping module tags: it also
guards against a pre-release or a release made by hand, and keeps the release process
`docs/core/versioning.md` documents. The old parser, given a `releases/latest` answer whose
`tag_name` is `clamav-v0.7.0`, finds no tag, so `install.sh` and `--self-update` would stop on
"Could not determine latest release". `install.sh` and `setup.sh` now read
`releases?per_page=100` and pick the highest `vX.Y.Z` through `latest_project_tag`, still without
`jq`, a function each script holds since neither can source the other. `tests/unit/install.bats`
reads it out of both files: a newer module release, a pre-release, numeric order and a list
without any project release, plus the check that both copies are identical, which failed until
`setup.sh` had its copy; with `sort -V` removed, the order and module-tag tests fail. Against
the real API, the function gives `v0.6.0`. Both scripts go to 0.1.1, and
`docs/core/versioning.md` says how the release is picked.

Review of `lib/`, first the files with pure functions. `format.bats` caught `format_size`
printing 1024 as `1024 B` and 1 GiB as `1024.0 MB`, its thresholds being `-gt`: each unit now
starts at its exact size, and the division runs in `awk`, which drops the `bc` dependency and
writes a `.` under a French locale. `yaml.bats`, nine tests on a config in the test's folder,
passed as written; it documents that the array readers return 1 on an empty list, which the
`hdd` and `hdd-both` backups use for their defaults (`|| echo "/"`), and the examples of
`lib/yaml.sh` and its documents, which piped them into `while`, now read them through process
substitution, since under `pipefail` a pipe would end the script without a message on an empty
list. CI installs `yq` for these tests. `validate.bats`, eight tests, passed as written;
`validation_check` no longer leaks its loop variable. `paths.bats` found two defects of
`lib/paths.sh`. Without `user-dirs.dirs`, `xdg-user-dir` answers with the home, which the probe
then took as the download folder, so ClamAV would have watched the whole home; the home is now
never returned. And `paths.conf`, which root scripts source, wrote each folder in double
quotes: a probe of the old code as root reads it, a folder named `dl $(touch <file>)`, creates
the file when `paths.conf` is sourced, and the new code, which single-quotes every value,
creates nothing. `xdg-user-dir` went too, since it sources `user-dirs.dirs` itself;
`user-dirs.dirs` is parsed as text alone. An installed `paths.conf` is kept as it is, per
the no-migration rule.

`submodule.bats` holds the dependency-order tests: with a chain `report` → `scanner` → `core`,
`submodule_sort_uninstall` gave `report, core, scanner`, since it only held back a direct
dependency, so `core` would have come before `scanner` and the deps protection would have
refused it. No module has a chain today; the function now emits, pass after pass, the
submodules no pending one depends on, and the five tests pass. Then the rest of `lib/`. In
`ui.sh`, eight functions are called nowhere, `ui_write`, `ui_file`, `ui_spin`, `ui_pager`,
`ui_log`, `ui_format`, `ui_join` and `ui_style`: they are removed with their documentation
(see Decisions), 310 lines out of 613, with the unused `body` of `ui_banner`; its two counters
are written `i=$((i + 1))` and `i=$((i + 2))`. `color.sh` set its defaults twice and its
terminal overrides twice, at load and in `color_reload`: each is now one function, which drops
18 of its 21 `SC2034` directives; `color.bats`, four tests, passed before the change and after.
The defaults no longer take `COLOR_ACCENT` and `COLOR_ERROR` from the environment, an override
no document named and `color_reload` ignored. `detect_real_user` in `fs.sh` stops with a message
on an unknown `SUDO_USER` instead of leaving an empty `REAL_HOME`, and `notify.sh` gives the
user's files to `SUDO_USER:`. `core.sh`, `config.sh` and `log.sh` needed nothing. `make test`
runs 55 tests. On both VMs, `tests/vm/run.sh notifications` passes as before, the 3 leftovers
of Phase 2 aside, the generated `paths.conf` holds single-quoted values, and the system
registry keeps one blank line after two library installs. `submodule.sh` beyond its sort is
the next task's.

Session closed with five of the eight tasks done, each committed and pushed, CI green on every
push, `yq` included. The menus were not tried by hand under gum 2.0.2: only its flags and
variables were checked, so the interactive use of `setup.sh` on the VMs is where its behaviour
shows. Seen during the review and left to the tasks that own them: `submodule.sh` still holds
five counters (`((i++))`, `(( ++idx ))`, `(( ++remaining ))`); `setup.sh` keeps its own copies of
`has_gum`, `ui_choose`, `ui_confirm`, `ui_header`, `error`, `warn`, `info`, `success`, of
`_version_compare` and of the color defaults, which `color_reload` now resets alone.

Session resumed the same day on `lib/submodule.sh`, the engine. Its removals went beyond what
a module declares: `backup/local`'s uninstall deleted `hooks.d/pre-backup` and `post-backup`
whole, where `docs/modules/backup/local.md` invites user hooks and where this machine holds
`btrfs-snapshot.sh`, which no module ships; a declared directory went by `rm -rf` whatever its
path; `notify_unregister` left `levels.conf` and its folder. Removals now follow the first
decision below. The install wrote in the home as root: `install -d -o` owns the last folder
alone, so `vps` made `~/.local/log` root's, and `registry_init` and `notify_register` did the
same with a missing `~/.config`. In a `fedora:45` container, for a user without `~/.config`,
HEAD's engine leaves `~/.local`, `~/.local/log`, `~/.config` and `~/.config/probe` to root, the
new one nothing.

Other defects fixed: `system_deps` checked with `command -v`, which never finds `inotify-tools`,
behind a `[y/N]` whose default skipped them; a missing `bw` stopping `make install-backup` before
`vps`; the deps protection reading a typeless dependent with the removed submodule's type;
global context variables, which a dependency's install overwrote; a declared hook file missing
skipped silently; templates' logrotate configs named after the file, so `bitwarden`'s and
`vps`'s `user-logs.tpl` collided, now `<user>-<name>` as `docs/core/logrotate.md` said; unknown
options ignored; unit failures silenced; five counters. Removed as dead code: the list form of
`source`, unreachable since `submodule_get` prints a list as text, and `_module_pre_uninstall`.
The engine's knowledge of `backup` became keys, `hook_scripts` and a `configs:` entry for the
hook config. `backup` goes to 0.2.1, `bitwarden` to 0.1.2; the lib stays at this phase's 0.6.0.
`ui_press_enter` read `/dev/tty` under `sudo`, which drops `NONINTERACTIVE`, so installers over
`ssh` ended in error after their work; it returns when no terminal can answer.

`make test` runs 79 tests, 22 new; seven mutants restoring an old behaviour each fail their
test, and HEAD's `notify.sh` and `ui.sh` fail theirs. `tests/vm/checks/backup.sh` checks what
`module.yml` declares, owners included, and that nothing in the home is root's. HEAD's tree on
KDE: the install stops at `bitwarden`, the uninstall ends on `/dev/tty`, `levels.conf` and its
folder are left. CUPS rewriting `/etc/cups/subscriptions.conf` failed one run, and joins the
paths `guest-state.sh` excludes. The final tree passes `tests/vm/run.sh backup` on both VMs, 11/11
checks twice and 0 leftovers but `~/.config/backup`.

**Where the next session starts:**
1. Seed config files from `my-config/` in `_install_submodule_configs`, never overwriting an
   installed one; every config file a submodule installs is now a `configs:` entry, hook
   configs included.
2. Review `setup.sh`, `install.sh` and `uninstall.sh`: its copies of library functions and of
   `_version_compare`, the menus under gum 2 on both VMs, and `uninstall.sh`'s removal of the
   whole `~/.config/system-scripts`, where `color.conf` and `bookmarks.conf` live.
- This machine's `~/.config/system-scripts/registry` is still `root:root`, waiting for a write
  as the user or `sudo chown "$USER:" ~/.config/system-scripts/registry`. An upgrade of
  `backup/bitwarden` here leaves `/etc/logrotate.d/user-logs`, its former name, to remove by
  hand; `hooks.d/pre-backup/btrfs-snapshot.sh`, which no module ships, now survives an uninstall.

---

## Decisions

- **An uninstall removes what a submodule declares and nothing else.** Decided on 2026-11-06 in
  the engine's review: hook scripts by name, declared directories behind the removal guard, and
  the folders of the home it emptied, never a direct child of the home, as Phase 2 decided for
  `notifications`. Commits every module phase's checks to a `leftovers` step clear but for `KEEP`.
- **Everything written in the user's home belongs to the user.** Decided on 2026-11-06: the
  engine, `registry_init` and `notify_register` write there as the user through `runuser`,
  missing parents included, instead of writing as root and `chown`ing the last component.
  Commits every module's VM checks to verifying that nothing in the home belongs to root.
- **Missing packages are installed without asking; a missing command warns.** Decided on
  2026-11-06, as `lib/install.sh` already installs `yq` and `gum`: `system_deps` go to
  `dnf install -y`, and `required_commands` the user installs get a warning, the install going
  on. Set aside: the `[y/N]` prompt, whose default skipped the packages, and stopping the whole
  install on a command a single submodule needs to run.
- **Release detection picks the highest `vX.Y.Z` release instead of dropping module tags.**
  Decided on 2026-11-06 under the task's two options: it also guards against a pre-release or a
  release made by hand, and keeps the release process `docs/core/versioning.md` documents.
- **A library function no script calls is removed, not kept as API.** Decided on 2026-11-06 from
  the checklist's "No duplicate, no dead code", which the user approved: eight `ui.sh` functions
  went. A module that needs one again brings it back with its first caller and a test. Commits
  every module phase to the same rule for its own functions.

---

## Deviations

- `phase-3-clamav.md`: task added under Refocus, moving the rendering of
  `download-clamscan.service.tpl` out of the engine into the module and settling whether a system
  timer starts at install, both found in the engine's review; Phase 3 goes from 9 to 10 tasks.
- `phase-4-backup.md`: the `vps` review task now also moves its logrotate template and its log
  folder's removal from its hooks into `module.yml`, which the engine can now do.
- `modules/backup/module.yml`, Phase 4's, changed here for the engine's keys alone: the files a
  backup install writes are the same, but for `bitwarden`'s logrotate config, now
  `/etc/logrotate.d/<user>-backup-bitwarden`.
- `lib/ui.sh`, `lib/notify.sh` and `lib/registry.sh`, already reviewed, were fixed again here:
  the harness and the probe showed what reading had not.
---

## Assessment
