# Bitwarden Vault Backup

Export and encrypt Bitwarden vault for offline backup with automatic rotation.

## Table of Contents

- [Features](#features)
- [How It Works](#how-it-works)
- [Configuration](#configuration)
- [Usage](#usage)
- [Initial Setup](#initial-setup)
- [Hook Integration](#hook-integration)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Dual export formats** — JSON cleartext encrypted with `age`, and/or Bitwarden native encrypted export
- **Automatic rotation** — oldest backups pruned to configurable retention count
- **Secure cleanup** — all temporary files shredded on exit (trap handler)
- **Dry-run mode** — test config without writing
- **Retry on password mismatch** — encrypted export retries up to 3 times
- **Hook-compatible** — callable standalone or as a `backup-system` pre-backup hook

---

## How It Works

```
1. Decrypt API key        ← age-encrypted file, interactive passphrase
2. Master password input  ← prompted via ui_password
3. Login (API key)        ← BW_CLIENTID + BW_CLIENTSECRET
4. Unlock vault           ← master password → BW_SESSION
5. Export JSON cleartext   ← bw export --format json
6. Encrypt with age       ← age -p (interactive passphrase)
7. Export encrypted JSON   ← bw export --format encrypted_json (interactive password)
8. Rotate old backups     ← keep N newest per retention config
9. Cleanup                ← shred temps, lock vault, logout
```

Steps 5-6 and 7 depend on the `export_mode` config.

---

## Configuration

Default location: `~/.config/backup/bitwarden.yml`

```yaml
bitwarden:
  # Path to age-encrypted API key file
  # Create with: age -p -o <path> bw-api-key.json && shred -u bw-api-key.json
  api_key_path: ~/.secrets/bw-api-key.age

  # Backup destination directory
  backup_path: /media/backup-hdd/backups/bitwarden

  # Number of backup versions to keep (oldest deleted first)
  retention: 3

  # Export mode: both | age_json | encrypted_json
  #   both           - JSON encrypted with age + Bitwarden encrypted export (default)
  #   age_json       - Only JSON export encrypted with age
  #   encrypted_json - Only Bitwarden native encrypted export
  export_mode: both

# Logging (default: ~/.local/log/backup-bitwarden/backup-bitwarden.log)
# Uncomment to override:
# logging:
#   file: /custom/path/backup-bitwarden.log
```

### Export modes

| Mode | Output files | Prompts |
|------|-------------|---------|
| `both` (default) | `.json.age` + `.encrypted.json` | age passphrase + encrypted export password |
| `age_json` | `.json.age` only | age passphrase only |
| `encrypted_json` | `.encrypted.json` only | encrypted export password only |

### Output files

```
bitwarden-2026-03-15-133000.json.age           ← JSON cleartext encrypted with age
bitwarden-2026-03-15-133000.encrypted.json     ← Bitwarden native encrypted (re-importable)
```

---

## Usage

```bash
backup-bitwarden [OPTIONS]
  -c, --config <file>    Config file (default: ~/.config/backup/bitwarden.yml)
  -n, --dry-run          Simulate without making changes
  -h, --help             Show help
```

### Examples

```bash
# Standard interactive backup
backup-bitwarden

# Dry run (test config, no export)
backup-bitwarden -n

# Custom config path
backup-bitwarden -c /path/to/bitwarden.yml
```

---

## Initial Setup

### 1. Install dependencies

```bash
sudo dnf install age jq
# Bitwarden CLI: https://bitwarden.com/help/cli/
```

### 2. Create API key

In Bitwarden web vault: Settings > Security > Keys > API Key. Save the JSON:

```json
{
  "client_id": "user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "client_secret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

### 3. Encrypt API key with age

```bash
age -p -o ~/.secrets/bw-api-key.age bw-api-key.json
shred -u bw-api-key.json
```

### 4. Create config

```bash
mkdir -p ~/.config/backup
cp modules/backup/bitwarden/config.yml ~/.config/backup/bitwarden.yml
# Edit paths to match your setup
```

### 5. Create backup directory

```bash
sudo mkdir -p /media/backup-hdd/backups/bitwarden
```

---

## Hook Integration

`backup-bitwarden` can run as a **pre-backup hook** for `backup-system`:

```yaml
# In ~/.config/backup/system.yml
hooks:
  pre_backup:
    - name: bitwarden
      script: /usr/local/bin/backup-bitwarden
      enabled: true
      confirm: true
      run_as_user: true    # Drop sudo — bw CLI is installed per-user
```

When called as a hook, confirmation is handled by the parent `backup-system` script.

---

## Security

### Sensitive data handling

- API key decrypted to `/tmp`, read, then **shredded immediately**
- JSON export decrypted to `/tmp`, encrypted with age, then **shredded immediately**
- Master password held in memory only, unset after use
- Trap handler ensures cleanup on error, interrupt, or normal exit
- All temp files created with `chmod 600`

### Vault lifecycle

```
Logout (cleanup) → Login → Unlock → Export → Lock → Logout
```

The vault is always locked and logged out on exit, even on error.
A preventive `bw logout` runs before login to handle interrupted previous sessions.

---

## Troubleshooting

### "Bitwarden login failed (invalid API key?)"

Either the API key is wrong, or a previous session was not properly closed.
The script runs `bw logout` before login to handle stale sessions, but if
the issue persists, try `bw logout` manually and retry.

### "Failed to decrypt API key file"

The age passphrase for the API key file is wrong, or the file is corrupted.
Recreate with `age -p -o <path> bw-api-key.json`.

### "Failed to unlock vault (wrong master password?)"

The Bitwarden master password is incorrect. The script does not retry —
run again with the correct password.

### "Encrypted export failed after 3 attempts"

The `bw export --format encrypted_json` command prompts for a password and
confirmation. If they don't match 3 times, the export is aborted.
The JSON+age export (if enabled) is not affected.

### "API key file not found"

The path in `api_key_path` does not exist. Check that the backup drive is mounted
and the path is correct.

---

*Version: 0.1.0*
*Last Updated: March 15, 2026*
