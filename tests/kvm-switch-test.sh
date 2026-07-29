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

case "${1:-}" in
    getvcp)
        if [[ "${FAKE_GET_FAIL:-0}" == "1" ]]; then
            printf '%s\n' "DDC read failed" >&2
            exit 1
        fi
        printf 'VCP 60 SNC x%s\n' "${FAKE_CURRENT:-12}"
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

export PATH="$TEST_DIR/bin:$PATH"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export KVM_AT_HOME_CONFIG="$TEST_DIR/config"
export FAKE_DDC_LOG="$TEST_DIR/ddc.log"
export FAKE_NOTIFY_LOG="$TEST_DIR/notify.log"

write_config() {
    cat > "$KVM_AT_HOME_CONFIG" <<'EOF'
monitor_model=DELL U5226KW
input_a=0x11
input_b=0x12
EOF
}

reset_logs() {
    : > "$FAKE_DDC_LOG"
    : > "$FAKE_NOTIFY_LOG"
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

write_config
reset_logs
FAKE_CURRENT=11 "$SCRIPT"
assert_contains "$FAKE_DDC_LOG" "setvcp 0x60 0x12 --model DELL U5226KW --noverify"
printf '%s\n' "PASS: HDMI 1 switches to HDMI 2"

reset_logs
FAKE_CURRENT=12 "$SCRIPT"
assert_contains "$FAKE_DDC_LOG" "setvcp 0x60 0x11 --model DELL U5226KW --noverify"
printf '%s\n' "PASS: HDMI 2 switches to HDMI 1"

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
if FAKE_CURRENT=12 FAKE_SET_FAIL=1 "$SCRIPT" >/dev/null 2>&1; then
    printf '%s\n' "Expected a DDC write failure" >&2
    exit 1
fi
assert_contains "$FAKE_NOTIFY_LOG" "KVM Switch Failed to switch DELL U5226KW to 0x11."
printf '%s\n' "PASS: DDC write failure is reported"

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
