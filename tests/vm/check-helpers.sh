#!/bin/bash
# =============================================================================
# CHECK-HELPERS - Helpers available to every VM check
# =============================================================================
# Sourced by guest-checks.sh before a module's checks file.
#
# Module: tests
# Requires: none
# Version: 0.1.0
# =============================================================================

# Print the reason a check fails, then fail
fail() {
    echo "$*"
    return 1
}
