# Shared Library

The shared Bash library installed to `/usr/local/lib/system-scripts/`: an overview, then one
document per file.

## Documents

- [system/lib — Shared Bash Library](overview.md) — the library as a whole, its files and how scripts source them; read first.
- [color.sh — Customizable UI Color Theme](color.md) — color configuration and the `GUM_*` theme; read when changing the interface's colors.
- [config.sh — Centralized Configuration Loading](config.md) — loading `paths.conf` or another config file; read when a script reads shared configuration.
- [core.sh — Base Module](core.md) — colors, typed messages, root and dependency checks, Gum detection; read before writing a script that sources the library.
- [format.sh — Size, Date & Name Formatting](format.md) — human-readable sizes, dates and truncated names; read when formatting output.
- [fs.sh — Filesystem Helpers](fs.md) — mount checks, BTRFS detection, disk usage, sudo-aware user and home; read when a script touches filesystems or resolves the real user.
- [install.sh — Library & Gum Installer](install.md) — the library's installer and the `paths.conf` and `color.conf` it generates; read when changing how the library installs.
- [log.sh — Structured Logging](log.md) — timestamped logging to stdout and a log file; read when a script logs.
- [notify.sh — Notification Registration Helpers](notify.md) — registering notification tags with `notify-daemon`; read when a module sends notifications.
- [paths.sh — Locale-Aware Download Path Detection](paths.md) — download directory detection and `paths.conf`; read when a module needs the user's directories.
- [registry.sh — Module Registry](registry.md) — the registry of installed modules, submodules and versions; read when changing how installs are tracked.
- [submodule.sh — Submodule Engine](submodule.md) — installing and uninstalling submodules from `module.yml`; read before writing a module installer.
- [ui.sh — Interactive UI (Gum + Bash Fallback)](ui.md) — Gum wrappers with a plain bash fallback; read when writing an interactive script.
- [validate.sh — Configuration Validation Helpers](validate.md) — validators that collect every error before reporting; read when validating a config file.
- [yaml.sh — YAML Configuration Parsing via yq](yaml.md) — reading YAML values with `yq`; read when a script reads a YAML config.
