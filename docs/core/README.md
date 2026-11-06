# Core

The conventions and mechanisms every part of the project shares.

## Documents

- [Conventions](conventions.md) — strict mode and arithmetic under `set -e`, colors, the real user under `sudo`, installers and personal settings; read before writing or reviewing a script.
- [Logrotate](logrotate.md) — log rotation for system-level and user-level modules; read when a module writes logs.
- [Module Review](module-review.md) — the checklist a module is reviewed against and what passing each item means; read before reviewing or finishing a module.
- [setup.sh — Interactive System Tools Manager](setup.md) — the interactive menu and CLI flags of `setup.sh`; read to install, upgrade or inspect modules through it.
- [State, Configuration & Installed Paths](state-and-paths.md) — every file the project installs, generates or manages; read before adding or removing an installed file.
- [Testing](testing.md) — the `bats` unit tests and the VM harness that runs a module's install cycle on both test VMs; read before writing a test or validating a module.
- [Versioning](versioning.md) — SemVer across lib, module and submodule, and when each is bumped; read before a version bump or a release.
