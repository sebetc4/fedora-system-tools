# validate.sh — Configuration Validation Helpers

> Error-accumulating validators for configuration values. Collects all errors before displaying them together and exiting.

**Guard:** `_LIB_VALIDATE_LOADED`
**Dependencies:** `core.sh`
**Sourced by:** backup scripts (config validation)

---

## Usage Pattern

```bash
source "$LIB_DIR/validate.sh"

validation_reset
validate_required "backup.mount"       "$MOUNT"
validate_boolean  "snapshots.enabled"  "$ENABLE_SNAPSHOTS"
validate_integer  "snapshots.retention" "$RETENTION"
validate_path     "backup.destination" "$DEST"
validation_check "config.yml"
# If errors: prints all, then exits 1
# If clean: continues silently
```

---

## Functions

### `validation_reset`

Clear the error accumulator. Call before each validation pass.

### `validation_add_error message`

Manually add an error message to the accumulator.

```bash
validation_add_error "SSH key not found at $KEY_PATH"
```

### `validation_check [label]`

If any errors accumulated, display them all with red `✗` markers and exit 1. Optional `label` shows the config file path in the output. Returns 0 if no errors.

### `validate_required key value`

Error if `value` is empty.

### `validate_boolean key value`

Error if `value` is not `true` or `false`. Accepts empty (skips validation).

### `validate_integer key value`

Error if `value` is not a positive integer (`^[0-9]+$`). Accepts empty (skips validation).

### `validate_path key value`

Error if `value` does not start with `/`. Accepts empty (skips validation).

### `validate_pattern key value pattern [hint]`

Error if `value` does not match the given regex pattern. Optional `hint` replaces the default error message.

```bash
validate_pattern "backup.schedule" "$SCHEDULE" '^(daily|weekly|monthly)$' \
    "must be daily, weekly, or monthly"
```
