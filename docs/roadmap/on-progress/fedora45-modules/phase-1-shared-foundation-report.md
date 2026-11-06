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

---

## Decisions

---

## Deviations

---

## Assessment
