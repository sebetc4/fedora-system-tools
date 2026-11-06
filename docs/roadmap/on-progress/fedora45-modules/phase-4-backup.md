# Phase 4: Backup

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/7)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Review every backup submodule and prove what matters in a backup: that it restores. Free `vps` from
the desktop's SSH agent, so that it works on both desktops.

### Out of Scope
Changing the backup strategy itself: which data goes where stays the user's.

---

## Tasks

### Local And Disks
- [ ] Review `shared/backup-lib.sh` and `local` against the checklist, its btrfs structure hook included
  Proof: high, test — a restore on a VM gives a tree identical to the source
- [ ] Review `hdd` against the checklist, the mount validation and the `--inplace` and `--partial` options included
  Proof: high, test — on two virtual disks, a mirror restored and an unmounted target refused
- [ ] Review `hdd-both`, installed nowhere today, against the checklist
  Proof: high, test — on virtual disks, the split backup restored, an unmounted target refused

### Bitwarden
- [ ] Review `bitwarden` against the checklist: secret handling, `age` encryption, finding `bw` when it comes from `pnpm`
  Proof: high, test — the export decrypts, and no plaintext remains on disk

### VPS
- [ ] Make `vps` independent of the desktop's SSH agent (`backup-vps.service` hardcodes `%t/gcr/ssh`), deciding with the user between a dedicated key restricted on the server and a configurable socket
  Proof: high, test — the timer runs unattended on the KDE VM against a test SSH target
- [ ] Review the rest of `vps` against the checklist, its GFS rotation included, and move its logrotate template and its log folder's removal from its hooks into `module.yml`, the engine installing a `<name>.tpl` as `/etc/logrotate.d/<user>-<name>` and removing declared folders
  Proof: high, test — rotation on a fixture keeps the expected set and deletes nothing else

### Documentation
- [ ] Update `docs/modules/backup/`, and add a restore procedure for each submodule
  Proof: medium, each procedure followed once on a VM

---

## Technical Details

### Files to Modify
```
modules/backup/
docs/modules/backup/
tests/
```

### Dependencies
Phase 2: the notifications the submodules report through.

### Constraints
Tests use virtual disks and fixtures, never the user's backup disks or the real VPS.
