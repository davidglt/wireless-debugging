#!/usr/bin/env bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE in the repository root for licensing details.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
mkdir -p "$PROJECT/examples" "$PROJECT/scripts" "$WORK/bin"
cp "$ROOT/examples/poweroff.sh" "$PROJECT/examples/poweroff.sh"

export ACTIVATION_LOG="$WORK/activation.log"
export ADB_LOG="$WORK/adb.log"
export HELPER_LOG="$WORK/helper.log"
export HELPER_COUNT="$WORK/helper-count"

cat > "$PROJECT/scripts/adb-local-check" <<'HELPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HELPER_LOG"
COUNT=0
[[ ! -f "$HELPER_COUNT" ]] || read -r COUNT < "$HELPER_COUNT"
COUNT=$((COUNT + 1))
printf '%s\n' "$COUNT" > "$HELPER_COUNT"
case "$COUNT" in
    1) printf '%s\n' "${FAKE_HELPER_RESULT_1-}" ;;
    2) printf '%s\n' "${FAKE_HELPER_RESULT_2-}" ;;
    *) printf '\n' ;;
esac
HELPER

cat > "$WORK/bin/wireless-debugging" <<'ACTIVATION'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ACTIVATION_LOG"
if [[ -n "${FAKE_ACTIVATION_STATUS:-}" \
        && "$FAKE_ACTIVATION_STATUS" != 0 ]]; then
    exit "$FAKE_ACTIVATION_STATUS"
fi
if [[ -n "${FAKE_ACTIVATION_RESULT+x}" ]]; then
    printf '%s\n' "$FAKE_ACTIVATION_RESULT" >&3
fi
ACTIVATION

cat > "$WORK/bin/adb" <<'ADB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ADB_LOG"
if [[ "$1" == pair ]]; then
    exit "${FAKE_PAIR_STATUS:-0}"
fi
exit "${FAKE_SHUTDOWN_STATUS:-0}"
ADB

chmod +x "$PROJECT/scripts/adb-local-check" "$WORK/bin/wireless-debugging" "$WORK/bin/adb"
SCRIPT="$PROJECT/examples/poweroff.sh"
FAILED=0

reset_logs() {
    : > "$ACTIVATION_LOG"
    : > "$ADB_LOG"
    : > "$HELPER_LOG"
    : > "$HELPER_COUNT"
}

run_poweroff() {
    local INPUT="$1"
    shift
    local STATUS=0
    printf '%b' "$INPUT" | env HOME="$WORK/home" PATH="$WORK/bin:$PATH" \
        ACTIVATION_LOG="$ACTIVATION_LOG" ADB_LOG="$ADB_LOG" \
        HELPER_LOG="$HELPER_LOG" HELPER_COUNT="$HELPER_COUNT" "$@" \
        bash "$SCRIPT" > "$WORK/stdout" 2> "$WORK/stderr" || STATUS=$?
    return "$STATUS"
}

check_equal() {
    local NAME="$1" ACTUAL="$2" EXPECTED="$3"
    if [[ "$ACTUAL" != "$EXPECTED" ]]; then
        echo "FAIL: poweroff: $NAME" >&2
        printf 'expected: %s\nactual: %s\n' "$EXPECTED" "$ACTUAL" >&2
        FAILED=1
    else
        echo "ok: poweroff: $NAME"
    fi
}

check_contains() {
    local NAME="$1" ACTUAL="$2" EXPECTED="$3"
    if [[ "$ACTUAL" != *"$EXPECTED"* ]]; then
        echo "FAIL: poweroff: $NAME" >&2
        FAILED=1
    else
        echo "ok: poweroff: $NAME"
    fi
}

TARGET='127.0.0.1:41234'
AVAILABLE="adb-check-v1|available|$TARGET|verified|"
UNAVAILABLE='adb-check-v1|unavailable||discovery_failed|none'

reset_logs
if run_poweroff '' "FAKE_ACTIVATION_RESULT=$AVAILABLE"; then STATUS=0; else STATUS=$?; fi
check_equal 'verified activation exits successfully' "$STATUS" 0
check_equal 'activation uses exact local shutdown command' "$(cat "$ADB_LOG")" \
    "-s $TARGET shell svc power shutdown"
check_equal 'activation reuses structured result' "$(cat "$HELPER_LOG")" ''
check_equal 'activation requests wrapper on' "$(cat "$ACTIVATION_LOG")" on

reset_logs
if run_poweroff '' FAKE_HELPER_RESULT_1="$AVAILABLE"; then STATUS=0; else STATUS=$?; fi
check_equal 'helper discovery succeeds' "$STATUS" 0
check_equal 'shared helper receives timeout' "$(cat "$HELPER_LOG")" 30
check_equal 'helper fallback uses exact local shutdown command' "$(cat "$ADB_LOG")" \
    "-s $TARGET shell svc power shutdown"

reset_logs
if run_poweroff '' FAKE_ACTIVATION_STATUS=1 FAKE_HELPER_RESULT_1="$AVAILABLE"; then
    STATUS=0
else
    STATUS=$?
fi
check_equal 'activation failure still permits verified discovery' "$STATUS" 0
check_equal 'activation failure warns on stderr' \
    "$(grep -c 'activation command reported an error' "$WORK/stderr")" 1
check_equal 'activation failure uses explicit verified target' "$(cat "$ADB_LOG")" \
    "-s $TARGET shell svc power shutdown"

reset_logs
if run_poweroff '' WIRELESS_DEBUGGING_CHECK_TIMEOUT=007 \
        FAKE_HELPER_RESULT_1="$AVAILABLE"; then
    STATUS=0
else
    STATUS=$?
fi
check_equal 'leading-zero timeout is normalized' "$(cat "$HELPER_LOG")" 7

reset_logs
if run_poweroff '' WIRELESS_DEBUGGING_CHECK_TIMEOUT=0; then STATUS=0; else STATUS=$?; fi
check_equal 'invalid timeout is rejected' "$STATUS" 1
check_equal 'invalid timeout does not activate or run adb' "$(cat "$ACTIVATION_LOG")$(cat "$ADB_LOG")" ''

reset_logs
if run_poweroff 'n\n' "FAKE_ACTIVATION_RESULT=$UNAVAILABLE"; then STATUS=0; else STATUS=$?; fi
check_equal 'unavailable activation requires consent' "$STATUS" 1
check_equal 'declined activation pairing issues no adb command' "$(cat "$ADB_LOG")" ''
check_contains 'declined activation pairing warns no shutdown' "$(cat "$WORK/stdout")" \
    'Device was not shut down.'

reset_logs
if run_poweroff 'n\n' FAKE_ACTIVATION_RESULT='invalid-result'; then STATUS=0; else STATUS=$?; fi
check_equal 'malformed activation result exits without shutdown' "$STATUS" 1
check_equal 'malformed activation result issues no adb command' "$(cat "$ADB_LOG")" ''
check_equal 'malformed activation result does not trust helper output' "$(cat "$HELPER_LOG")" ''

reset_logs
if run_poweroff 'n\n' FAKE_ACTIVATION_RESULT='adb-check-v1|available|127.0.0.1:99999|verified|'; then STATUS=0; else STATUS=$?; fi
check_equal 'out-of-range target port is rejected' "$STATUS" 1
check_equal 'out-of-range target issues no adb command' "$(cat "$ADB_LOG")" ''

reset_logs
if run_poweroff 'n\n' FAKE_ACTIVATION_RESULT='adb-check-v1|available|192.0.2.1:41234|verified|'; then STATUS=0; else STATUS=$?; fi
check_equal 'non-loopback target is rejected' "$STATUS" 1
check_equal 'non-loopback target issues no adb command' "$(cat "$ADB_LOG")" ''

reset_logs
if run_poweroff 'n\n' FAKE_ACTIVATION_RESULT='adb-check-v1|available|127.0.0.1:41234|connected|'; then STATUS=0; else STATUS=$?; fi
check_equal 'unverified loopback target is rejected' "$STATUS" 1
check_equal 'unverified loopback target issues no adb command' "$(cat "$ADB_LOG")" ''

reset_logs
if run_poweroff 'n\n' FAKE_HELPER_RESULT_1="$UNAVAILABLE"; then STATUS=0; else STATUS=$?; fi
check_equal 'unavailable helper discovery is not treated as a target' "$STATUS" 1
check_equal 'unavailable helper issues no adb command' "$(cat "$ADB_LOG")" ''
check_equal 'unavailable helper receives timeout' "$(cat "$HELPER_LOG")" 30

reset_logs
TARGET='127.0.0.1:45321'
AFTER_PAIR="adb-check-v1|available|$TARGET|verified|"
if run_poweroff 'y\n5555\n' FAKE_HELPER_RESULT_1="$UNAVAILABLE" \
        "FAKE_HELPER_RESULT_2=$AFTER_PAIR"; then
    STATUS=0
else
    STATUS=$?
fi
check_equal 'consented pairing and rediscovery succeed' "$STATUS" 0
check_equal 'consented pairing shutdowns only rediscovered target' "$(cat "$ADB_LOG")" \
    "$(printf 'pair 127.0.0.1:5555\n-s %s shell svc power shutdown' "$TARGET")"
check_equal 'pairing rediscovery uses bounded helper twice' "$(cat "$HELPER_LOG")" \
    "$(printf '30\n30')"

reset_logs
if run_poweroff 'n\n' "FAKE_ACTIVATION_RESULT=$UNAVAILABLE"; then STATUS=0; else STATUS=$?; fi
check_equal 'pairing cancellation exits without shutdown' "$STATUS" 1
check_equal 'pairing cancellation issues no adb command' "$(cat "$ADB_LOG")" ''

reset_logs
if run_poweroff 'y\n5555\n' FAKE_HELPER_RESULT_1="$UNAVAILABLE" FAKE_PAIR_STATUS=1; then
    STATUS=0
else
    STATUS=$?
fi
check_equal 'pairing failure exits without shutdown' "$STATUS" 1
check_equal 'pairing failure runs pair only' "$(cat "$ADB_LOG")" 'pair 127.0.0.1:5555'
check_equal 'pairing failure does not rediscover' "$(cat "$HELPER_LOG")" 30

reset_logs
if run_poweroff 'y\n5555\n' FAKE_HELPER_RESULT_1="$UNAVAILABLE" \
        FAKE_HELPER_RESULT_2="$UNAVAILABLE"; then
    STATUS=0
else
    STATUS=$?
fi
check_equal 'failed post-pair rediscovery exits without shutdown' "$STATUS" 1
check_equal 'failed post-pair rediscovery runs pair only' "$(cat "$ADB_LOG")" \
    'pair 127.0.0.1:5555'
check_equal 'failed post-pair rediscovery runs helper twice' "$(cat "$HELPER_LOG")" \
    "$(printf '30\n30')"

exit "$FAILED"
