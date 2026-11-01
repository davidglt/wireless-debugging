#!/usr/bin/env bash
# Copyright (C) 2026 David González López-Tercero
# Author: David González López-Tercero
# SPDX-License-Identifier: GPL-3.0-or-later
# See LICENSE and NOTICE in the repository root for licensing details.
#
# Host checks for scripts/install-scripts.sh using temporary directories only.

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: install: $1" >&2; exit 1; }
ok() { echo "ok: install: $1"; }

# Copy of the project in a path containing spaces; sources are marked so
# updates can be detected. Nothing is executed from it.
PROJECT="$WORK/my project"
mkdir -p "$PROJECT/scripts" "$PROJECT/examples"
cp "$ROOT/scripts/install-scripts.sh" "$PROJECT/scripts/"
printf '#!/bin/sh\n# v1 wd\n' > "$PROJECT/scripts/wireless-debugging"
printf '#!/bin/sh\n# v1 check\n' > "$PROJECT/scripts/adb-local-check"
printf '#!/bin/sh\n# v1 reboot\n' > "$PROJECT/examples/reboot.sh"
printf '#!/bin/sh\n# v1 poweroff\n' > "$PROJECT/examples/poweroff.sh"
chmod 644 "$PROJECT/scripts/wireless-debugging" "$PROJECT/scripts/adb-local-check" \
    "$PROJECT/examples/reboot.sh" "$PROJECT/examples/poweroff.sh"

DEST="$WORK/dest dir/bin"
run() { BINDIR="$DEST" bash "$PROJECT/scripts/install-scripts.sh"; }

run >/dev/null || fail 'first installation failed'
for n in wireless-debugging adb-local-check reboot poweroff; do
    [[ -x "$DEST/$n" ]] || fail "$n not executable"
done
grep -q 'v1 wd' "$DEST/wireless-debugging" && grep -q 'v1 check' "$DEST/adb-local-check" \
    && grep -q 'v1 reboot' "$DEST/reboot" && grep -q 'v1 poweroff' "$DEST/poweroff" \
    || fail 'first install content'
[[ "$(find "$DEST" -mindepth 1 | wc -l)" -eq 4 ]] || fail 'unexpected files (staging left behind?)'
ok 'first installation (paths with spaces, executable)'

for f in scripts/wireless-debugging scripts/adb-local-check examples/reboot.sh examples/poweroff.sh; do
    sed -i 's/v1/v2/' "$PROJECT/$f"
done
run >/dev/null || fail 'update failed'
grep -q 'v2 wd' "$DEST/wireless-debugging" && grep -q 'v2 check' "$DEST/adb-local-check" \
    && grep -q 'v2 reboot' "$DEST/reboot" && grep -q 'v2 poweroff' "$DEST/poweroff" \
    || fail 'update content'
[[ -x "$DEST/reboot" && -x "$DEST/poweroff" ]] || fail 'update lost executable bit'
ok 'rerun updates scripts'

for f in scripts/wireless-debugging scripts/adb-local-check examples/reboot.sh examples/poweroff.sh; do
    sed -i 's/v2/v3/' "$PROJECT/$f"
done
rm "$PROJECT/examples/reboot.sh"
rm "$PROJECT/examples/poweroff.sh"
if run >/dev/null 2>"$WORK/err"; then fail 'missing source did not fail'; fi
grep -q 'missing or unreadable source' "$WORK/err" || fail 'missing source message'
grep -q 'v2 wd' "$DEST/wireless-debugging" && grep -q 'v2 check' "$DEST/adb-local-check" \
    && grep -q 'v2 reboot' "$DEST/reboot" || fail 'partial update after missing source'
grep -q 'v2 poweroff' "$DEST/poweroff" || fail 'partial update changed poweroff'
ok 'missing source fails without partial update'

# A missing source must not even create the destination.
FRESH="$WORK/fresh/bin"
if BINDIR="$FRESH" bash "$PROJECT/scripts/install-scripts.sh" >/dev/null 2>&1; then
    fail 'fresh missing source did not fail'
fi
[[ ! -e "$FRESH" ]] || fail 'destination created despite missing source'
ok 'missing source creates nothing'

# Default destination is $HOME/bin.
printf '#!/bin/sh\n# v4\n' > "$PROJECT/examples/reboot.sh"
printf '#!/bin/sh\n# v4\n' > "$PROJECT/examples/poweroff.sh"
HOME="$WORK/home dir" bash "$PROJECT/scripts/install-scripts.sh" >/dev/null || fail 'default destination'
[[ -x "$WORK/home dir/bin/reboot" ]] || fail 'default destination is not $HOME/bin'
[[ -x "$WORK/home dir/bin/poweroff" ]] || fail 'poweroff not installed in $HOME/bin'
ok 'default destination is $HOME/bin'
