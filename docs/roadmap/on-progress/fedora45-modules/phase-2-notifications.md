# Phase 2: Notifications

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** roadmap `review-skill`

---

## Objective

Review the notifications module, which every other module reports through, and prove it on both
desktops. It relies on the freedesktop notification standard, so it should need no desktop-specific
code.

### Out of Scope
The notification tags other modules register, reviewed with those modules.

---

## Tasks

### Review
- [ ] Review `notify-daemon`, `notify-manage` and `check-notify-dependencies` against the checklist, with `bats` tests for the level filtering
  Proof: medium, test — each level's filtering watched failing then passing
- [ ] Limit what the daemon logs (`notify-daemon.log` holds 12,842 lines here, many of them `Filtered:`) and check its rotation
  Proof: medium, a measure of the log's growth over a day's messages, before and after
- [ ] Set with the user the default notification level of each tag
  Proof: low, the user's review
- [ ] Make the uninstall remove what the install created and the harness finds left: the empty `~/.config/systemd/user` and `~/.local/log` folders, removed only when empty
  Proof: medium, test — `tests/vm/run.sh notifications` passes on both VMs

### Validation
- [ ] Send a tagged `logger` line end to end on both VMs: it reaches the desktop with its icon, under Adwaita and Breeze
  Proof: medium, use on both VMs
- [ ] Update `docs/modules/notifications.md`
  Proof: low, the page read against the module's behavior

---

## Technical Details

### Files to Modify
```
modules/notifications/
lib/notify.sh
docs/modules/notifications.md
tests/
```

### Dependencies
Phase 1: the shared foundation.

### Constraints
No desktop-specific code unless a VM shows it is needed.
