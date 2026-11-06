# Testing

How the project is tested: unit tests of pure functions with `bats`, and a harness that runs a
module's whole install cycle on the Fedora test VMs. What a module review expects from both is in
[Module Review](module-review.md); lint is `make shellcheck`, described in
[Conventions](conventions.md).

## Unit Tests

`make test` runs every `*.bats` file under `tests/unit/` with `bats`, packaged in Fedora
(`sudo dnf install bats`). A test file sits at the path of the source it tests:
`tests/unit/lib/registry.bats` tests `lib/registry.sh`. It sources that file from the checkout,
never from `/usr/local/lib/system-scripts`, so it tests the working tree. `make shellcheck` lints
the `*.bats` files with the scripts.

CI runs `make shellcheck` and `make test` in a `registry.fedoraproject.org/fedora:45` container,
with Fedora's own ShellCheck and bats.

## VM Harness

`tests/vm/run.sh <module>[/<submodule>]` runs, on each VM of `tests/vm/vms.conf`:

| Step | What it does |
|---|---|
| `reset` | shuts the VM down, restores its `clean-install` snapshot, starts it |
| `boot` | waits for its address and for SSH |
| `copy` | copies the files git tracks or sees as new, from the working tree, to `~/fedora-system-tools-test` |
| `prereqs` | installs the packages of `tests/vm/prereqs.list` |
| `lib` | `make install-lib` |
| `install`, `checks` | `make install-<target>`, then the module's checks |
| `reinstall`, `checks-2` | the same again: a second install must change nothing |
| `uninstall` | `make uninstall-<target>` |
| `leftovers` | compares the VM after the uninstall with the VM before the install |

It prints one table per desktop and exits 1 when a step failed or was skipped. Each run keeps its
logs, the checks' results, the VM's states and `leftovers.txt` under
`test-output/vm/<date>-<target>/<domain>/`, which git ignores. Make targets run with
`NONINTERACTIVE=1`, and every prompt gets Enter, its default answer. `--vm <domain>` limits the
run to one VM, `--keep` leaves it running; `VM_USER`, `VM_SSH_KEY`, `VM_CONF` and `VM_SNAPSHOT`
change the account, its key, the VM list and the snapshot.

The harness acts only on the VMs `vms.conf` lists, never on the host, and never changes their
snapshots: each run starts from the snapshot and leaves what it did in the VM until the next one.

### Checks

A module's checks live in `tests/vm/checks/<module>.sh`, a submodule's in
`tests/vm/checks/<module>/<submodule>.sh`. `tests/vm/guest-checks.sh` runs each `check_*`
function of the file in the VM, as the VM's user, in a shell of its own under
`set -euo pipefail`: a check passes when it returns 0, and `fail "<reason>"` ends it with the
reason the report shows. The file also sets `KEEP`, the glob patterns of what the uninstall
keeps on purpose, such as the user's config.

### Leftovers

`tests/vm/guest-state.sh` lists the VM's files, directories and links under `/etc`, `/opt`,
`/srv`, `/usr/local`, `/var`, `/root` and the user's home, the content of the files under `/etc`
and `~/.config`, and the accounts. It runs twice before the install, and what differs between
those two baselines is ignored as changing on its own, as are the package manager's and the
session's paths it excludes. After the uninstall, `leftovers` fails on a new path no package
owns, a path gone, a file whose content changed, or an account no package provides, unless
`KEEP` covers it. New paths a package owns are counted, not failed: they came with the packages
the module installed, which an uninstall leaves.
