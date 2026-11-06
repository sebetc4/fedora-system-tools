#!/bin/bash
# =============================================================================
# GUEST-CHECKS - Run a module's checks inside a test VM
# =============================================================================
# Runs inside a test VM, as the VM's user. Sources a checks file and runs each
# of its check_* functions in a shell of its own, with strict mode, so that a
# check stops at its first failing command. Prints one tab-separated line per
# check: PASS <name>, or FAIL <name> <last line the check printed>.
#
# Omits -e on purpose: a failing check is a result to report, not an error.
#
# A checks file defines check_* functions, which may use the helpers of
# check-helpers.sh such as fail "<reason>", and a KEEP array: glob patterns of
# what may stay after the uninstall.
#
# Module: tests
# Requires: none
# Version: 0.1.0
#
# Usage:
#   bash guest-checks.sh <checks-file>          Run every check
#   bash guest-checks.sh --keep <checks-file>   Print the KEEP patterns
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly HELPERS="$SCRIPT_DIR/check-helpers.sh"

mode="run"
if [[ "${1:-}" == "--keep" ]]; then
    mode="keep"
    shift
fi
readonly CHECKS_FILE="${1:?Usage: guest-checks.sh [--keep] <checks-file>}"

if [[ ! -f "$CHECKS_FILE" ]]; then
    printf 'FAIL\t(checks)\tno checks file: %s\n' "$CHECKS_FILE"
    exit 1
fi

KEEP=()
# shellcheck source=check-helpers.sh
source "$HELPERS"
# shellcheck source=/dev/null
source "$CHECKS_FILE"

if [[ "$mode" == "keep" ]]; then
    if (( ${#KEEP[@]} > 0 )); then
        printf '%s\n' "${KEEP[@]}"
    fi
    exit 0
fi

mapfile -t checks < <(declare -F | awk '$3 ~ /^check_/ { print $3 }')
if (( ${#checks[@]} == 0 )); then
    printf 'FAIL\t(checks)\tno check_* function in %s\n' "$CHECKS_FILE"
    exit 1
fi

failed=0
for check in "${checks[@]}"; do
    output=$(bash -c 'set -euo pipefail; source "$1"; source "$2"; "$3"' \
        _ "$HELPERS" "$CHECKS_FILE" "$check" 2>&1)
    status=$?
    if (( status == 0 )); then
        printf 'PASS\t%s\n' "$check"
    else
        reason=$(tail -n 1 <<< "$output")
        printf 'FAIL\t%s\t%s\n' "$check" "${reason:-exit status $status}"
        failed=1
    fi
done
exit "$failed"
