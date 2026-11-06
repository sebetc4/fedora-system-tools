# install.sh — Library & Dependencies Installer

> Not a library — this is the installer script for the shared lib. Installs yq and Gum from Fedora's repositories, all `.sh` files to `/usr/local/lib/system-scripts/`, generates `paths.conf` and `color.conf`, and registers lib in the module registry.

**Requires:** root (`sudo`)
**Location:** `lib/install.sh`

---

## Usage

```bash
sudo ./lib/install.sh          # Install yq, Gum and the lib
sudo ./lib/install.sh --no-gum # Install yq and the lib, without Gum (bash fallback mode)
```

---

## What It Does

### 1. Install Dependencies

Installs with `dnf`, in one transaction, the commands missing among:

- `yq`, which parses every `module.yml` and the YAML configs; always installed
- `gum`, which draws the interactive menus; skipped with `--no-gum`, the scripts then using their bash fallback

Both come from Fedora's repositories; no third-party repository is added. Nothing is asked: the
install runs unattended.

### 2. Install Library Files

Copies all 13 lib modules to `/usr/local/lib/system-scripts/` with mode `644`:

`core.sh`, `log.sh`, `config.sh`, `format.sh`, `ui.sh`, `yaml.sh`, `validate.sh`, `fs.sh`, `registry.sh`, `notify.sh`, `submodule.sh`, `paths.sh`, `color.sh`

### 3. Generate `paths.conf`

Creates `/etc/system-scripts/paths.conf` using `paths.sh` if it doesn't already exist. Contains locale-aware download directory paths for the real user (`SUDO_USER`).

### 4. Install `color.conf`

Copies `templates/color.conf.default` to `/etc/system-scripts/color.conf` if it doesn't already exist.

### 5. Register in Registry

Calls `registry_set "lib" "$LIB_VERSION"` to record the installed lib version.
