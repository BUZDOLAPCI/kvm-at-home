#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${KVM_AT_HOME_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/kvm-at-home/config}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/kvm-at-home-${UID}.lock"

notify_error() {
    notify-send "KVM Switch" "$1" 2>/dev/null || true
    printf 'ERROR: %s\n' "$1" >&2
}

fail() {
    notify_error "$1"
    exit 1
}

normalize_source() {
    local value="${1,,}"
    value="${value#0x}"
    value="${value#x}"
    [[ "$value" =~ ^[0-9a-f]{2}$ ]] || return 1
    printf '0x%s\n' "$value"
}

suspend_after_switch=false
if (( $# > 0 )); then
    [[ $# -eq 1 && "$1" == "--suspend" ]] || fail "Usage: kvm-at-home [--suspend]"
    suspend_after_switch=true
fi

command -v ddcutil >/dev/null 2>&1 || fail "ddcutil is not installed."
command -v flock >/dev/null 2>&1 || fail "flock is not installed."
if "$suspend_after_switch"; then
    command -v systemctl >/dev/null 2>&1 || fail "systemctl is not installed."
    command -v sleep >/dev/null 2>&1 || fail "sleep is not installed."
fi
[[ -r "$CONFIG_FILE" ]] || fail "Config not found: $CONFIG_FILE"

monitor_model=""
input_a=""
input_b=""

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || fail "Invalid config line: $line"

    key="${line%%=*}"
    value="${line#*=}"

    case "$key" in
        monitor_model) monitor_model="$value" ;;
        input_a) input_a="$value" ;;
        input_b) input_b="$value" ;;
        *) fail "Unknown config key: $key" ;;
    esac
done < "$CONFIG_FILE"

[[ -n "$monitor_model" ]] || fail "monitor_model is missing from the config."
input_a="$(normalize_source "$input_a")" || fail "input_a is not a valid source code."
input_b="$(normalize_source "$input_b")" || fail "input_b is not a valid source code."
[[ "$input_a" != "$input_b" ]] || fail "input_a and input_b must be different."

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

if ! current_output="$(ddcutil getvcp 0x60 --model "$monitor_model" --terse 2>&1)"; then
    fail "Cannot read the input source for $monitor_model."
fi

if [[ "$current_output" =~ (^|[[:space:]])x([0-9a-fA-F]{2})($|[[:space:]]) ]]; then
    current_source="0x${BASH_REMATCH[2],,}"
else
    fail "Cannot parse the current input source."
fi

case "$current_source" in
    "$input_a") target_source="$input_b" ;;
    "$input_b") target_source="$input_a" ;;
    *) fail "Current source $current_source is outside the configured input pair." ;;
esac

if ! ddcutil setvcp 0x60 "$target_source" --model "$monitor_model" --noverify; then
    fail "Failed to switch $monitor_model to $target_source."
fi

if "$suspend_after_switch"; then
    # Allow the monitor's input and KVM to settle before suspending this PC.
    # Keep the switch lock held so repeated shortcuts cannot switch back.
    sleep 2
    if ! systemctl --no-ask-password suspend; then
        fail "Switched $monitor_model to $target_source, but failed to suspend this computer."
    fi
fi
