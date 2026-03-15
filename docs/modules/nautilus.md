# Nautilus Module

Nautilus bookmark & symlink manager for organizing directories in the GNOME
file manager sidebar and a `~/Bookmarks` hierarchy.

## Architecture

```
modules/nautilus/
├── module.yml                          Module metadata
├── install.sh                          Installer (binary + init)
├── uninstall.sh                        Uninstaller (binary only)
└── scripts/
    └── bookmark-manager.sh             CLI + interactive (/usr/local/bin/bookmark-manager)
```

### Installed paths

| File | Path | Purpose |
|------|------|---------|
| CLI binary | `/usr/local/bin/bookmark-manager` | Bookmark & symlink management |
| GTK bookmarks | `~/.config/gtk-3.0/bookmarks` | Nautilus sidebar entries |
| State file | `~/.config/system-scripts/bookmarks.conf` | Tool configuration |
| Managed list | `~/.config/system-scripts/bookmarks.managed` | Tracked bookmark URIs |
| Symlink dir | `~/Bookmarks` | Default symlink directory |

## CLI — `bookmark-manager`

Runs as the current user. No root required (installed by root).

```
bookmark-manager                        Interactive menu
bookmark-manager init                   Initialize ~/Bookmarks directory
bookmark-manager add [dir] [-n name] [-s]   Add bookmark (+ optional symlink)
bookmark-manager remove <name> [-s]     Remove bookmark (+ optional symlink)
bookmark-manager list                   Show bookmarks & symlinks with status
bookmark-manager edit                   Open GTK bookmarks in $EDITOR
bookmark-manager check                  Validate bookmarks & symlinks
bookmark-manager clean                  Remove broken bookmarks & symlinks
bookmark-manager rename <old> <new>     Rename bookmark label + symlink
bookmark-manager info <name>            Show bookmark details (path, git, size)
bookmark-manager open [name]            Open in Nautilus / file manager
bookmark-manager config [show|dir [p]]  View/change settings
bookmark-manager export [file]          Backup bookmarks & symlinks
bookmark-manager import [file]          Restore from backup
bookmark-manager install-completion     Install bash tab completion
bookmark-manager link <sub> {add|remove|list}   Manage symlinks in subdirectories
```

### Command aliases

| Full | Aliases |
|------|---------|
| `add` | `a` |
| `remove` | `rm`, `delete` |
| `list` | `ls`, `l` |
| `edit` | `e` |
| `check` | `verify` |
| `clean` | `prune` |
| `rename` | `mv` |
| `info` | `show` |
| `open` | `o` |
| `link` | `ln` |
| `config` | `cfg` |

### Bookmark management

**Add:**
```bash
bookmark-manager add                        # Bookmark current dir
bookmark-manager add /code/myapp -n MyApp   # Custom name
bookmark-manager add /code/myapp -s         # Bookmark + symlink in ~/Bookmarks
```

**Remove:**
```bash
bookmark-manager remove OldProject
bookmark-manager remove OldProject -s       # Also remove symlink
```

**List output:**
- `●` green — valid bookmark target
- `●` red — broken bookmark (missing target)
- `●` blue — remote URI
- Orphan symlinks shown separately

### Symlink subdirectories

Symlinks can be organized in subdirectories within `~/Bookmarks`:

```bash
bookmark-manager link projects add /code/app -n App
bookmark-manager link projects list
bookmark-manager link projects remove App
```

### Data portability

```bash
bookmark-manager export mybackup.txt        # Export all bookmarks + symlinks
bookmark-manager import mybackup.txt        # Restore (skips existing)
```

Format: `bookmark|file:///path label` and `symlink|name|target`.

### Configuration

Stored in `~/.config/system-scripts/bookmarks.conf` (key=value):

```bash
bookmark-manager config                     # Show config
bookmark-manager config dir                 # Print bookmarks directory
bookmark-manager config dir /custom/dir     # Change directory
```

Environment variable overrides:
- `GTK_BOOKMARKS_FILE` — custom GTK bookmarks path
- `BOOKMARK_STATE_DIR` — custom state directory
- `BOOKMARKS_DIR` — custom symlinks directory

## Install / Uninstall

### Install

1. Installs `bookmark-manager` to `/usr/local/bin/`
2. Runs `bookmark-manager init` as the real user (creates `~/Bookmarks`)
3. Registers in module registry

### Uninstall

1. Removes `/usr/local/bin/bookmark-manager`
2. Unregisters from module registry
3. Preserves user data (`~/Bookmarks`, bookmarks.conf, GTK bookmarks)

## Strict mode

Uses `set -uo pipefail` (omits `-e`). As an interactive tool, errors are handled
explicitly per-command rather than aborting on any failure.

---

*Last Updated: March 9, 2026*
