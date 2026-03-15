# install.sh — Library & Gum Installer

> Not a library — this is the installer script for the shared lib. Installs all `.sh` files to `/usr/local/lib/system-scripts/`, optionally installs Gum, generates `paths.conf` and `color.conf`, and registers lib in the module registry.

**Requires:** root (`sudo`)
**Location:** `lib/install.sh`

---

## Usage

```bash
sudo ./lib/install.sh          # Install lib + Gum
sudo ./lib/install.sh --no-gum # Install lib only (bash fallback mode)
```

---

## What It Does

### 1. Install Library Files

Copies all 13 lib modules to `/usr/local/lib/system-scripts/` with mode `644`:

`core.sh`, `log.sh`, `config.sh`, `format.sh`, `ui.sh`, `yaml.sh`, `validate.sh`, `backup.sh`, `registry.sh`, `notify.sh`, `submodule.sh`, `paths.sh`, `color.sh`

### 2. Install Gum

Unless `--no-gum` is passed:
- Skips if already installed
- Tries `dnf` (Fedora/RHEL) with Charm repo
- Falls back to `apt-get` (Debian/Ubuntu) with Charm repo
- Warns if no supported package manager found

### 3. Generate `paths.conf`

Creates `/etc/system-scripts/paths.conf` using `paths.sh` if it doesn't already exist. Contains locale-aware download directory paths for the real user (`SUDO_USER`).

### 4. Install `color.conf`

Copies `templates/color.conf.default` to `/etc/system-scripts/color.conf` if it doesn't already exist.

### 5. Register in Registry

Calls `registry_set "lib" "$LIB_VERSION"` to record the installed lib version.
