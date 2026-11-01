#!/usr/bin/env bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PROJECT="$WORK/project"
HOME="$WORK/home"
TOOLS="$WORK/tools"
mkdir -p "$PROJECT/src" "$TOOLS" "$HOME/.local/share/android-sdk/platforms/android-33"
cp "$ROOT/build.sh" "$PROJECT/build.sh"
cp "$ROOT/AndroidManifest.xml" "$PROJECT/AndroidManifest.xml"
cp "$ROOT/LICENSE" "$PROJECT/LICENSE"
cp -R "$ROOT/src/." "$PROJECT/src/"
: > "$HOME/.local/share/android-sdk/platforms/android-33/android.jar"

cat > "$TOOLS/javac" <<'TOOL'
#!/usr/bin/env bash
while (( $# )); do
    if [[ "$1" == -d ]]; then
        mkdir -p "$2"
        printf 'class\n' > "$2/Fake.class"
        exit 0
    fi
    shift
done
exit 1
TOOL
cat > "$TOOLS/jar" <<'TOOL'
#!/usr/bin/env bash
while (( $# )); do
    if [[ "$1" == --file ]]; then
        : > "$2"
        exit 0
    fi
    shift
done
exit 1
TOOL
cat > "$TOOLS/aapt2" <<'TOOL'
#!/usr/bin/env bash
while (( $# )); do
    if [[ "$1" == -o ]]; then
        printf 'resource\n' > "$2"
        exit 0
    fi
    shift
done
exit 1
TOOL
cat > "$TOOLS/d8" <<'TOOL'
#!/usr/bin/env bash
while (( $# )); do
    if [[ "$1" == --output ]]; then
        mkdir -p "$2"
        printf 'dex\n' > "$2/classes.dex"
        exit 0
    fi
    shift
done
exit 1
TOOL
cat > "$TOOLS/zip" <<'TOOL'
#!/usr/bin/env bash
exit 0
TOOL
cat > "$TOOLS/zipalign" <<'TOOL'
#!/usr/bin/env bash
if [[ "$1" == -c ]]; then
    [[ -s "$3" ]]
else
    cp "$3" "$4"
fi
TOOL
cat > "$TOOLS/keytool" <<'TOOL'
#!/usr/bin/env bash
case "$1" in
    -genkeypair)
        [[ "${FAKE_KEYTOOL_GEN_FAIL:-0}" != 1 ]] || exit 7
        while (( $# )); do
            if [[ "$1" == -keystore ]]; then
                printf 'fake key\n' > "$2"
                exit 0
            fi
            shift
        done
        exit 1
        ;;
    -list)
        [[ "${FAKE_KEYTOOL_LIST_FAIL:-0}" != 1 ]]
        ;;
    *) exit 1 ;;
esac
TOOL
cat > "$TOOLS/apksigner" <<'TOOL'
#!/usr/bin/env bash
if [[ "$1" == sign ]]; then
    OUTPUT=""
    INPUT=""
    while (( $# )); do
        if [[ "$1" == --out ]]; then
            OUTPUT="$2"
            shift 2
        else
            INPUT="$1"
            shift
        fi
    done
    cp "$INPUT" "$OUTPUT"
    exit 0
fi
if [[ "$1" == verify ]]; then
    [[ "${FAKE_APKSIGNER_VERIFY_FAIL:-0}" != 1 && -s "${@: -1}" ]]
    exit $?
fi
exit 1
TOOL
chmod +x "$TOOLS"/*

export HOME
PATH="$TOOLS:$PATH"
export PATH

mkdir -p "$PROJECT/build/assets" "$PROJECT/build/generated" "$PROJECT/build/dex"
printf 'stale\n' > "$PROJECT/build/assets/stale.txt"
printf 'stale\n' > "$PROJECT/build/generated/Stale.java"
printf 'stale\n' > "$PROJECT/build/dex/stale.dex"

run_build() {
    (cd "$PROJECT" && HOME="$HOME" PATH="$PATH" bash build.sh)
}

run_build > "$WORK/build.log"
OUTPUT="$PROJECT/dist/wireless-debugging.apk"
SIGNING="$HOME/.local/share/wireless-debugging/signing/identity"
KEYSTORE="$SIGNING/local-signing.p12"
PASSFILE="$SIGNING/store-password"
[[ -s "$OUTPUT" && -s "$KEYSTORE" && -s "$PASSFILE" ]]
[[ "$(wc -c < "$PASSFILE")" == 65 ]]
grep -Eq '^[0-9a-f]{64}$' "$PASSFILE"
[[ "$(stat -c %a "$SIGNING")" == 700 \
    && "$(stat -c %a "$KEYSTORE")" == 600 \
    && "$(stat -c %a "$PASSFILE")" == 600 ]]
[[ ! -e "$PROJECT/build/assets/stale.txt" \
    && ! -e "$PROJECT/build/generated/Stale.java" \
    && ! -e "$PROJECT/build/dex/stale.dex" ]]
KEY_HASH="$(sha256sum "$KEYSTORE" | cut -d' ' -f1)"
PASSWORD_HASH="$(sha256sum "$PASSFILE" | cut -d' ' -f1)"
run_build > "$WORK/build-again.log"
[[ "$KEY_HASH" == "$(sha256sum "$KEYSTORE" | cut -d' ' -f1)" ]]
[[ "$PASSWORD_HASH" == "$(sha256sum "$PASSFILE" | cut -d' ' -f1)" ]]

LEGACY_HOME="$WORK/legacy-home"
LEGACY_SIGNING="$LEGACY_HOME/.local/share/wireless-debugging/signing"
mkdir -p "$LEGACY_SIGNING" "$LEGACY_HOME/.local/share/android-sdk/platforms/android-33"
: > "$LEGACY_HOME/.local/share/android-sdk/platforms/android-33/android.jar"
printf 'legacy key\n' > "$LEGACY_SIGNING/local-signing.p12"
printf 'legacy password\n' > "$LEGACY_SIGNING/store-password"
chmod 755 "$LEGACY_SIGNING"
chmod 644 "$LEGACY_SIGNING/local-signing.p12" "$LEGACY_SIGNING/store-password"
LEGACY_HASH="$(sha256sum "$LEGACY_SIGNING"/* | sha256sum | cut -d' ' -f1)"
HOME="$LEGACY_HOME" run_build > "$WORK/legacy-build.log"
[[ ! -e "$LEGACY_SIGNING/identity" ]]
[[ "$LEGACY_HASH" == "$(sha256sum "$LEGACY_SIGNING"/* | sha256sum | cut -d' ' -f1)" ]]
[[ "$(stat -c %a "$LEGACY_SIGNING")" == 700 \
    && "$(stat -c %a "$LEGACY_SIGNING/local-signing.p12")" == 600 \
    && "$(stat -c %a "$LEGACY_SIGNING/store-password")" == 600 ]]

FAIL_HOME="$WORK/keygen-failure"
mkdir -p "$FAIL_HOME/.local/share/android-sdk/platforms/android-33"
: > "$FAIL_HOME/.local/share/android-sdk/platforms/android-33/android.jar"
if FAKE_KEYTOOL_GEN_FAIL=1 HOME="$FAIL_HOME" run_build \
        > "$WORK/keygen-failure.log" 2>&1; then
    echo "FAIL: key generation failure was accepted" >&2
    exit 1
fi
FAIL_SIGNING="$FAIL_HOME/.local/share/wireless-debugging/signing"
[[ ! -e "$FAIL_SIGNING/identity" ]]
[[ -z "$(find "$FAIL_SIGNING" -mindepth 1 -maxdepth 1 -name '.new-identity.*' -print -quit)" ]]

ORPHAN_HOME="$WORK/orphan-stage"
ORPHAN_SIGNING="$ORPHAN_HOME/.local/share/wireless-debugging/signing"
mkdir -p "$ORPHAN_SIGNING/.new-identity.manual-review" \
    "$ORPHAN_HOME/.local/share/android-sdk/platforms/android-33"
: > "$ORPHAN_HOME/.local/share/android-sdk/platforms/android-33/android.jar"
printf 'staged private material\n' > "$ORPHAN_SIGNING/.new-identity.manual-review/store-password"
ORPHAN_HASH="$(sha256sum "$ORPHAN_SIGNING/.new-identity.manual-review/store-password")"
if HOME="$ORPHAN_HOME" run_build > "$WORK/orphan-stage.log" 2>&1; then
    echo "FAIL: build ignored an incomplete signing staging directory" >&2
    exit 1
fi
[[ "$ORPHAN_HASH" == \
    "$(sha256sum "$ORPHAN_SIGNING/.new-identity.manual-review/store-password")" ]]

printf 'preserve previous apk\n' > "$OUTPUT"
if FAKE_APKSIGNER_VERIFY_FAIL=1 run_build > "$WORK/verify-failure.log" 2>&1; then
    echo "FAIL: build accepted an invalid APK signature" >&2
    exit 1
fi
[[ "$(cat "$OUTPUT")" == 'preserve previous apk' ]]

for STATE in key-only password-only invalid-identity; do
    STATE_HOME="$WORK/$STATE"
    STATE_SIGNING="$STATE_HOME/.local/share/wireless-debugging/signing"
    mkdir -p "$STATE_SIGNING" "$STATE_HOME/.local/share/android-sdk/platforms/android-33"
    : > "$STATE_HOME/.local/share/android-sdk/platforms/android-33/android.jar"
    case "$STATE" in
        key-only) printf 'existing key\n' > "$STATE_SIGNING/local-signing.p12" ;;
        password-only) printf 'existing password\n' > "$STATE_SIGNING/store-password" ;;
        invalid-identity)
            printf 'existing key\n' > "$STATE_SIGNING/local-signing.p12"
            printf 'existing password\n' > "$STATE_SIGNING/store-password"
            ;;
    esac
    BEFORE="$(find "$STATE_SIGNING" -type f -exec sha256sum {} \; | sort)"
    if [[ "$STATE" == invalid-identity ]]; then
        if FAKE_KEYTOOL_LIST_FAIL=1 HOME="$STATE_HOME" run_build \
                > "$WORK/$STATE.log" 2>&1; then
            echo "FAIL: build accepted an unverifiable signing identity" >&2
            exit 1
        fi
    elif HOME="$STATE_HOME" run_build > "$WORK/$STATE.log" 2>&1; then
        echo "FAIL: build accepted inconsistent signing state: $STATE" >&2
        exit 1
    fi
    AFTER="$(find "$STATE_SIGNING" -type f -exec sha256sum {} \; | sort)"
    [[ "$BEFORE" == "$AFTER" ]]
done

echo 'build-test.sh: fake-tool build safety checks passed'
