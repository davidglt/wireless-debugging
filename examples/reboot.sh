#!/data/data/com.termux/files/usr/bin/bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -x "$SCRIPT_DIR/adb-local-check" ]]; then
    ADB_CHECK="$SCRIPT_DIR/adb-local-check"
elif [[ -x "$SCRIPT_DIR/../scripts/adb-local-check" ]]; then
    ADB_CHECK="$SCRIPT_DIR/../scripts/adb-local-check"
else
    ADB_CHECK="$HOME/bin/adb-local-check"
fi

CHECK_TIMEOUT="${WIRELESS_DEBUGGING_CHECK_TIMEOUT-30}"
if [[ ! "$CHECK_TIMEOUT" =~ ^[0-9]{1,3}$ ]]; then
    echo "Error: WIRELESS_DEBUGGING_CHECK_TIMEOUT must be a decimal integer from 1 to 300." >&2
    exit 1
fi
CHECK_TIMEOUT=$((10#$CHECK_TIMEOUT))
if (( CHECK_TIMEOUT < 1 || CHECK_TIMEOUT > 300 )); then
    echo "Error: WIRELESS_DEBUGGING_CHECK_TIMEOUT must be a decimal integer from 1 to 300." >&2
    exit 1
fi

if ! command -v wireless-debugging >/dev/null 2>&1; then
    echo "Error: required command not found: wireless-debugging" >&2
    exit 1
fi
if [[ ! -x "$ADB_CHECK" ]]; then
    echo "Error: shared ADB discovery helper not found: $ADB_CHECK" >&2
    exit 1
fi

read_result() {
    local LINE="$1"
    IFS='|' read -r RESULT_VERSION CHECK_STATE TARGET CHECK_REASON CHECK_DETAIL \
        <<< "$LINE"
    if [[ "$RESULT_VERSION" != adb-check-v1 \
            || ! "$CHECK_STATE" =~ ^(available|unavailable)$ \
            || ! "$CHECK_REASON" =~ ^[a-z_]+$ ]]; then
        return 1
    fi
    if [[ "$CHECK_STATE" == available ]] \
            && [[ ! "$TARGET" =~ ^127\.0\.0\.1:[0-9]{1,5}$ \
                || "$CHECK_REASON" != verified ]]; then
        return 1
    fi
    if [[ "$CHECK_STATE" == available ]]; then
        local PORT="${TARGET#127.0.0.1:}"
        PORT=$((10#$PORT))
        if (( PORT < 1024 || PORT > 65535 )); then
            return 1
        fi
    fi
}

RESULT_FILE="$(mktemp)"
trap 'rm -f "$RESULT_FILE"' EXIT

echo "Requesting Wireless debugging activation..."
if ! WIRELESS_DEBUGGING_MACHINE_OUTPUT=1 wireless-debugging on 3>"$RESULT_FILE"; then
    echo "Warning: the activation command reported an error." >&2
    echo "Continuing with local discovery to verify ADB availability." >&2
fi

TARGET=""
if [[ -s "$RESULT_FILE" ]]; then
    IFS= read -r RESULT_LINE < "$RESULT_FILE"
    if ! read_result "$RESULT_LINE"; then
        CHECK_STATE=unavailable
        CHECK_REASON=probe_failed
        CHECK_DETAIL="wireless-debugging returned a malformed internal result"
        echo "Warning: $CHECK_DETAIL." >&2
    fi
else
    RESULT_LINE="$(bash "$ADB_CHECK" "$CHECK_TIMEOUT")"
    if ! read_result "$RESULT_LINE"; then
        CHECK_STATE=unavailable
        CHECK_REASON=probe_failed
        CHECK_DETAIL="ADB helper returned a malformed result"
    fi
fi
if [[ "$CHECK_STATE" != available ]]; then
    TARGET=""
fi

if [[ -z "$TARGET" ]]; then
    echo "Could not verify a local ADB connection."
    echo "The setting alone does not establish ADB connectivity."
    echo

    read -r -p "Start interactive pairing? [y/N] " ANSWER
    case "$ANSWER" in
        y|Y|yes|YES) ;;
        *)
            echo "Cancelled. Device was not rebooted."
            exit 1
            ;;
    esac

    echo
    echo "On this phone, open:"
    echo "Settings > Developer options > Wireless debugging"
    echo "> Pair device with pairing code"
    echo "Keep the pairing dialog open."
    echo
    read -r -p "Pairing port: " PAIR_PORT
    if [[ ! "$PAIR_PORT" =~ ^[0-9]{1,5}$ ]]; then
        echo "Error: invalid pairing port." >&2
        exit 1
    fi
    PAIR_PORT=$((10#$PAIR_PORT))
    if (( PAIR_PORT < 1 || PAIR_PORT > 65535 )); then
        echo "Error: port must be between 1 and 65535." >&2
        exit 1
    fi

    echo "Enter the pairing code when adb asks for it."
    if ! adb pair "127.0.0.1:$PAIR_PORT"; then
        echo "Error: pairing failed. Device was not rebooted." >&2
        exit 1
    fi

    echo "Discovering the connection port..."
    RESULT_LINE="$(bash "$ADB_CHECK" "$CHECK_TIMEOUT")"
    if ! read_result "$RESULT_LINE" || [[ "$CHECK_STATE" != available ]]; then
        echo "Error: could not verify an ADB connection after pairing." >&2
        echo "Device was not rebooted." >&2
        exit 1
    fi
fi

echo "Connected to $TARGET."
echo "Rebooting device..."
adb -s "$TARGET" reboot
