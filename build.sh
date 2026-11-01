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
KEYSTORE="$SIGNING/local-signing.p12"
PASSWORD_FILE="$SIGNING/store-password"
ALIAS="wireless-debugging"

trap 'printf "Error: build failed at line %s.\n" "$LINENO" >&2' ERR

for TOOL in javac jar keytool aapt2 d8 zip zipalign apksigner; do
    if ! command -v "$TOOL" >/dev/null 2>&1; then
        printf 'Error: required tool not found: %s\n' "$TOOL" >&2
        exit 1
    fi
done

if [[ ! -f "$PLATFORM" ]]; then
    printf 'Error: Android platform not found: %s\n' "$PLATFORM" >&2
    exit 1
fi

mkdir -p \
    "$BUILD/classes" \
    "$BUILD/dex" \
    "$BUILD/generated" \
    "$PROJECT/dist" \
    "$SIGNING"

chmod 700 "$SIGNING"

echo "[1/7] Packaging Android resources..."

RESOURCE_ARGS=()

if [[ -d "$PROJECT/res" ]] &&
   [[ -n "$(find "$PROJECT/res" -type f -print -quit)" ]]; then
    aapt2 compile \
        --dir "$PROJECT/res" \
        -o "$BUILD/compiled-resources.zip"
    RESOURCE_ARGS+=("$BUILD/compiled-resources.zip")
fi

aapt2 link \
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

if [[ ! -f "$KEYSTORE" ]]; then
    if [[ ! -f "$PASSWORD_FILE" ]]; then
        PASSWORD=""

        for ((INDEX = 0; INDEX < 12; INDEX++)); do
            printf -v PART '%04x' "$RANDOM"
            PASSWORD+="$PART"
        done

        printf '%s\n' "$PASSWORD" > "$PASSWORD_FILE"
        unset PASSWORD PART
    fi

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
fi

if [[ ! -f "$PASSWORD_FILE" ]]; then
    echo "Error: signing password file is missing." >&2
    exit 1
fi

chmod 600 "$KEYSTORE" "$PASSWORD_FILE"

echo "[7/7] Signing and verifying APK..."

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-type PKCS12 \
    --ks-key-alias "$ALIAS" \
    --ks-pass "file:$PASSWORD_FILE" \
    --out "$OUTPUT" \
    "$BUILD/aligned.apk"

zipalign -c 4 "$OUTPUT"
apksigner verify --verbose "$OUTPUT"

printf '\nBuild completed successfully.\nAPK: %s\n' "$OUTPUT"
