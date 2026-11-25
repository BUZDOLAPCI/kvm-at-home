#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/kvm-switch.sh"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin" "$TEST_DIR/runtime"

cat > "$TEST_DIR/bin/ddcutil" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_DDC_LOG"
printf 'ddcutil %s\n' "$*" >> "$FAKE_ACTION_LOG"

case "${1:-}" in
    getvcp)
        if [[ "${FAKE_GET_FAIL:-0}" == "1" ]]; then
            printf '%s\n' "DDC read failed" >&2
            exit 1
        fi
        printf 'VCP 60 SNC x%s\n' "${FAKE_CURRENT:-13}"
        ;;
    setvcp)
        if [[ "${FAKE_SET_FAIL:-0}" == "1" ]]; then
            printf '%s\n' "DDC write failed" >&2
            exit 1
        fi
        ;;
    *)
        printf 'Unexpected ddcutil command: %s\n' "${1:-}" >&2
        exit 2
        ;;
esac
EOF
chmod +x "$TEST_DIR/bin/ddcutil"

cat > "$TEST_DIR/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_NOTIFY_LOG"
EOF
chmod +x "$TEST_DIR/bin/notify-send"

cat > "$TEST_DIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sleep %s\n' "$*" >> "$FAKE_ACTION_LOG"
if [[ "${FAKE_REENTER_DURING_SLEEP:-0}" == "1" ]]; then
    "$FAKE_SWITCH_SCRIPT"
    "$FAKE_SWITCH_SCRIPT" --suspend
fi
EOF
chmod +x "$TEST_DIR/bin/sleep"

cat > "$TEST_DIR/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl %s\n' "$*" >> "$FAKE_ACTION_LOG"
if [[ "${FAKE_SUSPEND_FAIL:-0}" == "1" ]]; then
    printf '%s\n' "Suspend request failed" >&2
    exit 1
fi
EOF
chmod +x "$TEST_DIR/bin/systemctl"

export PATH="$TEST_DIR/bin:$PATH"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export KVM_AT_HOME_CONFIG="$TEST_DIR/config"
export FAKE_DDC_LOG="$TEST_DIR/ddc.log"
export FAKE_NOTIFY_LOG="$TEST_DIR/notify.log"
export FAKE_ACTION_LOG="$TEST_DIR/actions.log"
export FAKE_SWITCH_SCRIPT="$SCRIPT"

write_config() {
    cat > "$KVM_AT_HOME_CONFIG" <<'EOF'
monitor_model=DELL U5226KW
input_a=0x11
input_b=0x13
EOF
}

reset_logs() {
    : > "$FAKE_DDC_LOG"
    : > "$FAKE_NOTIFY_LOG"
    : > "$FAKE_ACTION_LOG"
}

assert_contains() {
    local file="$1"
    local expected="$2"
    grep -Fqx -- "$expected" "$file" || {
        printf 'Expected line not found in %s: %s\n' "$file" "$expected" >&2
        exit 1
    }
}

assert_no_set() {
    if grep -q '^setvcp ' "$FAKE_DDC_LOG"; then
        printf '%s\n' "Unexpected setvcp call" >&2
        cat "$FAKE_DDC_LOG" >&2
        exit 1
    fi
}

assert_no_suspend() {
    if grep -Eq '^(sleep|systemctl) ' "$FAKE_ACTION_LOG"; then
        printf '%s\n' "Unexpected suspend sequence" >&2
        cat "$FAKE_ACTION_LOG" >&2
        exit 1
    fi
}

assert_suspend_sequence() {
    local target="$1"
    printf '%s\n' \
        'ddcutil getvcp 0x60 --model DELL U5226KW --terse' \
        "ddcutil setvcp 0x60 $target --model DELL U5226KW --noverify" \
        'sleep 2' \
        'systemctl --no-ask-password suspend' > "$TEST_DIR/expected-actions.log"
    diff -u "$TEST_DIR/expected-actions.log" "$FAKE_ACTION_LOG"
}

write_config
reset_logs
FAKE_CURRENT=11 "$SCRIPT"
assert_contains "$FAKE_DDC_LOG" "setvcp 0x60 0x13 --model DELL U5226KW --noverify"
assert_no_suspend
printf '%s\n' "PASS: HDMI 1 switches to DP 2"

reset_logs
FAKE_CURRENT=13 "$SCRIPT"
assert_contains "$FAKE_DDC_LOG" "setvcp 0x60 0x11 --model DELL U5226KW --noverify"
assert_no_suspend
printf '%s\n' "PASS: DP 2 switches to HDMI 1"

reset_logs
if FAKE_CURRENT=12 "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected former HDMI 2 source to fail" >&2
    exit 1
fi
assert_no_set
assert_no_suspend
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Current source 0x12 is outside the configured input pair."
printf '%s\n' "PASS: former HDMI 2 source is rejected"

reset_logs
if FAKE_CURRENT=0f "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected an unknown source to fail" >&2
    exit 1
fi
assert_no_set
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Current source 0x0f is outside the configured input pair."
printf '%s\n' "PASS: unknown source is rejected"

reset_logs
if FAKE_GET_FAIL=1 "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected a DDC read failure" >&2
    exit 1
fi
assert_no_set
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Cannot read the input source for DELL U5226KW."
printf '%s\n' "PASS: DDC read failure is reported"

reset_logs
if FAKE_CURRENT=13 FAKE_SET_FAIL=1 "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected a DDC write failure" >&2
    exit 1
fi
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Failed to switch DELL U5226KW to 0x11."
printf '%s\n' "PASS: DDC write failure is reported"

reset_logs
FAKE_CURRENT=11 "$SCRIPT" --suspend
assert_suspend_sequence 0x13
printf '%s\n' "PASS: HDMI 1 switches to DP 2 before delay and suspend"

reset_logs
FAKE_CURRENT=13 "$SCRIPT" --suspend
assert_suspend_sequence 0x11
printf '%s\n' "PASS: DP 2 switches to HDMI 1 before delay and suspend"

for scenario in FAKE_CURRENT=0f FAKE_CURRENT=12 FAKE_GET_FAIL=1 FAKE_SET_FAIL=1; do
    reset_logs
    if env "$scenario" "$SCRIPT" --suspend >/dev/null 2>&1; then
        printf 'Expected switch failure for %s\n' "$scenario" >&2
        exit 1
    fi
    assert_no_suspend
    printf 'PASS: %s prevents suspend\n' "$scenario"
done

reset_logs
if FAKE_SUSPEND_FAIL=1 "$SCRIPT" --suspend >/dev/null 2>&1; then
    printf '%s\n' "Expected a suspend failure" >&2
    exit 1
fi
assert_suspend_sequence 0x11
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Switched DELL U5226KW to 0x11, but failed to suspend this computer."
printf '%s\n' "PASS: suspend failure is reported without switching back"

reset_logs
(
    exec 9>"$XDG_RUNTIME_DIR/kvm-at-home-${UID}.lock"
    flock -n 9
    "$SCRIPT" --suspend
    # Keep this shell alive to hold the lock while the child runs.
    :
)
[[ ! -s "$FAKE_ACTION_LOG" ]]
printf '%s\n' "PASS: a busy lock prevents switching and suspend"

reset_logs
FAKE_REENTER_DURING_SLEEP=1 "$SCRIPT" --suspend
assert_suspend_sequence 0x11
printf '%s\n' "PASS: both shortcuts are ignored during the delay before suspend"

for args in '--invalid' '--suspend extra'; do
    reset_logs
    read -r -a argv <<< "$args"
    if "$SCRIPT" "${argv[@]}" >/dev/null 2>&1; then
        printf 'Expected invalid arguments to fail: %s\n' "$args" >&2
        exit 1
    fi
    [[ ! -s "$FAKE_ACTION_LOG" ]]
    assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Usage: kvm-at-home [--suspend]"
    printf 'PASS: invalid arguments are rejected: %s\n' "$args"
done

cat > "$KVM_AT_HOME_CONFIG" <<'EOF'
monitor_model=DELL U5226KW
input_a=0x11
input_b=0x11
EOF
reset_logs
if "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected an invalid config to fail" >&2
    exit 1
fi
assert_no_set
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch input_a and input_b must be different."
printf '%s\n' "PASS: invalid config is rejected"

reset_logs
if "$SCRIPT" --suspend >/dev/null 2>&1; then
    printf '%s\n' "Expected an invalid config to prevent suspend" >&2
    exit 1
fi
assert_no_set
assert_no_suspend
printf '%s\n' "PASS: invalid config prevents suspend"
