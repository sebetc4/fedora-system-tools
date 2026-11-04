# Phase 5: Torrent

---

## Status

**Current Status:** 🔴 Not Started (0% — 0/6)
**Started:** {{START_DATE}}
**Completed:** {{COMPLETION_DATE}}
**Blocked By:** —

---

## Objective

Review the user's most used module and prove its security promises: no traffic outside the VPN,
secrets kept out of sight, and downloads scanned, on Fedora 45's Podman.

### Out of Scope
The choice of VPN provider and of torrent client.

---

## Tasks

### Security
- [ ] Verify the kill switch: with `gluetun` stopped or its tunnel down, `qbittorrent` has no network
  Proof: high, test — a connection attempt from the `qbittorrent` container fails in both cases
- [ ] Check the handling of the VPN credentials: Podman secrets, nothing in logs, `ps` or `podman inspect`
  Proof: high, check — a search for a test credential in these outputs finds nothing

### Review
- [ ] Review `torrent.sh`, `torrent-container.sh`, `torrent-list.sh` and `torrent-move.sh` against the checklist
  Proof: medium, the checklist filled in the report
- [ ] Decide with the user whether Quadlet units replace the `podman run` scripts, and apply the decision
  Proof: medium, use — start, stop, export and a reboot on a VM

### Fedora 45
- [ ] Run the stack on Fedora 45's Podman 6 on both VMs
  Proof: medium, use on both VMs
- [ ] Align `torrent-list`'s scan status with the refocused watcher of Phase 3, and update `docs/modules/torrent.md`
  Proof: medium, test — a clean file and EICAR each show the right status

---

## Technical Details

### Files to Modify
```
modules/torrent/
docs/modules/torrent.md
```

### Dependencies
Phase 3: the download watcher covering finished torrents.

### Constraints
The module stays usable throughout: the user's existing containers are not touched until the new
version is proven on a VM.
