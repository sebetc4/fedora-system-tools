# Backup

The backup module: an overview, one document per submodule, and its shared library.

## Documents

- [Backup Module](overview.md) — the five submodules, how they relate and what they install; read first.
- [Local Backup with Hook System](local.md) — the rsync backup driven by YAML, with its hook system; read when configuring or changing local backups.
- [BTRFS HDD Backup Script - Simple HDD Mirror](hdd.md) — mirroring one HDD to a backup drive with optional snapshots; read for the `hdd` submodule.
- [HDD Split Backup - Two Drive System](hdd-both.md) — splitting a source drive's folders across two backup drives; read for the `hdd-both` submodule.
- [Bitwarden Vault Backup](bitwarden.md) — exporting and encrypting the Bitwarden vault, with rotation; read for the `bitwarden` submodule.
- [backup-lib.sh — Backup module shared library](backup-lib.md) — BTRFS operations, rsync helpers, timeline and archives; read before changing a backup script.
