#!/usr/bin/env bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.
#
# Copies the user-facing scripts into BINDIR (default: $HOME/bin). Rerunning
# updates them. It never runs the scripts, uses ADB, installs the APK, touches
# tokens or keys, or installs dependencies.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -n "${BINDIR+x}" ]]; then
    DEST="$BINDIR"
elif [[ -n "${HOME:-}" ]]; then
    DEST="$HOME/bin"
else
    echo 'Error: HOME is not set and BINDIR was not given.' >&2
    exit 1
fi
if [[ -z "$DEST" ]]; then
    echo 'Error: BINDIR is empty.' >&2
    exit 1
fi

# Source path, installed command name.
SOURCES=("$ROOT/scripts/wireless-debugging" "$ROOT/scripts/adb-local-check" "$ROOT/examples/reboot.sh")
NAMES=(wireless-debugging adb-local-check reboot)

for i in "${!SOURCES[@]}"; do
    if [[ ! -f "${SOURCES[$i]}" || ! -r "${SOURCES[$i]}" ]]; then
        printf 'Error: missing or unreadable source: %s\n' "${SOURCES[$i]}" >&2
        exit 1
    fi
    if [[ -d "$DEST/${NAMES[$i]}" ]]; then
        printf 'Error: destination is a directory: %s\n' "$DEST/${NAMES[$i]}" >&2
        exit 1
    fi
done

mkdir -p -- "$DEST"
STAGE="$(mktemp -d -- "$DEST/.install-scripts.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT

# Stage every file first so a failure leaves existing commands untouched.
for i in "${!SOURCES[@]}"; do
    install -m 700 -- "${SOURCES[$i]}" "$STAGE/${NAMES[$i]}"
done
for i in "${!SOURCES[@]}"; do
    mv -f -- "$STAGE/${NAMES[$i]}" "$DEST/${NAMES[$i]}"
    printf 'Installed: %s\n' "$DEST/${NAMES[$i]}"
done
