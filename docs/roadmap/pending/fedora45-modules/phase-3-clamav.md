# Phase 3: ClamAV

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/9)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Fix the confirmed bugs, refocus ClamAV on where files enter the machine (downloads, finished
torrents, USB drives, on-demand scans), and make it cost nothing while idle.

### Out of Scope
Threats ClamAV cannot see, such as malicious npm or pip packages and browser extensions.

---

## Tasks

### Fixes
- [ ] Fix the counters that abort `quarantine list`, its interactive menu, `quarantine purge` and `clamav-manage diagnose`
  Proof: high, test — `purge` with two confirmed files deletes both, `list` shows every file and `diagnose` reports every problem, each watched failing first

### Refocus
- [ ] Remove the `daily-clamscan` submodule, its service and its timer: it repeats the download watcher
  Proof: medium, check — after an install on a VM, no `daily-clamscan` unit exists
- [ ] Reduce `weekly-clamscan` to the user's data: system files come from signed RPMs, and `rpm -Va` checks them better
  Proof: medium, a run's log lists only the user's directories
- [ ] Cover finished torrents in the download watcher's `WATCH_DIRS`: `README.md` announces this integration, while `torrent` only displays a scan status
  Proof: high, test — EICAR in the finished downloads folder is quarantined
- [ ] Run `clamd` on demand: started by the first scan, stopped after an idle delay, with no scan lost while it loads
  Proof: medium, a measure — no `clamd` process while idle, and a file arriving meanwhile is scanned
- [ ] Add community signatures with Fedora's `clamav-unofficial-sigs`, after checking its sources and its false positives on the user's files
  Proof: medium, a scan of the user's downloads with them reports no false positive

### USB
- [ ] Find why all 11 insertions since 2026-10-07 timed out, then make `usb-clamscan` independent of the desktop's auto-mount, mounting read-only itself when nothing else has
  Proof: high, test — EICAR on a USB disk passed through to each VM is detected, with and without an open session

### End To End
- [ ] Test the whole chain with EICAR on both VMs: watcher, quarantine, notification, then the `quarantine` commands
  Proof: high, test — EICAR reaches the quarantine, the notification shows, and `quarantine` lists and deletes it
- [ ] Review the remaining scripts, units and SELinux rules against the checklist, and update `docs/modules/clamav.md`
  Proof: medium, the checklist filled in the report

---

## Technical Details

### Files to Modify
```
modules/clamav/
modules/clamav/module.yml
docs/modules/clamav.md
tests/
```

### Dependencies
Phase 2: the notifications the scanners report through.

### Constraints
- Tests use the EICAR test string only, never real malware.
- A scanner's failure is reported, never taken for a clean result.
