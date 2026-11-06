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
   phases 1, 3, and 8 were adjusted (see Deviations). The detection decision was
   aligned with phase 1's preflight task: below Fedora 45 the tool runs in dry-run only, which
   lets it be tried on this Fedora 44 machine.

Wrote `postinstall/README.md` with the eight decisions and their rationale.

#### Session Close

Fourteen of the fifteen tasks are done; only the Fedora 45 VM remains. The user chose to pause the
roadmap until the Fedora 45 release rather than build the VM from a pre-release image, and is in
no hurry. The inventory in `study/fedora44-inventory/` stays on disk, ignored by git by design.
The architecture work and this record were committed together at the close.

### 2026-10-22

Resumed the phase. `progress.py --check` found two steps the opening had missed: the roadmap
was still under `pending/` and the README's `**Roadmap Status:**` was still 🔴. Moved the folder
to `on-progress/` with `git mv` and set the status to 🟡; no other living document cited the old
path.

Fedora 45 Final was declared NO-GO on 2026-10-15 (no release candidate); 2026-10-27 is the
target, 2026-11-03 the fallback, and the next Go/No-Go meeting is on 2026-10-22 at 17:00 UTC.

### 2026-11-04

Fedora 45 was released on 2026-11-03 (GNOME 51 on Workstation, Plasma 6.7 on the KDE Plasma
Desktop edition, kernel 7.2). RPM signature enforcement and the move of packaged repository files
to `/usr/share/dnf5/repos.d` both landed, as phases 1 and 2 assume.

Reviewed the whole repository with the user; the review is in
`reviews/2026-11-04-repository-review.md` (untracked, `/reviews` is ignored). What matters for this
roadmap: the Legion 7 boots the custom `audio` kernel for its sound, so build-kernel must work on
Fedora 45 before the real-machine run (added to phase 8's dependencies, see
Deviations); and the `nautilus`, `clamav/usb-clamscan` and `backup/vps` modules are the only parts
of the repository tied to a desktop.

Made a usage inventory of the installed modules from the registries, timers, journal (kept since
2026-10-07), logs and the last 1000 shell commands. In use: `torrent`, `build-kernel`,
`notifications`, the `clamav` daily, weekly and download scans, `backup/vps`; used now and then:
`backup/local`, `backup/hdd`, `backup/bitwarden`. Not used or broken: `clamav/usb-clamscan` (all 11
insertions since 2026-10-07 timed out waiting for an auto-mount, no scan ran), `clamav/quarantine`,
`clamav-manage`, `nautilus`, `firewall` (applied once on 2026-03-15), `backup/hdd-both` (not
installed). The user triages the modules before any bug is fixed; modules stay outside this
roadmap's scope.

The user chose to support and test both GNOME and KDE Plasma (see Decisions). The test VM no
longer waits on anything. Added the `[git]` table to `.agent-conventions.toml` with the user
(push `auto`, branch `default`, Conventional Commits), then committed and pushed the folder move
and the table.

Downloaded the Fedora 45 Workstation and KDE Plasma Desktop Live images (1.4) to `/vm/iso`: the
`CHECKSUM` files carry a good signature from the `fedora-45-primary` key, and both images match
their SHA-256.

The user triaged the modules: `torrent`, `notifications` and `backup` stay; ClamAV is refocused on
the entry points; `firewall` becomes a postinstall step; build-kernel stays generic and dormant.
The ClamAV engine detects the EICAR test string, so the absence of positives is not a broken
scanner. Upstream, the AW88399 driver is in mainline from 7.3 on, while the firmware still waits
for `linux-firmware`. The user approved the desktop restructuring and a separate roadmap for the
modules, `fedora45-modules`: both are done.

Defined the VMs `fedora-45-workstation` and `fedora-45-kde` in the `vm-pool` pool: 8 vCPU, 16 GB,
60 GB qcow2, UEFI with Secure Boot and enrolled keys, qcow2 NVRAM so that internal snapshots work.
`fedora-45-kde` booted to its Live Plasma session and was stopped again; `fedora-45-workstation`
has not been started yet. Neither is installed.

Installed both VMs from their Live images, with the default layout the installer proposes: EFI,
ext4 `/boot`, `/` and `/home` as btrfs subvolumes on `vda3`. Both boot Fedora 45 on kernel
`7.2.11-300.fc45` under Secure Boot, in `fr_FR`, and a first desktop session was opened on each
with the account `seb` (administrator). GNOME has its Initial Setup; KDE Plasma has its own first
boot setup, which also asks for the keyboard, and its session runs under `plasmalogin`. The
Workstation installer left the keyboard on `us`: it was set to `fr` AZERTY, as on this machine,
with `localectl` and `gsettings`. No update was applied. Neither VM has a snapshot yet.

The check of `detect_desktop` failed: the `Desktop` property of the `loginctl` session is empty
under GDM, on this Fedora 44 machine and on the Fedora 45 Workstation VM, after a real login too,
while the KDE VM reports `KDE`. As `postinstall/README.md` words it, the function would return
`other` on GNOME and skip every desktop step. The user manager's environment
(`systemctl --user show-environment`) holds `XDG_CURRENT_DESKTOP=GNOME` on this machine; it is the
candidate replacement, not yet tried through `sudo` in either VM.

The guest agent is no way to drive the VMs: it runs confined by SELinux (`virt_qemu_ga_t`), and
`rpm`, `localectl` and `systemctl` on units are denied to it. The installs were therefore driven by
screen captures and a virtual keyboard, which is slow and lost or repeated keys under load. The
user asked for terminal access wherever possible, which means enabling `sshd` in both VMs; the
command that did so was refused by the session's permission classifier, so the choice is the
user's.

The VMs' addresses, the account's password and the virtual keyboard script are kept in
`study/fedora45-vms/` (untracked), since the scratchpad holding the script does not outlive the
session. The session closed before any SSH setup, on the user's request.

### 2026-11-06

Resumed the phase. The host had rebooted on 2026-11-05, so both VMs were stopped; their ISOs were
ejected and they were started again, on the same addresses. The user enabled `sshd` in each VM,
gave `seb` passwordless `sudo` (`/etc/sudoers.d/90-seb-nopasswd`) and installed the host key
`~/.ssh/fedora45-vms` with `ssh-copy-id`: from here on the VMs are driven by SSH (see Decisions).
The `.gitignore` change found at the resume was the user's (`/notes` ignored in place of
`/roadmap`), committed on its own.

Tried `detect_desktop`'s replacement through `sudo` on both VMs, a desktop session open on each.
`runuser -u seb -- systemctl --user show-environment`, with `XDG_RUNTIME_DIR` set, gives
`XDG_CURRENT_DESKTOP=GNOME` on Workstation and `KDE` on Plasma; the graphical `loginctl` sessions
are `Type=wayland`, their `Desktop` empty under `gdm-password` and `KDE` under `plasmalogin`. A
user-scope read through `runuser` with the session's bus works as the root/user split assumes:
`gsettings` returns the `fr+azerty` input source. The Detection decision and
`postinstall/README.md` were corrected.

Powered both VMs off and took an internal snapshot `clean-install` of each, shut off: Fedora 45
with no update, kernel `7.2.11-300.fc45`, Secure Boot enabled, `sshd` enabled and the key
installed. Restore proven on both: a marker written in `/root` after the snapshot is gone after
`virsh snapshot-revert`, the VM boots to its greeter (`gdm` on Workstation, `plasmalogin` on KDE)
and SSH answers by key. The addresses, the key's name and the SSH command are in
`study/fedora45-vms/access.md` (untracked).


---

## Decisions

- **The test VMs are driven by SSH, with passwordless `sudo` for `seb`.** The user asked for
  terminal access wherever possible: the guest agent is confined by SELinux, and the virtual
  keyboard loses keys. `sshd`, the key `~/.ssh/fedora45-vms` and the drop-in
  `/etc/sudoers.d/90-seb-nopasswd` are in the `clean-install` snapshots, so every restore stays
  reachable and `sudo` runs without a password in a command line. Consequence for later phases:
  runs on the VMs never show a `sudo` prompt, which only the real machine exercises.
- **The test VMs are not encrypted.** A passphrase at each boot would block unattended reboots and
  snapshot restores, and they hold nothing sensitive. The real machine stays on LUKS, so these VMs
  validate nothing about it. Their account's throwaway password stays out of the repository.
- **GNOME and KDE Plasma are both supported and tested targets.** The user has two laptops and
  may run one on GNOME and the other on KDE Plasma, and wants quick VM tests of either desktop
  with their own configuration. The `personal` layer therefore holds settings for both desktops,
  and detection, not the machine profile, decides which desktop steps run. Which desktop each
  machine runs on Fedora 45 is left open. This replaces the opening decision "Target: Fedora 45
  Workstation (GNOME)".
- **The `firewall` module becomes a step.** Its hardening is real (the Workstation zone opens
  ports 1025 to 65535 by default, and this machine's zone is reduced to `dhcpv6-client`), but it
  is applied once: a declarative `firewall` step in phase 7 fits it better than a module with a
  wizard, backups and restores. The module's removal is in roadmap `fedora45-modules`.
- **The Legion 7's audio no longer depends on build-kernel.** From kernel 7.3 on the AW88399 driver
  is in mainline; what remains is a firmware step in phase 3 while `linux-firmware` does not ship
  the file. `snd_intel_dspcfg.dsp_driver=3` is dropped from the `legion-7` profile, since the
  driver's documentation advises against it. Adapting build-kernel to Fedora 45 is deferred to its
  first real need.

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
  not require a redesign. Phase 8 loses its `system-tools` step (see Deviations).
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
  `detect_desktop` (`XDG_CURRENT_DESKTOP` in the user's systemd manager environment, read only
  while `loginctl` shows the user an active `wayland` or `x11` session), `detect_virt`
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

## Deviations

- 2026-11-04, adjustments: `phase-3-nvidia-hardware.md`'s Secure Boot task now reads the state
  from `detect_secure_boot` instead of `mokutil --sb-state`, matching the detection decision; a
  task added there decides whether akmods and build-kernel share one MOK key or enroll one each
  (phase 3 goes from 7 to 8 tasks). `phase-8-integration-validation.md` gains a dependency:
  build-kernel working on Fedora 45. Both were overtaken the same day: the MOK task moved to roadmap
  `fedora45-modules`, Phase 6, and the dependency became Fedora's kernel 7.3.
- 2026-11-04, **approved by the user and applied** — desktop restructuring, from the decision to
  support GNOME and KDE Plasma (roadmap scope, phase 6's Objective, a phase file renamed):
  1. `README.md`: the opening decision "Target: Fedora 45 Workstation (GNOME)" becomes "Targets:
     Fedora 45 Workstation (GNOME) and KDE Plasma Desktop, both tested; desktop steps chosen by
     detection"; the out-of-scope line on non-GNOME spins excludes spins other than these two;
     the phase 6 line follows the new title. `postinstall/README.md`'s Target line follows.
  2. Phase 0: the VM task becomes two VMs, Workstation and KDE Plasma Desktop, each from the
     final image, on btrfs, with a clean-install snapshot; its acceptance criterion covers both.
  3. Profile format (phase 0 decision, `postinstall/README.md`): desktop-specific content in a
     profile — `packages.<desktop>.list`, `flatpaks.<desktop>.list`, a `gnome/` folder
     (`extensions.list`, `dconf/*.ini`) and a `kde/` folder (Plasma settings) — loaded only when
     the detected desktop matches; phase 1's profile task says so, and `detect_desktop` returns
     `gnome`, `kde`, or another value for which every desktop step is skipped.
  4. Phase 4: the default packages the personal profile removes are decided per edition.
  5. Phase 5: desktop-specific apps (the GNOME Extension Manager) go to the desktop's list.
  6. Phase 6 becomes "Desktop", file `phase-6-desktop.md` (renamed with `git mv`, links in the
     README and phase 7 repaired). Objective: restore the chosen settings on GNOME and on KDE
     Plasma. GNOME tasks kept as they are. Plasma tasks added: configure Plasma once on the KDE VM
     and select the `~/.config` settings worth keeping, starting from the native equivalents of
     the 9 GNOME extensions; store them in the profile's `kde/` folder as file, group, key and
     value; step `kde-settings` applying them with `kwriteconfig6` as the desktop user and
     checking them with `kreadconfig6`; the panel layout either scripted through Plasma's
     `evaluateScript` or left manual, decided with the user. Acceptance on both VMs, each one
     skipping the other desktop's steps.
  7. Phase 8: the full run and its idempotent second run on both VMs; the real-machine run on the
     desktop the user chooses for the Legion 7.
- 2026-11-04, **approved by the user and applied** — module triage reaching this roadmap: phase 7
  gains the `firewall` step and its Objective and Out of Scope change; phase 3 gains the
  `audio-firmware` step, its Objective changes, and the `kernel-args` task drops
  `snd_intel_dspcfg.dsp_driver=3`; phase 8's dependency and speakers criterion follow.
- The VM task of this phase split in two, one per desktop: the phase goes from 15 to 16 tasks.
- `README.md` no longer links `CLAUDE.md`, which git ignores: the link broke in every other clone.
- 2026-11-04, defect in the Detection decision: `detect_desktop` reads a `loginctl` property that is
  empty under GDM, so it would skip every desktop step on GNOME. Fixed on 2026-11-06: the
  function reads `XDG_CURRENT_DESKTOP` from the user's systemd manager, tried through `sudo` on
  both VMs; the Detection decision and `postinstall/README.md` say so.
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

Phase 0 delivered what the roadmap builds on: an inventory of the Fedora 44 workstation in
`study/fedora44-inventory/` (packages, Flatpaks, GNOME extensions, dconf, `/etc` changes), the
architecture of `postinstall/` written with its rationale in `postinstall/README.md`, and two
Fedora 45 test VMs, Workstation and KDE Plasma Desktop, each with a restorable `clean-install`
snapshot and reachable by SSH. It ran far longer than planned: the wait for the final Fedora 45
image, then a repository review and a module triage that became roadmap `fedora45-modules`, the
GNOME-and-Plasma restructuring of phases 3 to 8, and the move of `firewall` to a phase 7 step.
Trying detection on real installs caught one design defect before any code, the `loginctl`
`Desktop` property empty under GDM; it is fixed.

Phase 1 needs first the step model, the profile format with its desktop-specific files, and
`detect_desktop` reading `XDG_CURRENT_DESKTOP` from the user's systemd manager, all in
`postinstall/README.md`. Its dry-run criterion runs on the VMs over SSH
(`ssh -i ~/.ssh/fedora45-vms seb@<address>`), and a VM is reset, shut off, with
`virsh -c qemu:///system snapshot-revert <vm> clean-install`.
