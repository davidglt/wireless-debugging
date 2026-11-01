#!/usr/bin/env bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.
#
# Host-side checks (no Android device needed). Requires bash, javac and java.
# The Android receiver, aapt2/d8 build and real Termux "am" are NOT covered.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PKG="$ROOT/src/local/termux/wirelessdebugging"
javac -encoding UTF-8 -d "$WORK/classes" \
    "$PKG/ControlProtocol.java" "$ROOT/tests/ControlProtocolTest.java" \
    "$ROOT/tests/FakeAm.java"
java -cp "$WORK/classes" local.termux.wirelessdebugging.ControlProtocolTest

# Source-level UI checks (text/structure only; not a compile or device test).
UI="$PKG/MainActivity.java"
FAILED_UI=0
ui_check() { # description, condition result
    if ! "${@:2}"; then echo "FAIL: UI: $1" >&2; FAILED_UI=1; else echo "ok: UI: $1"; fi
}
for LABEL in 'Turn ON' 'Turn OFF' 'Refresh status' 'Setup' 'About'; do
    ui_check "main screen has $LABEL" grep -q "\"$LABEL\"" "$UI"
done
ui_check 'main screen does not read or show the token' \
    bash -c '! grep -Eqi "tokenView|Control token|pm grant|getOrCreateToken\(this\)\.|Show token" "$1"' _ "$UI"
ui_check 'setup hides token initially and has show/hide/copy' \
    grep -Eq '"Show token"' "$PKG/SetupActivity.java"
ui_check 'setup uses FLAG_SECURE' grep -q FLAG_SECURE "$PKG/SetupActivity.java"
ui_check 'main keeps FLAG_SECURE' grep -q FLAG_SECURE "$UI"
ABOUT="$PKG/AboutActivity.java"
ui_check 'about has license line' grep -q 'License: ' "$ABOUT"
ui_check 'about has clickable GPL link text' \
    bash -c 'grep -q "GNU GPL v3 or later" "$1" && grep -q ClickableSpan "$1"' _ "$ABOUT"
ui_check 'about copyright line' grep -q 'Copyright \\u00a9 2026 David Gonz' "$ABOUT"
ui_check 'about has Repository and Close buttons' \
    bash -c 'grep -q "\"Repository\"" "$1" && grep -q "\"Close\"" "$1"' _ "$ABOUT"
ui_check 'about has no Author line, old button or plain URL text' \
    bash -c '! grep -Eq "\\nAuthor: |Open project page|\" *\+ *AppSupport.PROJECT_URL" "$1"' _ "$ABOUT"
ui_check 'about uses installedVersion' grep -q 'AppSupport.installedVersion' "$ABOUT"
ui_check 'about reads bundled license asset' grep -q 'getAssets().open' "$ABOUT"
ui_check 'build.sh bundles LICENSE as asset' \
    bash -c 'grep -q "LICENSE.txt" "$1" && grep -q -- "-A \"\$BUILD/assets\"" "$1"' _ "$ROOT/build.sh"
ui_check 'LICENSE is the GPL v3 text' \
    bash -c 'head -2 "$1" | grep -q "GNU GENERAL PUBLIC LICENSE" && grep -q "^END OF TERMS AND CONDITIONS" "$1"' _ "$ROOT/LICENSE"
ui_check 'no token logging' \
    bash -c '! grep -Eq "Log\.|System\.(out|err)" "$1"/*Activity.java "$1"/AppSupport.java "$1"/ControlReceiver.java' _ "$PKG"
ui_check 'setup/about declared non-exported' \
    bash -c '[[ "$(grep -c "exported=\"false\"" "$1")" == 2 ]]' _ "$ROOT/AndroidManifest.xml"
(( FAILED_UI == 0 )) || exit 1

mkdir -p "$WORK/bin" "$WORK/home/.config/wireless-debugging"
cat > "$WORK/bin/am" <<AM
#!/usr/bin/env bash
exec java -cp "$WORK/classes" local.termux.wirelessdebugging.FakeAm "\$@"
AM
chmod +x "$WORK/bin/am"

TOKEN="$(printf 'c%.0s' {1..64})"
export HOME="$WORK/home"
export PATH="$WORK/bin:$PATH"
export FAKE_AM_TOKEN="$TOKEN" FAKE_AM_STATE="$WORK/state"
printf '%s\n' "$TOKEN" > "$HOME/.config/wireless-debugging/token"
echo 0 > "$WORK/state"
CMD=(bash "$ROOT/scripts/wireless-debugging")

FAILED=0
expect() { # name expected_exit stdout_pattern stderr_pattern -- command...
    local NAME="$1" CODE="$2" OUT_RE="$3" ERR_RE="$4"
    shift 5
    local OUT ERR STATUS=0
    OUT="$("$@" 2>"$WORK/err")" || STATUS=$?
    ERR="$(cat "$WORK/err")"
    if [[ "$STATUS" != "$CODE" || ! "$OUT" =~ $OUT_RE || ! "$ERR" =~ $ERR_RE \
          || "$OUT$ERR" == *"$TOKEN"* ]]; then
        printf 'FAIL: %s (exit %s)\nstdout: %s\nstderr: %s\n' \
            "$NAME" "$STATUS" "$OUT" "$ERR" >&2
        FAILED=1
    else
        printf 'ok: %s\n' "$NAME"
    fi
}

expect status 0 'setting \(observed\): OFF' '^$' -- "${CMD[@]}" status
expect on 0 'setting \(observed\): ON' '^$' -- "${CMD[@]}" on
expect status-after-on 0 'observed\): ON' '^$' -- "${CMD[@]}" status
expect off 0 'setting \(observed\): OFF' '^$' -- "${CMD[@]}" off
expect reachability-note 0 'ADB reachability is not verified' '^$' -- "${CMD[@]}" status
expect status-version 0 'App version: 1.2.3 \(code 12\)' '^$' -- "${CMD[@]}" status
expect on-version 0 'App version: 1.2.3 \(code 12\)' '^$' -- "${CMD[@]}" on
echo 0 > "$WORK/state"
expect version 0 '^App version: 1.2.3 \(code 12\)$' '^$' -- "${CMD[@]}" --version
if [[ "$(cat "$WORK/state")" != 0 ]]; then
    echo 'FAIL: --version changed the setting' >&2; FAILED=1
fi
FAKE_AM_VERSION='' expect version-unknown 1 '^$' 'did not report its installed version' -- "${CMD[@]}" --version
FAKE_AM_MODE=oldproto expect version-incompatible 1 '^$' 'incompatible protocol' -- "${CMD[@]}" --version
FAKE_AM_MODE=oldproto expect status-incompatible 1 '^$' 'incompatible protocol' -- "${CMD[@]}" status
FAKE_AM_TOKEN="$(printf 'd%.0s' {1..64})" \
    expect version-invalid-token 1 '^$' 'token was rejected' -- "${CMD[@]}" --version
FAKE_AM_DELAY=3 WIRELESS_DEBUGGING_TIMEOUT=1 \
    expect version-timeout 1 '^$' 'no response within' -- "${CMD[@]}" --version
expect bad-usage 1 '^$' 'Usage' -- "${CMD[@]}" reboot

FAKE_AM_PERMISSION=0 expect missing-permission 1 '^$' 'WRITE_SECURE_SETTINGS' -- "${CMD[@]}" on
FAKE_AM_TOKEN="$(printf 'd%.0s' {1..64})" \
    expect invalid-token 1 '^$' 'token was rejected' -- "${CMD[@]}" status
FAKE_AM_DELAY=3 WIRELESS_DEBUGGING_TIMEOUT=1 \
    expect timeout 1 '^$' 'no response within 1 seconds' -- "${CMD[@]}" status
FAKE_AM_MODE=garbage expect garbage 1 '^$' 'no valid response' -- "${CMD[@]}" status
FAKE_AM_MODE=wrongnonce expect nonce-mismatch 1 '^$' 'did not match' -- "${CMD[@]}" status

mv "$HOME/.config/wireless-debugging/token" "$WORK/token.bak"
expect missing-token 1 '^$' 'token file' -- "${CMD[@]}" status
mv "$WORK/token.bak" "$HOME/.config/wireless-debugging/token"

# Concurrent invocations: each must succeed with its own correlated response.
PIDS=()
for N in 1 2 3 4 5 6 7 8; do
    OP=status; (( N % 2 )) && OP=on
    "${CMD[@]}" "$OP" > "$WORK/out.$N" 2> "$WORK/err.$N" &
    PIDS+=($!)
done
for PID in "${PIDS[@]}"; do
    wait "$PID" || { echo "FAIL: concurrent request exit" >&2; cat "$WORK"/err.* >&2; FAILED=1; }
done
for N in 1 2 3 4 5 6 7 8; do
    grep -q 'Result: success' "$WORK/out.$N" \
        || { echo "FAIL: concurrent output $N" >&2; FAILED=1; }
done
(( FAILED )) || echo 'ok: concurrent requests'

exit "$FAILED"
