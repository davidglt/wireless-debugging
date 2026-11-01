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

# Fake adb: logs every call; FAKE_ADB_STATES="PORT=state ..." gives the
# get-state result per 127.0.0.1 target (anything else: device not found);
# FAKE_ADB_HANG=<subcommand> makes that subcommand block. A bare get-state
# reports "device" to model an unrelated USB/remote transport.
cat > "$WORK/bin/adb" <<'ADB'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_ADB_LOG"
[[ "${FAKE_ADB_HANG:-}" == "$1" ]] && exec sleep 30
case "$1" in
    start-server) exit "${FAKE_ADB_START_STATUS:-0}" ;;
    connect) echo "connected to $2"; exit 0 ;;
    get-state)
        echo device; exit 0 ;;
    -s)
        if [[ "$3" == get-state ]]; then
            for PAIR in ${FAKE_ADB_STATES:-}; do
                if [[ "127.0.0.1:${PAIR%%=*}" == "$2" ]]; then echo "${PAIR#*=}"; exit 0; fi
            done
            echo 'error: device not found' >&2; exit 1
        fi ;;
esac
exit 0
ADB
chmod +x "$WORK/bin/adb"
export FAKE_ADB_LOG="$WORK/adb.log"
export FAKE_PYTHON_LOG="$WORK/python.log"
: > "$FAKE_ADB_LOG"
: > "$FAKE_PYTHON_LOG"

# Fake discovery interpreter: prints FAKE_PORTS (space separated) after
# FAKE_DISCOVERY_DELAY seconds; "import zeroconf" fails if FAKE_NO_ZEROCONF=1.
mkdir -p "$WORK/home/.venvs/adb-discovery/bin"
cat > "$WORK/home/.venvs/adb-discovery/bin/python" <<'PYFAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_PYTHON_LOG"
if [[ "$1" == -c && "$2" == 'import zeroconf' ]]; then
    [[ "${FAKE_NO_ZEROCONF:-0}" != 1 ]]; exit
fi
[[ "${FAKE_DISCOVERY_FAIL:-0}" == 1 ]] && exit 3
[[ -n "${FAKE_DISCOVERY_DELAY:-}" ]] && { sleep "$FAKE_DISCOVERY_DELAY"; }
for PORT in ${FAKE_PORTS:-}; do echo "$PORT"; done
PYFAKE
chmod +x "$WORK/home/.venvs/adb-discovery/bin/python"

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
expect removed-check-command 1 '^$' 'Usage: wireless-debugging \{on\|off\|status\|--version\}' \
    -- "${CMD[@]}" check
expect unsupported-strict-option 1 '^$' 'Usage' -- "${CMD[@]}" --strict

# --- ADB check ---
export FAKE_PORTS="40123" FAKE_ADB_STATES="40123=device"
NO_FORBIDDEN='! grep -Eq "^(kill-server|disconnect|pair|reboot|-s [^ ]+ reboot|install|shell)" "$1"'
: > "$FAKE_ADB_LOG"
expect status-adb-available 0 'ADB check: available.*ADB target: 127\.0\.0\.1:40123' '^$' -- "${CMD[@]}" status
if ! grep -q '^connect 127.0.0.1:40123$' "$FAKE_ADB_LOG" \
   || ! grep -q '^-s 127.0.0.1:40123 get-state$' "$FAKE_ADB_LOG"; then
    echo 'FAIL: status did not connect/get-state the specific local target' >&2; FAILED=1
fi
bash -c "$NO_FORBIDDEN" _ "$FAKE_ADB_LOG" \
    || { echo 'FAIL: status ran a forbidden adb command' >&2; FAILED=1; }
expect status-no-setting-change 0 'observed\): OFF' '^$' -- "${CMD[@]}" status
expect on-reports-check 0 'observed\): ON.*ADB check: available' '^$' -- "${CMD[@]}" on
expect status-reports-check 0 'ADB check: available' '^$' -- "${CMD[@]}" status
: > "$FAKE_ADB_LOG"
expect off-no-adb 0 'ADB connectivity was not checked' '^$' -- "${CMD[@]}" off
[[ ! -s "$FAKE_ADB_LOG" ]] || { echo 'FAIL: off used adb' >&2; FAILED=1; }
: > "$FAKE_ADB_LOG"
expect version-no-adb 0 '^App version' '^$' -- "${CMD[@]}" --version
[[ ! -s "$FAKE_ADB_LOG" ]] || { echo 'FAIL: --version used adb' >&2; FAILED=1; }
: > "$FAKE_PYTHON_LOG"
expect version-no-discovery 0 '^App version' '^$' -- "${CMD[@]}" --version
[[ ! -s "$FAKE_PYTHON_LOG" ]] || { echo 'FAIL: --version used Python/discovery' >&2; FAILED=1; }
FAKE_AM_STATE="$WORK/state" FAKE_PORTS="" expect on-setting-on-adb-unavailable 0 \
    'Result: success.*observed\): ON.*ADB check: not verified \(no local connect service found' '^$' -- "${CMD[@]}" on
FAKE_PORTS="" expect status-no-service 0 'ADB check: not verified \(no local connect service found' '^$' -- "${CMD[@]}" status
FAKE_PORTS="1 70000 abc 22 40123" expect status-invalid-ports 0 'available.*40123' '^$' -- "${CMD[@]}" status
FAKE_PORTS="1 70000 abc" expect status-only-invalid-ports 0 'no local connect service found' '^$' -- "${CMD[@]}" status
FAKE_PORTS="40001 40002 40123" FAKE_ADB_STATES="40123=device" \
    expect status-multiple-ports 0 'ADB target: 127\.0\.0\.1:40123' '^$' -- "${CMD[@]}" status
FAKE_ADB_STATES="40123=unauthorized" expect status-unauthorized 0 'unauthorized on 127\.0\.0\.1:40123' '^$' -- "${CMD[@]}" status
FAKE_ADB_STATES="40123=offline" expect status-offline 0 'offline on 127\.0\.0\.1:40123' '^$' -- "${CMD[@]}" status
# An unrelated transport that reports "device" must not count as success.
FAKE_ADB_STATES="" expect status-unrelated-transport 0 'no discovered local port gave a usable ADB device' '^$' -- "${CMD[@]}" status
FAKE_NO_ZEROCONF=1 expect status-no-zeroconf 0 'missing dependencies: zeroconf' '^$' -- "${CMD[@]}" status
FAKE_DISCOVERY_FAIL=1 expect status-discovery-failed 0 'service discovery failed' '^$' -- "${CMD[@]}" status
FAKE_DISCOVERY_DELAY=10 WIRELESS_DEBUGGING_CHECK_TIMEOUT=2 \
    expect status-discovery-timeout 0 'service discovery timed out' '^$' -- "${CMD[@]}" status
FAKE_ADB_HANG=connect WIRELESS_DEBUGGING_CHECK_TIMEOUT=2 \
    expect status-connect-timeout 0 'timed out' '^$' -- "${CMD[@]}" status
FAKE_ADB_HANG=start-server WIRELESS_DEBUGGING_CHECK_TIMEOUT=2 \
    expect status-start-timeout 0 'not verified' '^$' -- "${CMD[@]}" status
WIRELESS_DEBUGGING_CHECK_TIMEOUT=0 expect status-timeout-invalid 1 '^$' 'CHECK_TIMEOUT must be' -- "${CMD[@]}" status
WIRELESS_DEBUGGING_CHECK_TIMEOUT=abc expect on-timeout-invalid 1 '^$' 'CHECK_TIMEOUT must be' -- "${CMD[@]}" on
WIRELESS_DEBUGGING_CHECK_TIMEOUT=abc expect version-ignores-check-timeout 0 '^App version' '^$' -- "${CMD[@]}" --version
FAKE_AM_TOKEN="$(printf 'd%.0s' {1..64})" expect status-app-failure 1 '^$' 'token was rejected' -- "${CMD[@]}" status
# Missing adb: PATH without adb (keep am, timeout and basic tools).
mkdir -p "$WORK/noadb"
for T in am timeout bash od tr cat sleep java dirname env; do
    ln -sf "$(command -v "$T")" "$WORK/noadb/$T"
done
PATH="$WORK/noadb" expect status-no-adb 0 'missing dependencies: adb' '^$' -- "${CMD[@]}" status
PATH="$WORK/noadb" expect on-no-adb 0 'Result: success.*ADB check: not verified \(missing dependencies: adb' '^$' -- "${CMD[@]}" on
echo 0 > "$WORK/state"

# Run the script's real embedded discovery code against a stub zeroconf module
# (only the _adb-tls-connect service type may be browsed; bad ports dropped).
if command -v python3 >/dev/null 2>&1; then
    mkdir -p "$WORK/stub/zeroconf"
    cat > "$WORK/stub/zeroconf/__init__.py" <<'STUB'
import os
class IPVersion: V4Only = 1
class ServiceListener: pass
class _Info:
    def __init__(self, port): self.port = port
class ServiceBrowser:
    def __init__(self, zc, stype, listener):
        assert stype == "_adb-tls-connect._tcp.local.", stype
        for i, _ in enumerate(os.environ["STUB_PORTS"].split()):
            listener.add_service(zc, stype, "svc%d" % i)
    def cancel(self): pass
class Zeroconf:
    def __init__(self, ip_version=None): pass
    def __enter__(self): return self
    def __exit__(self, *a): return False
    def get_service_info(self, stype, name, timeout=0):
        assert stype == "_adb-tls-connect._tcp.local.", stype
        return _Info(int(os.environ["STUB_PORTS"].split()[int(name[3:])]))
STUB
    printf '#!/usr/bin/env bash\nPYTHONPATH="%s/stub" exec python3 "$@"\n' "$WORK" \
        > "$HOME/.venvs/adb-discovery/bin/python"
    STUB_PORTS="22 41000 70000 41001 41000" FAKE_ADB_STATES="41001=device" \
        expect status-real-discovery-code 0 'ADB target: 127\.0\.0\.1:41001' '^$' -- "${CMD[@]}" status
    if grep -Eq 'connect 127\.0\.0\.1:(22|70000)$' "$FAKE_ADB_LOG"; then
        echo 'FAIL: invalid port was tried' >&2; FAILED=1
    fi
else
    echo 'skipped: embedded discovery code test (python3 not found)'
fi

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
