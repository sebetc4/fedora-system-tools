#!/bin/bash
# =============================================================================
# RUN - Run a module's install cycle on the Fedora test VMs
# =============================================================================
# For each test VM: restores its snapshot, copies the checkout with
# my-config-fixture/ as its my-config/, installs the prerequisites and the
# library, installs the module twice with its checks after each install,
# uninstalls it, and compares the VM before and after.
# Prints one table per desktop and exits 1 when any step failed.
#
# Acts only on the VMs listed in vms.conf, never on the host, and never
# changes their snapshots. Prompts get their default answer (Enter).
#
# Module: tests
# Requires: core
# Version: 0.2.0
#
# Usage:
#   tests/vm/run.sh [OPTIONS] <module>[/<submodule>]
#
# Options:
#   --vm <domain>   Run on this VM only (repeatable; default: every VM listed)
#   --keep          Leave each VM running after its run
#   -h, --help      Show help
#
# Environment:
#   VM_USER         Account in the VMs (default: $USER)
#   VM_SSH_KEY      Its SSH key (default: ~/.ssh/fedora45-vms)
#   VM_CONF         VM list (default: tests/vm/vms.conf)
#   VM_SNAPSHOT     Snapshot restored before each run (default: clean-install)
# =============================================================================

set -euo pipefail
trap 'echo "ERROR: VM harness failed at line $LINENO" >&2; exit 1' ERR

# virsh prints states in the user's language, and comm needs one collation
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
readonly REPO_DIR

source "$REPO_DIR/lib/core.sh"

# ===================
# Configuration
# ===================
readonly LIBVIRT_URI="qemu:///system"
readonly VM_USER="${VM_USER:-$USER}"
readonly VM_SSH_KEY="${VM_SSH_KEY:-$HOME/.ssh/fedora45-vms}"
readonly VM_CONF="${VM_CONF:-$SCRIPT_DIR/vms.conf}"
readonly VM_SNAPSHOT="${VM_SNAPSHOT:-clean-install}"
readonly PREREQS_FILE="$SCRIPT_DIR/prereqs.list"
readonly GUEST_DIR="fedora-system-tools-test"   # in the VM user's home
# Generic copies standing for the user's, never the host's own my-config/
readonly MY_CONFIG_FIXTURE="tests/vm/my-config-fixture"
readonly BOOT_TIMEOUT=300
readonly SHUTDOWN_TIMEOUT=120

readonly SSH_OPTS=(
    -i "$VM_SSH_KEY"
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o StrictHostKeyChecking=accept-new
    -o LogLevel=ERROR
)

# ===================
# Functions
# ===================
show_help() {
    sed -n '/^# Usage:/,/^# =====/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^# \{0,1\}//'
}

vsh() {
    virsh -q -c "$LIBVIRT_URI" "$@"
}

# vm_ssh <address> <command>: run a command in the VM as VM_USER
vm_ssh() {
    local address="$1"
    shift
    # shellcheck disable=SC2029  # the command is built here on purpose
    ssh "${SSH_OPTS[@]}" "$VM_USER@$address" "$@"
}

# --- step records of the current VM ---
STEP_NAMES=()
STEP_STATUS=()
STEP_SECS=()
STEP_DETAIL=()

record() {
    STEP_NAMES+=("$1")
    STEP_STATUS+=("$2")
    STEP_SECS+=("$3")
    STEP_DETAIL+=("$4")
}

# step <name> <detail-on-success> <command...>: run a command with its output
# in <name>.log, and record its result
step() {
    local name="$1" detail="$2"
    shift 2
    local start=$SECONDS
    if "$@" > "$RUN_DIR/$name.log" 2>&1; then
        record "$name" PASS $((SECONDS - start)) "$detail"
        return 0
    fi
    record "$name" FAIL $((SECONDS - start)) "see $name.log"
    return 1
}

skip_rest() {
    local name
    for name in "$@"; do
        record "$name" SKIP 0 ""
    done
}

# --- VM lifecycle ---
wait_shut_off() {
    local domain="$1" waited=0
    while [[ "$(vsh domstate "$domain")" != "shut off" ]]; do
        if (( waited >= SHUTDOWN_TIMEOUT )); then
            return 1
        fi
        sleep 2
        waited=$((waited + 2))
    done
}

stop_vm() {
    local domain="$1"
    [[ "$(vsh domstate "$domain")" == "shut off" ]] && return 0
    vsh shutdown "$domain" > /dev/null
    if ! wait_shut_off "$domain"; then
        echo "no clean shutdown after ${SHUTDOWN_TIMEOUT}s: powering off"
        vsh destroy "$domain" > /dev/null
        wait_shut_off "$domain"
    fi
}

# Run by step, where set -e does not apply: each command checks the last
# shellcheck disable=SC2329  # invoked through step
reset_vm() {
    local domain="$1"
    stop_vm "$domain" || return 1
    vsh snapshot-revert "$domain" "$VM_SNAPSHOT" || return 1
    vsh start "$domain"
}

# Print the VM's IPv4 address once it answers over SSH
wait_for_ssh() {
    local domain="$1" waited=0 address=""
    while (( waited < BOOT_TIMEOUT )); do
        address=$(vsh domifaddr "$domain" --source lease 2>/dev/null \
            | awk '$3 == "ipv4" { sub(/\/.*/, "", $4); print $4; exit }')
        if [[ -n "$address" ]] && vm_ssh "$address" true < /dev/null 2>/dev/null; then
            echo "$address"
            return 0
        fi
        sleep 3
        waited=$((waited + 3))
    done
    return 1
}

# Copy the files git tracks or sees as new, as they are in the working tree,
# and the fixture as the checkout's my-config/
# shellcheck disable=SC2329  # invoked through step
copy_checkout() {
    local address="$1"
    (
        cd "$REPO_DIR"
        git ls-files -z --cached --others --exclude-standard \
            | while IFS= read -r -d '' file; do
                if [[ -e "$file" ]]; then
                    printf '%s\0' "$file"
                fi
            done \
            | tar --null -T - -czf -
    ) | vm_ssh "$address" "rm -rf ~/$GUEST_DIR && mkdir ~/$GUEST_DIR && tar -xzf - -C ~/$GUEST_DIR \
        && { [[ ! -d ~/$GUEST_DIR/$MY_CONFIG_FIXTURE ]] || cp -a ~/$GUEST_DIR/$MY_CONFIG_FIXTURE ~/$GUEST_DIR/my-config; }"
}

# shellcheck disable=SC2329  # invoked through step
install_prereqs() {
    local address="$1"
    shift
    (( $# == 0 )) && return 0
    vm_ssh "$address" "sudo dnf install -y $*" < /dev/null
}

# guest_make <address> <target>: run a make target in the VM's checkout
# shellcheck disable=SC2329  # invoked through step
guest_make() {
    local address="$1" target="$2"
    vm_ssh "$address" "cd ~/$GUEST_DIR && NONINTERACTIVE=1 make $target" < <(yes '')
}

save_state() {
    local address="$1" label="$2"
    vm_ssh "$address" "sudo bash ~/$GUEST_DIR/tests/vm/guest-state.sh $VM_USER" \
        < /dev/null > "$RUN_DIR/state-$label.txt"
}

# run_checks <address> <name>: run the module's checks, with a summary in CHECK_DETAIL
run_checks() {
    local address="$1" name="$2" results passed total failures
    results="$RUN_DIR/$name.txt"
    if vm_ssh "$address" "cd ~/$GUEST_DIR && bash tests/vm/guest-checks.sh $CHECKS_FILE" \
        < /dev/null > "$results" 2> "$RUN_DIR/$name.log"; then
        :
    fi
    total=$(grep -cE '^(PASS|FAIL)' "$results" || true)
    passed=$(grep -c '^PASS' "$results" || true)
    failures=$(awk -F'\t' '$1 == "FAIL" { printf "%s%s (%s)", sep, $2, $3; sep = "; " }' "$results")
    CHECK_DETAIL="$passed/$total passed${failures:+: $failures}"
    [[ "$total" -gt 0 && "$passed" -eq "$total" ]]
}

# --- leftovers ---
# Print the entries of a state file whose kind is one of <kinds> (f, d, l, h, u, g)
state_paths() {
    awk -F'\t' -v kinds="$2" 'index(kinds, $1) { print $NF }' "$1" | sort -u
}

matches_keep() {
    local path="$1" pattern
    for pattern in "${KEEP_PATTERNS[@]}"; do
        # shellcheck disable=SC2053  # the pattern is a glob on purpose
        if [[ "$path" == $pattern || "$path" == $pattern/* ]]; then
            return 0
        fi
    done
    return 1
}

drop_kept() {
    local path
    while IFS= read -r path; do
        if (( ${#KEEP_PATTERNS[@]} == 0 )) || ! matches_keep "$path"; then
            printf '%s\n' "$path"
        fi
    done
}

# Compare the VM before and after, write leftovers.txt, set LEFTOVER_DETAIL
find_leftovers() {
    local address="$1" dir="$RUN_DIR" report="$RUN_DIR/leftovers.txt"
    local volatile new removed modified owned unowned accounts orphans

    mapfile -t KEEP_PATTERNS < <(vm_ssh "$address" \
        "cd ~/$GUEST_DIR && bash tests/vm/guest-checks.sh --keep $CHECKS_FILE" < /dev/null)

    # Entries that changed between the two baselines, with nothing installed
    volatile=$(comm -3 <(sort "$dir/state-before-1.txt") <(sort "$dir/state-before-2.txt") \
        | awk -F'\t' '{ print $NF }' | sort -u)

    new=$(comm -13 <(state_paths "$dir/state-before-2.txt" fdl) <(state_paths "$dir/state-after.txt" fdl) \
        | comm -23 - <(printf '%s\n' "$volatile") | drop_kept)
    removed=$(comm -23 <(state_paths "$dir/state-before-2.txt" fdl) <(state_paths "$dir/state-after.txt" fdl) \
        | comm -23 - <(printf '%s\n' "$volatile") | drop_kept)
    modified=$(awk -F'\t' '
            FNR == NR && $1 == "h" { before[$3] = $2; next }
            $1 == "h" && ($3 in before) && before[$3] != $2 { print $3 }
        ' "$dir/state-before-2.txt" "$dir/state-after.txt" \
        | grep -vE '^/etc/(passwd|group|shadow|gshadow)-?$' \
        | sort -u | comm -23 - <(printf '%s\n' "$volatile") | drop_kept || true)

    # New paths a package owns came with the packages the module installed
    # shellcheck disable=SC2016  # expands in the VM
    unowned=$(printf '%s\n' "$new" | sed '/^$/d' | vm_ssh "$address" \
        'while IFS= read -r p; do rpm -qf -- "$p" >/dev/null 2>&1 || printf "%s\n" "$p"; done')
    owned=$(( $(printf '%s\n' "$new" | sed '/^$/d' | wc -l) - $(printf '%s\n' "$unowned" | sed '/^$/d' | wc -l) ))

    # New accounts no package provides
    accounts=$(comm -13 <(state_paths "$dir/state-before-2.txt" ug) <(state_paths "$dir/state-after.txt" ug))
    # shellcheck disable=SC2016  # expands in the VM
    orphans=$(printf '%s\n' "$accounts" | sed '/^$/d' | vm_ssh "$address" \
        'while IFS= read -r a; do rpm -q --whatprovides "user($a)" >/dev/null 2>&1 || rpm -q --whatprovides "group($a)" >/dev/null 2>&1 || printf "%s\n" "$a"; done')

    {
        echo "# Left after the uninstall, owned by no package"
        printf '%s\n' "$unowned" | sed '/^$/d'
        echo "# Present before the install, gone after the uninstall"
        printf '%s\n' "$removed" | sed '/^$/d'
        echo "# Content changed between before and after"
        printf '%s\n' "$modified" | sed '/^$/d'
        echo "# Accounts added, provided by no package"
        printf '%s\n' "$orphans" | sed '/^$/d'
        echo "# Kept on purpose (KEEP patterns)"
        printf '%s\n' "${KEEP_PATTERNS[@]}"
    } > "$report"

    local n_unowned n_removed n_modified n_orphans
    n_unowned=$(printf '%s\n' "$unowned" | sed '/^$/d' | wc -l)
    n_removed=$(printf '%s\n' "$removed" | sed '/^$/d' | wc -l)
    n_modified=$(printf '%s\n' "$modified" | sed '/^$/d' | wc -l)
    n_orphans=$(printf '%s\n' "$orphans" | sed '/^$/d' | wc -l)
    LEFTOVER_DETAIL="$n_unowned left, $n_removed removed, $n_modified changed, $n_orphans accounts; $owned package files"
    (( n_unowned + n_removed + n_modified + n_orphans == 0 ))
}

# --- report ---
print_table() {
    local domain="$1" desktop="$2" i status color
    echo ""
    echo -e "${C_BOLD}${C_CYAN}$domain${C_NC} ($desktop)"
    for i in "${!STEP_NAMES[@]}"; do
        status="${STEP_STATUS[$i]}"
        case "$status" in
            PASS) color="$C_GREEN" ;;
            FAIL) color="$C_RED" ;;
            *)    color="$C_DIM" ;;
        esac
        printf "  %-11s ${color}%-4s${C_NC} %5ss  %s\n" \
            "${STEP_NAMES[$i]}" "$status" "${STEP_SECS[$i]}" "${STEP_DETAIL[$i]}"
    done
}

# run_vm <domain> <desktop>: the whole cycle on one VM
run_vm() {
    local domain="$1" desktop="$2" address start
    STEP_NAMES=(); STEP_STATUS=(); STEP_SECS=(); STEP_DETAIL=()
    RUN_DIR="$RESULTS_DIR/$domain"
    mkdir -p "$RUN_DIR"
    info "$domain ($desktop): restoring $VM_SNAPSHOT..."

    if ! step reset "snapshot $VM_SNAPSHOT" reset_vm "$domain"; then
        skip_rest boot copy prereqs lib install checks reinstall checks-2 uninstall leftovers
        return
    fi

    start=$SECONDS
    if address=$(wait_for_ssh "$domain"); then
        record boot PASS $((SECONDS - start)) "$address"
    else
        record boot FAIL $((SECONDS - start)) "no SSH within ${BOOT_TIMEOUT}s"
        skip_rest copy prereqs lib install checks reinstall checks-2 uninstall leftovers
        return
    fi

    info "$domain: running the cycle for $TARGET at $address..."
    if ! step copy "" copy_checkout "$address" \
        || ! step prereqs "${PREREQS[*]:-none}" install_prereqs "$address" "${PREREQS[@]}" \
        || ! step lib "" guest_make "$address" install-lib; then
        skip_rest install checks reinstall checks-2 uninstall leftovers
        return
    fi

    # Two baselines: what differs between them changes on its own
    save_state "$address" before-1
    save_state "$address" before-2

    if step install "" guest_make "$address" "install-$MAKE_TARGET"; then
        start=$SECONDS
        if run_checks "$address" checks; then
            record checks PASS $((SECONDS - start)) "$CHECK_DETAIL"
        else
            record checks FAIL $((SECONDS - start)) "$CHECK_DETAIL"
        fi
        if step reinstall "" guest_make "$address" "install-$MAKE_TARGET"; then
            start=$SECONDS
            if run_checks "$address" checks-2; then
                record checks-2 PASS $((SECONDS - start)) "$CHECK_DETAIL"
            else
                record checks-2 FAIL $((SECONDS - start)) "$CHECK_DETAIL"
            fi
        else
            skip_rest checks-2
        fi
    else
        skip_rest checks reinstall checks-2
    fi

    step uninstall "" guest_make "$address" "uninstall-$MAKE_TARGET" || true

    start=$SECONDS
    save_state "$address" after
    if find_leftovers "$address"; then
        record leftovers PASS $((SECONDS - start)) "$LEFTOVER_DETAIL"
    else
        record leftovers FAIL $((SECONDS - start)) "$LEFTOVER_DETAIL, see leftovers.txt"
    fi
}

# ===================
# Arguments
# ===================
SELECTED=()
KEEP_RUNNING=false
TARGET=""
while (( $# > 0 )); do
    case "$1" in
        --vm)
            [[ -n "${2:-}" ]] || error "--vm needs a domain" "exit"
            SELECTED+=("$2")
            shift 2
            ;;
        --keep) KEEP_RUNNING=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        -*) error "Unknown option: $1" "exit" ;;
        *)
            [[ -z "$TARGET" ]] || error "One module at a time" "exit"
            TARGET="$1"
            shift
            ;;
    esac
done
[[ -n "$TARGET" ]] || { show_help; exit 1; }

readonly MODULE="${TARGET%%/*}"
SUBMODULE=""
[[ "$TARGET" == */* ]] && SUBMODULE="${TARGET#*/}"
readonly SUBMODULE
[[ -f "$REPO_DIR/modules/$MODULE/module.yml" ]] || error "Unknown module: $MODULE" "exit"
readonly MAKE_TARGET="${MODULE}${SUBMODULE:+-$SUBMODULE}"
if [[ -n "$SUBMODULE" ]]; then
    readonly CHECKS_FILE="tests/vm/checks/$MODULE/$SUBMODULE.sh"
else
    readonly CHECKS_FILE="tests/vm/checks/$MODULE.sh"
fi
[[ -f "$REPO_DIR/$CHECKS_FILE" ]] || error "No checks for $TARGET: $CHECKS_FILE" "exit"

check_deps virsh ssh tar git

# ===================
# VMs
# ===================
declare -A DESKTOPS=()
ORDER=()
while read -r domain desktop _; do
    [[ -z "$domain" || "$domain" == \#* ]] && continue
    DESKTOPS["$domain"]="${desktop:-unknown}"
    ORDER+=("$domain")
done < "$VM_CONF"

if (( ${#SELECTED[@]} == 0 )); then
    SELECTED=("${ORDER[@]}")
fi
for domain in "${SELECTED[@]}"; do
    [[ -n "${DESKTOPS[$domain]:-}" ]] || error "$domain is not a test VM listed in $VM_CONF" "exit"
    vsh snapshot-info "$domain" "$VM_SNAPSHOT" > /dev/null 2>&1 \
        || error "$domain has no snapshot $VM_SNAPSHOT" "exit"
done

PREREQS=()
if [[ -f "$PREREQS_FILE" ]]; then
    mapfile -t PREREQS < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$PREREQS_FILE")
fi

RESULTS_DIR="$REPO_DIR/test-output/vm/$(date +%Y%m%d-%H%M%S)-${MAKE_TARGET}"
readonly RESULTS_DIR
mkdir -p "$RESULTS_DIR"

# ===================
# Run
# ===================
SUMMARY=()
OVERALL=0
for domain in "${SELECTED[@]}"; do
    run_vm "$domain" "${DESKTOPS[$domain]}"
    print_table "$domain" "${DESKTOPS[$domain]}" | tee -a "$RESULTS_DIR/report.txt"
    result="PASS"
    for status in "${STEP_STATUS[@]}"; do
        if [[ "$status" != "PASS" ]]; then
            result="FAIL"
            OVERALL=1
        fi
    done
    SUMMARY+=("${DESKTOPS[$domain]} $result")
    if [[ "$KEEP_RUNNING" == false ]]; then
        stop_vm "$domain" || warn "$domain did not shut down"
    fi
done

echo ""
echo -e "${C_BOLD}$TARGET:${C_NC} ${SUMMARY[*]}"
echo "Logs: ${RESULTS_DIR#"$REPO_DIR"/}"
exit "$OVERALL"
