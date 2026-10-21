# postinstall

Brings a fresh Fedora Workstation install to a deliberate, minimal target state, idempotently,
from a profile. Generic defaults apply to any Fedora 45 install; a personal layer and one profile
per machine add the owner's choices.

**Status:** design only. The decisions below were taken in phase 0 of the
`fedora45-postinstall` roadmap; nothing is implemented yet. Usage documentation comes with the
implementation.

**Target:** Fedora 45 Workstation (GNOME), DNF5 only.

---

## Layout

```
postinstall/
├── postinstall.sh          entry point: sudo ./postinstall.sh --profile <name> [options] [steps…]
├── README.md
├── lib/
│   ├── runner.sh           step discovery, execution, status, final summary
│   ├── detect.sh           hardware and system detection
│   └── run.sh              executes a command, or prints it under --dry-run
├── steps/                  one file per step, ordered by a numeric prefix
│   ├── 10-dnf-config.sh
│   ├── 20-repos.sh
│   ├── …
│   └── 80-system-settings.sh
└── profiles/
    ├── default/
    ├── personal/
    ├── legion-7/
    └── legion-5/
```

Steps are ordered by their numeric filename prefix, numbered with gaps, and selected by their name
without the prefix (`postinstall.sh packages flatpaks`).

**Why:** the execution order is visible in a directory listing, and a step can be inserted between
two others without renumbering.

`lib/` holds only what is specific to this tool. Output, logging, and filesystem helpers come from
the repository's shared `lib/` (see below).

There is no step that installs fedora-system-tools: its installation is already simple and handled
by `make` or `setup.sh`. `postinstall/` stays self-contained so that it can later become a
fedora-system-tools module without a redesign.

---

## Step Model

A step file declares two variables and three functions:

```bash
STEP_NAME="nvidia"
STEP_SCOPE="root"            # root | user

step_applies() { …; }        # does this step concern this machine? (from detection)
step_check()   { …; }        # read-only: is the target state already reached?
step_apply()   { …; }        # makes the changes, every mutation through `run`
```

For each selected step, the runner:

1. reports the step **skipped**, with the reason, when `step_applies` fails;
2. reports it **compliant** and touches nothing when `step_check` succeeds;
3. otherwise runs `step_apply` in a subshell and reports it **changed** or **failed**.

**Why:** `step_check` is what makes a second run change nothing. Routing every mutation through
`run` gives a dry-run that walks the same code path as a real run. Running `step_apply` in a
subshell confines a failure to its step.

---

## Profiles

A profile is a folder of plain files, one per concern:

| File | Format |
|---|---|
| `profile.conf` | shell variables: `PARENT`, `KERNEL_ARGS`, `TUNED_PROFILE`, `REPOS`, … |
| `packages.list` | one package per line; `-name` removes a package |
| `flatpaks.list` | one application id per line |
| `extensions.list` | one GNOME extension UUID per line |
| `dconf/*.ini` | the `dconf dump` keyfile format, applied with `dconf load` |

Profiles form a chain through `PARENT`:

```
default    any Fedora 45 install
  └── personal    the owner's choices, shared by all their machines
        ├── legion-7    Legion 7, RTX 5090: only what detection cannot infer
        └── legion-5    Legion 5 15IMH05H, RTX 2060: same
```

The chain is loaded from `default` down to the selected profile. List lines are added; a `-name`
line drops an entry inherited from a parent; a `profile.conf` variable replaces the parent's
value. A missing parent or a cycle is an error.

The profile is always chosen explicitly with `--profile`; the run header shows the machine model
read from DMI, so a profile run on the wrong machine is visible.

**Why plain files and not YAML:** `yq` is not installed on a fresh Fedora and would have to be
installed before the configuration could even be read. Plain lists read in pure bash and diff
cleanly. Shell-variable files are already the repository's format for `paths.conf` and
`clamav.conf`. The dconf keyfile format round-trips with `dconf dump` and `dconf load` unchanged.

**Why a chain:** packages, Flatpaks, extensions, and GNOME settings are the owner's choices on
every machine, while a few settings (a kernel argument fixing one laptop's audio) belong to one
machine only. Hardware differences that detection can see (GPU vendors, Secure Boot) need no
profile entry at all.

---

## Root And User Steps

The tool always runs as `sudo ./postinstall.sh` from the user's desktop session. The runner takes
the user from `SUDO_USER` (`detect_real_user` in `lib/fs.sh`) and refuses to run from a direct
root login, where it cannot know whose settings to apply.

- `root` steps run directly: dnf configuration, repositories, multimedia, NVIDIA, kernel
  arguments, Flatpaks (installed system-wide), system settings.
- `user` steps run through `runuser` as that user, with `DBUS_SESSION_BUS_ADDRESS` and
  `XDG_RUNTIME_DIR` pointing at the user's session, which `dconf` and `gnome-extensions` need:
  GNOME extensions and dconf settings.

A freshly installed GNOME extension can only be enabled after a re-login. The step reports this as
a pending action in the summary, not as a failure.

---

## Detection

`lib/detect.sh` computes the facts once at startup and prints them in the run header, dry-run
included. Steps query these functions and never call `lspci`, `mokutil`, or similar tools
themselves.

| Function | Source | Values |
|---|---|---|
| `detect_gpu_vendors` | `lspci -n`, display classes, vendor ids | `nvidia`, `intel`, `amd`; several on hybrid laptops |
| `detect_secure_boot` | the `SecureBoot` EFI variable under `/sys/firmware/efi/efivars` | `enabled`, `disabled`, `unsupported` |
| `detect_root_btrfs` | `is_btrfs /` from `lib/fs.sh` | yes / no |
| `detect_desktop` | the `Desktop` property of the user's `loginctl` session | `gnome`, … |
| `detect_virt` | `systemd-detect-virt` | `none`, `kvm`, … |
| `detect_fedora` | `/etc/os-release` | version and variant |
| `detect_machine` | `/sys/class/dmi/id/` | vendor and model |

The tool refuses to run outside Fedora, and below Fedora 45 except with `--dry-run`, so that it can
be tried on an older release without changing it.

**Why:** a step decides from the machine it runs on, never from hard-coded assumptions, which is
what lets one tool serve several machines. Reading the EFI variable directly avoids a dependency on
`mokutil`.

---

## Shared Library

`postinstall/` sources the repository's `lib/` from the checkout (`../lib/`), never the installed
copy in `/usr/local/lib/system-scripts`.

This works on a fresh install: the lib files source each other relative to their own path,
`ui.sh` falls back to plain bash without `gum`, and `color.sh` keeps its default colors when
`/etc/system-scripts/color.conf` does not exist.

**Consequence:** the tool always runs from a checkout of the repository. It would switch to the
installed `LIB_DIR` only if it became a module.

---

## Logging, Dry-Run, Failures

- **Log:** one file per run, `/var/log/postinstall/postinstall-<date>-<time>.log`, written through
  `lib/log.sh`. The runner captures the output of `user` steps, which cannot write there.
- **Dry-run:** `--dry-run` runs `step_applies` and `step_check` normally, since both only read,
  and runs `step_apply` with `run` printing each command instead of executing it. A command that
  depends on an earlier one, such as a package from a repository not yet added, is shown but not
  verified.
- **Failures:** a failed step never stops the run. The closing table gives each step's status and
  duration, then the pending manual actions: re-login, MOK enrollment, reboot when
  `dnf needs-restarting -r` asks for one. The exit code is 1 when at least one step failed.
- **No prompts:** the run is non-interactive (`dnf -y`). The one known exception is MOK enrollment
  for the NVIDIA driver on Secure Boot systems, which asks for a one-time password.

**Why:** the previous script aborted on the first package failure and logged to a location that did
not survive the session. Here one unavailable package or one failing step costs only that step,
and the log of every run is kept.

---

## Versioning

`postinstall/` has its own SemVer version, starting at `0.1.0`, declared in `postinstall.sh`
(`# Version:` header and `readonly POSTINSTALL_VERSION`). Steps have no version of their own:
they are never installed or upgraded separately.

The release tarball (`.github/workflows/release.yml`) does not include `postinstall/`, so, like
documentation, a change to it requires no project version bump. See
[`docs/core/versioning.md`](../docs/core/versioning.md).
