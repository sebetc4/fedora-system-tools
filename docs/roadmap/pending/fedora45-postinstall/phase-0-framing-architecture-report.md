# Phase 0 Report: Framing & Architecture

**Phase:** [phase-0-framing-architecture.md](phase-0-framing-architecture.md)
**Start Commit:** 4e5e06b

---

## Work Log

### 2026-10-21

Opened the phase. The roadmap, `.agent-conventions.toml`, and the `.gitignore` update were still
untracked, so they were committed first (`4e5e06b`) and the start commit moved there from
`987f697`: this phase's diff holds its own work only.

Decided to wait for the Fedora 45 final image for the VM (see Decisions), so the inventory came
first. It lives in `study/fedora44-inventory/` (ignored by git):

| File | Content |
|---|---|
| `packages.tsv` | 245 packages with reason `User` (132) or `External User` (113): name, arch, EVR, reason, origin repository, `workstation_default` flag, summary |
| `flatpaks.tsv` | 27 apps: 22 from `flathub`, 5 from the `fedora` OCI remote, all system-wide |
| `gnome-extensions.tsv` | 16 extensions, 10 enabled: 9 user-installed, 1 RPM (`user-theme`); 6 disabled |
| `etc-unowned.tsv` | unowned files and symlinks in `/etc/systemd/system`, `/etc/logrotate.d`, `/etc/snapper/configs`, `/etc/dnf/repos.override.d`, `/etc/yum.repos.d` |
| `units-vs-preset.tsv` | system and user units whose state differs from the vendor preset |
| `dconf.ini` | `dconf dump /`, 1159 lines |
| `rpm-va.raw` | `rpm -Va --nodeps --nomtime`, run as root by the user: 37 entries |
| `etc-modified.tsv` | the 14 `/etc` config files `rpm -Va` reports, with flags and owning package |
| `etc-modified/` | copies of the readable modified and unowned config files, under their `/etc` paths |

Export details that matter for the next steps:

- DNF5's `--qf` does not expand `\t`; the query format is passed with `$'...'`. `LC_ALL=C` is
  needed for every export: this system runs in French, and both `dnf` (`<inconnu>`) and
  `gnome-extensions info` (`Chemin:`) localize the fields the scripts parse.
- 125 of the 245 packages have no origin repository (`<unknown>`): installed by the live image or
  carried over by system upgrades. `anaconda-live` and `livesys-scripts` among the `User` packages
  confirm a Live-media install. The `workstation_default` column flags the 9 packages that belong
  to the mandatory or default packages of the `workstation-product-environment` groups.
- `flathub` is Fedora's **filtered** remote (`filtered` option), not the full Flathub.

#### System Facts

- **OS:** Fedora Linux 44 Workstation, GNOME on Wayland, installed from Live media.
- **Root filesystem:** btrfs on LUKS (subvolume `root`).
- **CPU:** Intel Core Ultra 9 275HX, 24 threads.
- **GPU:** hybrid — Intel Arrow Lake-S iGPU (`i915`, `xe` available) and NVIDIA GeForce RTX 5090
  Laptop GPU (GB203M), driver `nvidia` 615.78.08.
- **Secure Boot:** enabled.
- **Kernels:** custom `7.2.11-200.audio.fc44` (running, from `build-kernel`, installed from
  `@commandline`) plus stock `7.2.10-200.fc44` and `7.2.11-200.fc44`. A stale
  `kmod-nvidia-6.18.3-16iax10h.audio` (580.119.02, Fedora 43) is still installed; its module files
  are already gone.
- **NVIDIA stack:** `akmod-nvidia` and `xorg-x11-drv-nvidia-cuda` from RPM Fusion nonfree;
  `kmod-nvidia-*` built locally for every kernel and installed from `@commandline`;
  `nvidia-container-toolkit` from NVIDIA's repository.
- **Kernel arguments:** `rd.driver.blacklist=nouveau,nova_core`,
  `modprobe.blacklist=nouveau,nova_core`, `snd_intel_dspcfg.dsp_driver=3`, `rhgb quiet`.
- **Enabled repositories and owners:**

  | Repository | File | Owner |
  |---|---|---|
  | `fedora`, `updates`, `fedora-cisco-openh264` | `fedora*.repo` | `fedora-repos` |
  | `rpmfusion-free`, `rpmfusion-free-updates` | `rpmfusion-free*.repo` | `rpmfusion-free-release` |
  | `rpmfusion-nonfree`, `rpmfusion-nonfree-updates` | `rpmfusion-nonfree*.repo` | `rpmfusion-nonfree-release` |
  | `rpmfusion-nonfree-nvidia-driver`, `rpmfusion-nonfree-steam`, `google-chrome`, `copr:…:phracek:PyCharm` | their own files | `fedora-workstation-repositories` (files modified locally, `rpm -V` reports `5`) |
  | `code` | `vscode.repo` | unowned |
  | `cuda-fedora44-x86_64` | `cuda-fedora44.repo` | unowned (`cuda-fedora43.repo` also left, disabled) |
  | `nvidia-container-toolkit` | `nvidia-container-toolkit.repo` | unowned |

- **Repository overrides** (`/etc/dnf/repos.override.d/99-config_manager.repo`): CUDA repositories
  exclude every NVIDIA driver package (`nvidia-*`, `kmod-nvidia*`, `xorg-x11-*nvidia*`,
  `libnvidia-*`, `dnf-plugin-nvidia`) so the driver comes from RPM Fusion only;
  `cuda-fedora43-x86_64` is disabled.
- **`/etc/dnf/dnf.conf`:** `max_parallel_downloads=10`, `defaultyes=True`, `countme=false`,
  `installonly_limit=3`. `countme=false` has no effect: `fedora.repo` and `fedora-updates.repo`
  set `countme=1` per repository, which wins — the old script's `countme` defect, confirmed.
- **Installed groups:** environment `workstation-product-environment`; groups
  `container-management`, `desktop-accessibility`, `libreoffice`.
- **Unowned units and configs from fedora-system-tools:** the clamav units and timers, the
  `watch-downloads` drop-in, logrotate files for backup, `build-kernel`, clamav, notifications and
  user logs, plus the user units `backup-vps` and `notify-daemon`. Also unowned:
  `btrfs-balance.timer.d` and `btrfs-scrub.timer.d` schedule drop-ins, and the snapper configs
  `root` and `home`.
- **Units differing from their preset:** enabled by hand — `libvirtd` and its sockets,
  `clamav-freshclam`, the btrfs and snapper timers, the clamscan timers; disabled against the
  preset — `systemd-oomd`, `systemd-homed`, `systemd-pstore`, `lvm-devices-import`, among others.

A first `rpm -Va` run as the user was useless: 1828 of 1920 entries were `Permission denied`.
`sudo` asks for a password, so the user ran it as root; 37 entries remain.

#### Modified `/etc` Files

Content changed (`5` flag), with the owner each one points to:

- `/etc/dnf/dnf.conf` — the `dnf-config` step (phase 1).
- `/etc/yum.repos.d/` `google-chrome`, `rpmfusion-nonfree-nvidia-driver`, `rpmfusion-nonfree-steam`,
  `copr:…:phracek:PyCharm` — packaged files of `fedora-workstation-repositories` edited in place to
  enable them, which the Fedora 45 constraint forbids: phase 2 enables them with
  `dnf config-manager setopt`.
- `/etc/sysconfig/btrfsmaintenance` — weekly balance of `/` (`dusage` 5 10, `musage` 5), monthly
  scrub, no defrag, no trim; plus unowned `OnCalendar` drop-ins for `btrfs-balance.timer` and
  `btrfs-scrub.timer` (phase 7).
- `/etc/sysconfig/snapper` — `SNAPPER_CONFIGS="root home"`; the configs themselves are root-only
  and were not copied (phase 7 reads them with `sudo`).
- `/etc/clamd.d/scan.conf` — written by the clamav module (`modules/clamav/scripts/core/configure-clamav.sh`).
- `/etc/pesign/users`, `/etc/pki/pesign/cert9.db`, `/etc/pki/pesign/key4.db` — the kernel signing
  key database used by the build-kernel module (`modules/build-kernel/scripts/lib/signing.sh`).
  Key material: not copied, and out of this roadmap's scope with the rest of build-kernel's
  Fedora 45 adaptation.
- `/etc/sysconfig/livesys` — Live-media leftover, nothing to carry over.

Mode only (`M` flag), content unchanged: `/etc/default/grub`, `/etc/sysconfig/irqbalance`.

Outside `/etc`: the module directory of the stale 6.18.3 `kmod-nvidia` is missing, and
`alsa-ucm`'s `HiFi-analog.conf` and `HiFi-mic.conf` under `/usr/share/alsa/ucm2/HDA/` are
modified — a local audio fix that a package update would silently revert. The user confirmed its
owner: the build-kernel `aw88399` hook (`modules/build-kernel/hooks/aw88399/lib/resources.sh`,
`install_ucm2`), out of this roadmap's scope with the rest of build-kernel. The related kernel
argument `snd_intel_dspcfg.dsp_driver=3` is managed by no code of the repository; phase 3's
`kernel-args` step already plans it for the personal profile.

#### Architecture

The decisions were proposed two at a time and approved by the user (see Decisions):

1. Layout and step model. The user rejected the proposed `90-fedora-system-tools.sh` step: its
   installation is simple and handled separately, and `postinstall/` may later become a
   fedora-system-tools module. Phase 8 lost its `system-tools` task, with the user's approval.
   Personal profile named `legion-7`.
2. Profile format and root/user split, approved as proposed. Reading `lib/fs.sh` confirmed
   `detect_real_user` is there to reuse.
3. Detection, `lib/` reuse, logging/dry-run/failures, versioning. Checked before proposing: the lib
   files source each other relatively, `color.sh` tolerates a missing `color.conf`, and the release
   tarball leaves `postinstall/` out. Approved; the user then set the goal of using the tool on
   several devices, naming a Legion 5 15IMH05H (Intel Core i7, RTX 2060).
4. Multi-device: the single `legion-7` profile became the chain `default` → `personal` → machine
   profile, with `legion-5` created but validated after this roadmap. The roadmap's scope and
   phases 1, 3, and 8 were adjusted (see Changes To Later Phases). The detection decision was
   aligned with phase 1's preflight task: below Fedora 45 the tool runs in dry-run only, which
   lets it be tried on this Fedora 44 machine.

Wrote `postinstall/README.md` with the eight decisions and their rationale.

#### Session Close

Fourteen of the fifteen tasks are done; only the Fedora 45 VM remains. The user chose to pause the
roadmap until the Fedora 45 release rather than build the VM from a pre-release image, and is in
no hurry. The inventory in `study/fedora44-inventory/` stays on disk, ignored by git by design.
The architecture work and this record were committed together at the close.

**Where the next session starts:**
1. After the Fedora 45 release (2026-10-27): download the Fedora 45 Workstation final image,
   create the VM in virt-manager on btrfs, and take the clean-install snapshot — the last task
   of phase 0.
2. Close phase 0: the VM acceptance criterion is the one left; the inventory and README criteria
   are met. Then open phase 1.
- No question is waiting for the user.
- Nothing is left uncommitted.


---

## Decisions

- **The inventory lives in `study/fedora44-inventory/`, inside the checkout but ignored by git.**
  The phase first planned a folder outside the repository; the user preferred keeping it at hand in
  the checkout. `/study` is already in `.gitignore`, so the personal data it holds is never
  committed. Phases 4 to 7 read the inventory from there.
- **The test VM is built from the Fedora 45 final release image (2026-10-27), not a Beta or RC.**
  The VM is first needed by phase 1's dry-run criterion, and the inventory and architecture work
  fills the days before the release; building it once from the final image avoids redoing it. The
  VM task is therefore done last in this phase.
- **No post-install step installs fedora-system-tools.** Its installation is already simple and
  handled by `make` or `setup.sh`, and `postinstall/` may later become a fedora-system-tools module
  itself. `postinstall/` therefore stays self-contained, so that a later move into `modules/` does
  not require a redesign. Phase 8 loses its `system-tools` step (see Changes To Later Phases).
- **Profiles in three levels, for several machines.** `default` (any Fedora 45), `personal` (the
  user's choices shared by all their machines: packages, Flatpaks, extensions, dconf), and one
  profile per machine holding only what detection cannot infer: `legion-7` (this workstation,
  Legion 7 with RTX 5090) and `legion-5` (Legion 5 15IMH05H, Intel Core i7, RTX 2060). Each
  `profile.conf` names its `PARENT`; the chain `default → personal → legion-7` loads in that
  order with the merge rules of the profile format below. The profile is chosen explicitly
  (`--profile legion-7`), and the run header shows the machine model so a wrong profile is
  visible. This replaces the single `legion-7` personal profile decided first the same day, after
  the user set the goal of using the tool on several devices. Only the Legion 7 and the VM are
  validated in this roadmap; the Legion 5 run comes later.
- **Layout of `postinstall/`.** One entry point `postinstall.sh`; `lib/` for the tool's own
  helpers (`runner.sh`, `detect.sh`, `run.sh`), the repository's `lib/` reused beside them for
  output, logging, and btrfs detection; `steps/` with one file per step; `profiles/default/` and
  `profiles/legion-7/`; `README.md`. Steps are ordered by a numeric filename prefix with gaps
  (`10-dnf-config.sh` … `80-system-settings.sh`) and selected by their name without the prefix
  (`postinstall.sh packages flatpaks`). Rationale: the order is visible in a directory listing and
  a step can be inserted without renumbering.
- **Step model.** A step file declares `STEP_NAME` and `STEP_SCOPE` (`root` or `user`) and three
  functions: `step_applies` (does the step concern this machine, from detection), `step_check`
  (read-only: is the target state already reached), and `step_apply` (makes the changes, every
  mutation through the `run` helper). The runner reports each step as skipped (with the reason),
  already compliant, changed, or failed; `step_apply` runs in a subshell, so a failure stops that
  step only, and a summary table ends the run. Rationale: `step_check` gives idempotence, and
  routing every mutation through `run` gives a dry-run that walks the same code path and prints
  the commands instead of running them. Phases 1 to 7 write their steps against this contract.
- **Profile format: plain files, one per concern, no YAML.** A profile folder holds
  `profile.conf` (shell variables: `KERNEL_ARGS`, `TUNED_PROFILE`, `REPOS`…), `packages.list` (one
  name per line, `-name` to remove), `flatpaks.list` (app ids), `extensions.list` (UUIDs), and
  `dconf/*.ini` (the `dconf dump` format, applied with `dconf load`). The `PARENT` chain is loaded
  from `default` down to the selected profile: list lines are added, a `-name` line drops an entry of `default`, and
  `profile.conf` variables replace those of `default`. Rationale: `yq` is not installed on a fresh
  Fedora and would have to be installed before the configuration can be read; plain lists read in
  pure bash and diff cleanly; shell-variable files already serve `paths.conf` and `clamav.conf`;
  the dconf keyfile format round-trips with `dconf dump` and `dconf load` unchanged.
- **Root/user split.** The tool always runs as `sudo ./postinstall.sh` from the user's session;
  the runner takes the user from `SUDO_USER` (`detect_real_user` in `lib/fs.sh`) and refuses a
  direct root login, where it cannot know whose settings to apply. `root` steps run directly: dnf,
  repositories, NVIDIA, kernel arguments, Flatpaks (system-wide, as today), system settings.
  `user` steps run through `runuser` as that user, with `DBUS_SESSION_BUS_ADDRESS` and
  `XDG_RUNTIME_DIR` pointing at the session, which `dconf` and `gnome-extensions` need: GNOME
  extensions and dconf settings. A freshly installed extension can only be enabled after a
  re-login; the step reports it as a pending action in the summary, not as a failure.
- **Hardware detection (`lib/detect.sh`).** Facts are computed once at startup and printed in the
  run header, dry-run included; steps query them and never call `lspci` or `mokutil` themselves.
  `detect_gpu_vendors` (`lspci -n` display classes, vendor ids; several on hybrid laptops),
  `detect_secure_boot` (the `SecureBoot` EFI variable under `/sys`: `enabled`, `disabled`,
  `unsupported`; no `mokutil` dependency), `detect_root_btrfs` (`is_btrfs /` from `lib/fs.sh`),
  `detect_desktop` (the `Desktop` property of the user's `loginctl` session), `detect_virt`
  (`systemd-detect-virt`, for the test VM), `detect_fedora` (`/etc/os-release`), `detect_machine`
  (vendor and model from `/sys/class/dmi/id/`, shown in the header). The tool refuses
  to run outside Fedora or below Fedora 45, except with `--dry-run`, so that it can be tried on
  the current Fedora 44 machine; this matches phase 1's preflight task.
- **`lib/` comes from the checkout.** `postinstall/` sources `../lib/`, never
  `/usr/local/lib/system-scripts`. Checked: the lib files source each other relative to their own
  path, `ui.sh` falls back to plain bash without `gum`, and `color.sh` keeps its defaults when
  `/etc/system-scripts/color.conf` is absent. Consequence: the tool always runs from a checkout;
  it would switch to `LIB_DIR` only if it became a module.
- **Logging, dry-run, failure policy.** One log per run,
  `/var/log/postinstall/postinstall-<date>-<time>.log`, through `lib/log.sh`; the runner captures
  the output of `user` steps, which cannot write there. `--dry-run` runs `step_applies` and
  `step_check` normally and `step_apply` with `run` printing instead of executing; a command that
  depends on an earlier one (a package from a repository not yet added) is shown but not
  verified. A failed step never stops the run; the closing table gives each step's status and
  duration, then the pending manual actions (re-login, MOK enrollment, reboot when
  `dnf needs-restarting -r` asks for it); the exit code is 1 when a step failed. The run is
  non-interactive (`dnf -y`); the only known exception is MOK enrollment in phase 3, which asks
  for a password.
- **Versioning.** `postinstall/` has its own SemVer version, starting at `0.1.0`, in
  `postinstall.sh` (`# Version:` header and `readonly POSTINSTALL_VERSION`); steps carry no
  version of their own, since they are never installed separately. The release tarball
  (`.github/workflows/release.yml`) does not include `postinstall/`, so, like documentation, a
  change to it requires no project version bump; a line in `docs/core/versioning.md` will say so.


---

## Files Changed



---

## Problems And Deviations



---

## Changes To Later Phases

- `phase-8-integration-validation.md`, **approved by the user on 2026-10-21** (restructuring: a
  task removed without being moved, and the Objective changed): removed the task "Step
  `system-tools`: run `make install-lib`, then install the profile's modules and submodules with
  `setup.sh --install` from the checkout"; the Objective no longer installs fedora-system-tools;
  the `### fedora-system-tools Integration` subsection is now `### Bootstrap`;
  `postinstall/steps/ (system-tools)` left Files to Modify; the first acceptance criterion lists
  the fedora-system-tools install among the documented manual steps. Phase 8 goes from 7 to 6
  tasks, the roadmap from 77 to 76. The README phase list line was reworded to match.
- `README.md`, **approved by the user on 2026-10-21** (restructuring: the roadmap's scope): the
  tool serves several machines through a `personal` layer and one profile per machine; "Why This
  Roadmap Exists" says so, and "Deliberately Out Of Scope" now excludes the Legion 5's real run.
- `phase-1-core-framework.md`: the task "Create the generic default profile and the personal
  profile skeleton" now creates the chain `default` → `personal` → `legion-7` and `legion-5`
  skeletons, loaded through `PARENT`, with cycle and missing-parent errors. Added the task
  "Declare `POSTINSTALL_VERSION` (`0.1.0`) in `postinstall.sh`, and add `postinstall/` to
  `docs/core/versioning.md`…", which carries out the versioning decision; phase 1 goes from 13
  to 14 tasks, the roadmap from 76 to 77.
- `phase-3-nvidia-hardware.md`: `snd_intel_dspcfg.dsp_driver=3` moves from the personal profile
  to `legion-7`, since it fixes this laptop's audio; the CUDA, `gcc15`, and
  `nvidia-container-toolkit` decision now also says which level they belong to.
- `phase-8-integration-validation.md`: "the personal profile applied" becomes "the `legion-7`
  profile applied", in What It Enables and in the acceptance criteria.


---

## Assessment

