#!/data/data/com.termux/files/usr/bin/bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.

set -euo pipefail
umask 077

PROJECT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLATFORM="$HOME/.local/share/android-sdk/platforms/android-33/android.jar"
BUILD="$PROJECT/build"
OUTPUT="$PROJECT/dist/wireless-debugging.apk"
SIGNING="$HOME/.local/share/wireless-debugging/signing"
IDENTITY_DIR="$SIGNING/identity"
KEYSTORE=""
PASSWORD_FILE=""
STAGING=""
ALIAS="wireless-debugging"

trap 'printf "Error: build failed at line %s.\n" "$LINENO" >&2' ERR
cleanup_staging() {
    if [[ -n "$STAGING" && -d "$STAGING" ]]; then
        rm -rf -- "$STAGING"
    fi
}
trap cleanup_staging EXIT

for TOOL in javac jar keytool aapt2 d8 zip zipalign apksigner od tr; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        printf 'Error: required tool not found: %s\n' "$TOOL" >&2
        exit 1
    fi
done

if [[ ! -f "$PLATFORM" ]]; then
    printf 'Error: Android platform not found: %s\n' "$PLATFORM" >&2
    exit 1
fi

if [[ -L "$SIGNING" ]]; then
    echo "Error: signing directory must not be a symbolic link." >&2
    exit 1
fi
mkdir -p "$SIGNING"
chmod 700 "$SIGNING"

rm -rf \
    "$BUILD/classes" \
    "$BUILD/dex" \
    "$BUILD/generated" \
    "$BUILD/assets" \
    "$BUILD/compiled-resources.zip" \
    "$BUILD/resources.apk" \
    "$BUILD/classes.jar" \
    "$BUILD/unsigned.apk" \
    "$BUILD/aligned.apk" \
    "$BUILD/signed.apk"
mkdir -p \
    "$BUILD/classes" \
    "$BUILD/dex" \
    "$BUILD/generated" \
    "$BUILD/assets" \
    "$PROJECT/dist"

echo "[1/7] Packaging Android resources..."

RESOURCE_ARGS=()

if [[ -d "$PROJECT/res" ]] &&
   [[ -n "$(find "$PROJECT/res" -type f -print -quit)" ]]; then
    aapt2 compile \
        --dir "$PROJECT/res" \
        -o "$BUILD/compiled-resources.zip"
    RESOURCE_ARGS+=("$BUILD/compiled-resources.zip")
fi

# Bundle the repository LICENSE as an offline asset for the About screen.
cp "$PROJECT/LICENSE" "$BUILD/assets/LICENSE.txt"

aapt2 link \
    -A "$BUILD/assets" \
    -o "$BUILD/resources.apk" \
    -I "$PLATFORM" \
    --manifest "$PROJECT/AndroidManifest.xml" \
    --java "$BUILD/generated" \
    "${RESOURCE_ARGS[@]}"

echo "[2/7] Compiling Java sources..."

find "$BUILD/classes" -type f -name '*.class' -delete

mapfile -d '' -t SOURCES < <(
    find "$PROJECT/src" "$BUILD/generated" \
        -type f -name '*.java' -print0
)

if (( ${#SOURCES[@]} == 0 )); then
    echo "Error: no Java source files found." >&2
    exit 1
fi

javac \
    --release 8 \
    -Xlint:-options \
    -encoding UTF-8 \
    -classpath "$PLATFORM" \
    -d "$BUILD/classes" \
    "${SOURCES[@]}"

echo "[3/7] Generating DEX bytecode..."

jar --create \
    --file "$BUILD/classes.jar" \
    -C "$BUILD/classes" .

find "$BUILD/dex" -maxdepth 1 -type f -name '*.dex' -delete

d8 \
    --release \
    --min-api 30 \
    --lib "$PLATFORM" \
    --output "$BUILD/dex" \
    "$BUILD/classes.jar"

echo "[4/7] Assembling APK..."

cp "$BUILD/resources.apk" "$BUILD/unsigned.apk"

(
    cd "$BUILD/dex"
    zip -q "$BUILD/unsigned.apk" ./*.dex
)

echo "[5/7] Aligning APK..."

zipalign -f 4 "$BUILD/unsigned.apk" "$BUILD/aligned.apk"

echo "[6/7] Preparing signing key..."

LEGACY_KEYSTORE="$SIGNING/local-signing.p12"
LEGACY_PASSWORD_FILE="$SIGNING/store-password"
LEGACY_PRESENT=0
IDENTITY_PRESENT=0
if [[ -e "$LEGACY_KEYSTORE" || -L "$LEGACY_KEYSTORE" \
        || -e "$LEGACY_PASSWORD_FILE" || -L "$LEGACY_PASSWORD_FILE" ]]; then
    LEGACY_PRESENT=1
fi
if [[ -e "$IDENTITY_DIR" || -L "$IDENTITY_DIR" ]]; then
    IDENTITY_PRESENT=1
fi
if (( LEGACY_PRESENT && IDENTITY_PRESENT )); then
    echo "Error: multiple signing identities exist; all existing files were left unchanged." >&2
    exit 1
fi
if [[ -n "$(find "$SIGNING" -mindepth 1 -maxdepth 1 \
        -name '.new-identity.*' -print -quit)" ]]; then
    echo "Error: an incomplete signing staging directory exists; existing files were left unchanged." >&2
    exit 1
fi

NEW_IDENTITY=0
if (( LEGACY_PRESENT )); then
    KEYSTORE="$LEGACY_KEYSTORE"
    PASSWORD_FILE="$LEGACY_PASSWORD_FILE"
elif (( IDENTITY_PRESENT )); then
    if [[ -L "$IDENTITY_DIR" || ! -d "$IDENTITY_DIR" ]]; then
        echo "Error: signing identity directory is unsafe; existing files were left unchanged." >&2
        exit 1
    fi
    chmod 700 "$IDENTITY_DIR"
    KEYSTORE="$IDENTITY_DIR/local-signing.p12"
    PASSWORD_FILE="$IDENTITY_DIR/store-password"
else
    NEW_IDENTITY=1
    STAGING="$(mktemp -d "$SIGNING/.new-identity.XXXXXX")"
    KEYSTORE="$STAGING/local-signing.p12"
    PASSWORD_FILE="$STAGING/store-password"
fi

KEYSTORE_PRESENT=0
PASSWORD_PRESENT=0
if [[ -e "$KEYSTORE" || -L "$KEYSTORE" ]]; then
    KEYSTORE_PRESENT=1
fi
if [[ -e "$PASSWORD_FILE" || -L "$PASSWORD_FILE" ]]; then
    PASSWORD_PRESENT=1
fi
if (( NEW_IDENTITY == 0 )); then
    if (( KEYSTORE_PRESENT != PASSWORD_PRESENT )) \
            || [[ -L "$KEYSTORE" || -L "$PASSWORD_FILE" ]]; then
        echo "Error: signing key and password state is incomplete or unsafe; existing files were left unchanged." >&2
        exit 1
    fi
    if [[ ! -f "$KEYSTORE" || ! -f "$PASSWORD_FILE" \
            || ! -s "$KEYSTORE" || ! -s "$PASSWORD_FILE" ]]; then
        echo "Error: existing signing key or password is not a nonempty regular file; files were left unchanged." >&2
        exit 1
    fi
    chmod 600 "$KEYSTORE" "$PASSWORD_FILE"
    if ! keytool -list \
            -keystore "$KEYSTORE" \
            -storetype PKCS12 \
            -storepass:file "$PASSWORD_FILE" \
            -alias "$ALIAS" >/dev/null 2>&1; then
        echo "Error: existing signing identity could not be verified; files were left unchanged." >&2
        exit 1
    fi
else
    PASSWORD="$(od -An -N32 -tx1 /dev/urandom | tr -d '[:space:]')"
    if [[ ! "$PASSWORD" =~ ^[0-9a-f]{64}$ ]]; then
        echo "Error: could not generate a signing password." >&2
        exit 1
    fi
    if ! (set -o noclobber; printf '%s\n' "$PASSWORD" > "$PASSWORD_FILE"); then
        unset PASSWORD
        echo "Error: could not create signing password safely." >&2
        exit 1
    fi
    unset PASSWORD
    keytool -genkeypair \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -storepass:file "$PASSWORD_FILE" \
        -keypass:file "$PASSWORD_FILE" \
        -alias "$ALIAS" \
        -keyalg RSA \
        -keysize 3072 \
        -sigalg SHA256withRSA \
        -validity 10000 \
        -dname "CN=Wireless Debugging Local Build" \
        -noprompt
    keytool -list \
        -keystore "$KEYSTORE" \
        -storetype PKCS12 \
        -storepass:file "$PASSWORD_FILE" \
        -alias "$ALIAS" >/dev/null
    chmod 700 "$STAGING"
    chmod 600 "$KEYSTORE" "$PASSWORD_FILE"
    if ! mv -nT -- "$STAGING" "$IDENTITY_DIR"; then
        echo "Error: could not publish the new signing identity safely." >&2
        exit 1
    fi
    if [[ -e "$STAGING" ]]; then
        echo "Error: a signing identity appeared during publication; existing files were left unchanged." >&2
        exit 1
    fi
    STAGING=""
    KEYSTORE="$IDENTITY_DIR/local-signing.p12"
    PASSWORD_FILE="$IDENTITY_DIR/store-password"
fi

echo "[7/7] Signing and verifying APK..."

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-type PKCS12 \
    --ks-key-alias "$ALIAS" \
    --ks-pass "file:$PASSWORD_FILE" \
    --out "$BUILD/signed.apk" \
    "$BUILD/aligned.apk"

zipalign -c 4 "$BUILD/signed.apk"
apksigner verify --verbose "$BUILD/signed.apk"
mv -f "$BUILD/signed.apk" "$OUTPUT"

printf '\nBuild completed successfully.\nAPK: %s\n' "$OUTPUT"
