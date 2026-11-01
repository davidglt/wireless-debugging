# Wireless Debugging

Minimal Android companion app to control the wireless debugging system setting from Termux without root. Built directly on Android using command-line tools, without Gradle.

## Requirements and limitations

- Android 11 or later (minimum API 30; target API 33).
- Termux and Android-compatible build tools.
- An initial authorized ADB connection to grant WRITE_SECURE_SETTINGS. The app cannot grant this permission to itself.
- Developer options and wireless debugging support.

The app writes `Settings.Global.adb_wifi_enabled`. An ON setting does not guarantee ADB reachability: Android may still require network approval and pairing. The companion app itself does not pair devices or discover ports. Device behavior can vary.

## Development and observed test environment

| Component | Reported value |
| --- | --- |
| Device | Samsung Galaxy S20 FE |
| Manufacturer | samsung |
| Model reported by Android | SM-G780G |
| Android | 13 |
| Device API level | 33 |
| One UI | 5.1 |
| Android security patch | 2025-10-01 |
| Build identifier | TP1A.220624.014.G780GXXSHEYJ1 |
| Desktop environment | Samsung DeX; version not recorded |
| Termux distribution | Google Play; app version not recorded |

Development used Samsung DeX with an external monitor and a UGREEN USB-C hub. DeX is the desktop environment, not the DEX bytecode produced by the Android build tool `d8`. Exact build-tool versions were not recorded.

On this device, the app buttons and Termux control worked after enabling Termux's display-over-other-apps access. A launcher exception was also observed as described below. The reboot example's newly added activation integration still needs end-to-end device testing; these observations are not a compatibility guarantee for other devices.

## Repository layout

- `AndroidManifest.xml`: package, permission, activity and control receiver declaration.
- `src/local/termux/wirelessdebugging/MainActivity.java`: main screen, token creation on first launch and the `SetupActivity`/`AboutActivity` screens (with `AppSupport` helpers).
- `src/local/termux/wirelessdebugging/ControlReceiver.java` and `ControlProtocol.java`: token-authenticated control endpoint and its Android-independent request logic.
- `tests/run-tests.sh`: host-side checks (see Testing).
- `build.sh`: packaging, compilation, alignment, signing and verification.
- `scripts/wireless-debugging`: Termux command wrapper.
- `scripts/adb-local-check`: shared bounded local ADB discovery and verification helper.
- `examples/reboot.sh`: local wireless ADB reboot integration example.
- `build/` and `dist/`: generated files, excluded from source control.

## Build environment

Required commands on PATH:

```text
java javac jar keytool aapt2 d8 zip zipalign apksigner od tr
```

### Install build tools in Termux

Run these commands inside Termux, not in an ADB shell or a desktop Linux terminal:

```sh
pkg update &&
pkg install git openjdk-21 aapt aapt2 d8 apksigner zip coreutils
```

Review the package manager's proposed changes before accepting. Use the repositories configured for your Termux distribution; do not mix repositories from different Termux distributions. Package availability may differ between distributions or change over time. If a package is unavailable, stop and inspect the configured repositories rather than substituting an arbitrary downloaded executable.

| Package | Commands used by this project | Purpose |
| --- | --- | --- |
| `git` | `git` | Clone and update the repository |
| `openjdk-21` | `java`, `javac`, `jar`, `keytool` | Run Java tools, compile sources and manage the signing key |
| `aapt` | `zipalign` | Align the APK |
| `aapt2` | `aapt2` | Package Android resources |
| `d8` | `d8` | Convert compiled Java classes to DEX |
| `apksigner` | `apksigner` | Sign and verify the APK |
| `zip` | `zip` | Add DEX files to the APK |
| `coreutils` | `od`, `tr` | Generate a signing password from `/dev/urandom` |

The Android tool package ownership above was checked in the development device's installed package database: `zipalign` belongs to `aapt`, not to a separate package named `zipalign`. OpenJDK 21 is the installation option documented here; the original device's Java package/version was not established by that check. A missing package owner for a command path does not by itself prove a manual installation, because the path may be a symlink.

Use Termux-native tools for the device architecture. Desktop SDK binaries are not necessarily executable on Android. This project does not need Gradle, Android Studio, a Linux distribution in proot, or root for this build pipeline. The build script does not install dependencies automatically.

These packages do not provision the API 33 platform JAR at the project-specific path below. That is a separate requirement. The reboot example's `android-tools`, Python and `zeroconf` dependencies are also separate from compilation tools.

Official package definitions: [aapt](https://github.com/termux/termux-packages/tree/master/packages/aapt), [aapt2](https://github.com/termux/termux-packages/blob/master/packages/aapt/aapt2.subpackage.sh), [d8](https://github.com/termux/termux-packages/tree/master/packages/d8), and [apksigner](https://github.com/termux/termux-packages/tree/master/packages/apksigner).

### Check all required commands

Run in Bash. The subshell reports every missing command and returns a nonzero status without closing your interactive shell:

```bash
(
    missing=0
    for tool in java javac jar keytool aapt2 d8 zip zipalign apksigner od tr; do
        if path="$(command -v "$tool")"; then
            printf 'Found: %s -> %s\n' "$tool" "$path"
        else
            printf 'Missing: %s\n' "$tool" >&2
            missing=1
        fi
    done
    exit "$missing"
)
```

This checks command availability, not full tool compatibility. To inspect the Java toolchain and record useful diagnostics:

```sh
java -version
javac -version
d8 --version
aapt2 version
apksigner version
```

### Android API 33 platform JAR

The build expects the API 33 platform JAR at:

```text
$HOME/.local/share/android-sdk/platforms/android-33/android.jar
```

Provision this file from an Android SDK API 33 platform installation, or edit `PLATFORM` in `build.sh` to point to your API 33 platform JAR. Do not replace it with an arbitrary JAR or a framework APK from the phone. Follow the [Android API 33 platform setup guide](docs/android-platform-33.md) for download, checksum verification, installation and validation instructions.

Check the file and its archive structure:

```bash
(
    platform="$HOME/.local/share/android-sdk/platforms/android-33/android.jar"
    if [[ ! -s "$platform" ]]; then
        printf 'Error: API 33 platform JAR is missing or empty: %s\n' "$platform" >&2
        exit 1
    fi
    jar --list --file "$platform" >/dev/null || exit 1
    printf 'Platform JAR found: %s\n' "$platform"
)
```

Archive validity alone does not establish the API level or authenticity; use a trusted Android SDK source. After all checks pass, run the build below. The complete build and signature verification remain the practical compatibility test.

## Build and install the app

```sh
git clone https://github.com/davidglt/wireless-debugging.git
cd wireless-debugging
bash build.sh
```

Install or update the companion APK with `adb`, not with `termux-open` or the Android package installer. `TARGET` must be the actual serial or `IP:PORT` of an authorized target that `adb -s TARGET get-state` reports as `device`:

```sh
adb -s TARGET get-state
adb -s TARGET install -r dist/wireless-debugging.apk
```

`-r` reinstalls over an existing installation and preserves its app data (including the control token and granted permission) when the new APK uses the same signing identity. An APK signed with a different identity will not update the installed app.

**Bootstrap.** The initial installation needs an already authorized USB or wireless ADB connection that you establish independently (see [Initial wireless ADB pairing from Termux](#initial-wireless-adb-pairing-from-termux) or use a computer). `wireless-debugging on` is not required, and cannot be used, before the app is installed and granted its permission.

**From a computer (USB or network).** Run the commands above on the computer with its own copy of the APK path and the device's actual serial or IP address and port. Do not use `127.0.0.1` there; a computer's loopback is the computer, not the phone. Use `adb devices -l` to find the target.

**From Termux on the same phone.** Needs the `adb` client from `pkg install android-tools` and an authorized local connection (see the pairing section). For later updates, once the app is installed and permitted, `wireless-debugging on` can discover and verify the current loopback target; its output reports the actual `ADB target: 127.0.0.1:PORT`. Wireless debugging uses a dynamic connection port that changes, so use the port reported by that command (or shown in Developer options) as `TARGET`; never assume 5555 or reuse an example port.

The build verifies alignment and signatures. It creates a local signing key and password outside the repository:

```text
$HOME/.local/share/wireless-debugging/signing/identity/local-signing.p12
$HOME/.local/share/wireless-debugging/signing/identity/store-password
```

Keep both files private, back them up securely and reuse the same key for updates. Do not commit them. Existing root-level signing pairs from earlier builds are reused in place and are not moved or replaced; a verified pair may be restricted to owner-only permissions.
New signing passwords are generated from the operating system's cryptographic random source. The build stages and validates a new identity before publishing it. If an existing key/password pair is incomplete or cannot be verified, the build fails without replacing either file. The build never reads or changes ADB keys or the app control token.

## Initial wireless ADB pairing from Termux

Install the ADB client:

```sh
pkg install android-tools
```

On the phone:

1. Enable Developer options if necessary.
2. Open `Settings > Developer options > Wireless debugging` and turn it on manually for the initial setup.
3. Approve the current Wi-Fi network only if you trust it. If offered, `Always allow on this network` remembers network approval; it does not guarantee that debugging remains enabled forever.
4. Select `Pair device with pairing code`. Keep that dialog open. Use split-screen or separate DeX windows to keep Settings and Termux accessible.
5. Note the pairing port and enter it at the prompt below. Enter the displayed pairing code only when ADB asks for it.

```bash
read -r -p 'Pairing port: ' PAIR_PORT
adb pair "127.0.0.1:$PAIR_PORT"
unset PAIR_PORT
```

The loopback address is for the local-phone workflow used by this project. If the device does not accept loopback connections, use the IP address shown in Settings instead; the supplied reboot example specifically assumes loopback support. A computer-based setup should use the phone's displayed IP address on the same network, not the computer's loopback address.

After pairing, return to the main Wireless debugging screen. Its connection port is different from the pairing port. For a manual connection, enter the connection port shown on that main screen:

```bash
read -r -p 'Connection port: ' CONNECT_PORT
adb connect "127.0.0.1:$CONNECT_PORT"
adb -s "127.0.0.1:$CONNECT_PORT" get-state
```

Proceed only if the state is `device`. To grant the installed companion app its permission using this specific connection:

```bash
adb -s "127.0.0.1:$CONNECT_PORT" shell pm grant \
    local.termux.wirelessdebugging android.permission.WRITE_SECURE_SETTINGS
unset CONNECT_PORT
```

Do not save pairing codes or hard-code ports. Connection ports may change when debugging restarts. The reboot example rediscovers the connection port instead.

## Preserve pairing between sessions

Pairing, connection and the debugging switch are separate:

- Pairing authorizes the ADB client's identity and normally survives closing Termux or restarting its ADB server.
- A connection is a current session and may need reconnecting to a new port.
- Wireless debugging must be enabled for a connection to work. This app can request that setting after its one-time permission grant; it does not preserve authorization by itself.

To retain the client identity:

1. Keep Termux's existing ADB key files, normally `$HOME/.android/adbkey` and `$HOME/.android/adbkey.pub`. The first is a private credential. Do not delete or regenerate them unnecessarily.
2. Do not clear Termux's app data or uninstall it without securely backing up any keys you need. A new client key requires new authorization.
3. Do not choose `Forget` for that client in Android's paired-device list or revoke ADB debugging authorizations unless you intend to remove access.
4. Keep using the same Termux environment for this workflow. Pairing a computer authorizes that computer's identity, not automatically Termux's identity.
5. If you back up ADB keys, protect the backup as a credential. Never commit keys, paste their contents into issues, or place them in public/shared folders.

### Optional: disable authorization expiration

If Developer options exposes `Disable adb authorization timeout`, enabling it disables automatic authorization revocation due to the ADB authorization timeout. This retains trust in authorized clients for longer and is a security tradeoff, not a requirement for running the app. Availability and wording vary; this option has not yet been confirmed on the reported Samsung configuration.

This option does not keep a network connection alive, freeze the port, prevent explicit revocation, or guarantee that wireless debugging stays enabled after reboot or inactivity. Prefer normal expiration unless you need longer-lived authorization and understand the risk. This project does not change the timeout automatically.

### Reconnect without pairing again

Enable wireless debugging, discover the current connection port and reconnect using the same client identity. If the connection is unavailable, first check the switch, network approval and current port; do not assume pairing has been lost. Pair again only if authorization is missing or rejected.

For the integration example, `reboot` (installed at `$HOME/bin/reboot`) performs discovery and connection, but it will actually reboot the phone as soon as it connects. Do not use it merely as a harmless connection test. Use the manual `get-state` command above for a non-rebooting check.

Official background: [Android Debug Bridge wireless pairing](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi) and [Android authorization-timeout implementation](https://android.googlesource.com/platform/packages/apps/Settings/+/master/src/com/android/settings/development/AdbAuthorizationTimeoutPreferenceController.java). Newer Android features described in upstream documentation are not necessarily available on Android 13.

## Grant the app permission once

Using an authorized ADB shell connection, run:

```sh
adb shell pm grant local.termux.wirelessdebugging android.permission.WRITE_SECURE_SETTINGS
```

Use USB ADB from a computer or an already paired wireless ADB connection. Establish the initial connection before disabling wireless debugging. An ordinary Android permission dialog cannot grant this permission. If several devices are connected, specify the intended device with `adb -s TARGET`, as in the local pairing example above.

Open the app from its launcher icon; this creates the token if none exists. The main screen shows the current setting and permission status with `Turn ON`, `Turn OFF`, `Refresh status`, `Setup` and `About`. Press `Refresh status` and verify `Required permission: GRANTED`. `Setup` shows the permission command (with `Copy command`), Termux instructions and the control token, which stays hidden until `Show token` is pressed (`Hide token`, `Copy token` also available; opening Setup never replaces an existing token, and the screens use `FLAG_SECURE`). `About` shows the installed version (read from package metadata), the copyright line and `License: GNU GPL v3 or later`. The `GNU GPL v3 or later` text is a link that opens the complete GPL v3 text bundled in the APK (packaged by `build.sh` from `LICENSE`; no network access needed) in a scrollable dialog with `Close`. The `Repository` button opens the project page; `Close` leaves the screen.

## Allow Termux to open the app

On the device tested, Termux required this special access:

```text
Settings → Apps → Special app access → Display over other apps → Termux → Allow
```

The setting may also be named `Appear on top`; wording varies by manufacturer and system language. Grant it to Termux, not the companion app. This is separate from WRITE_SECURE_SETTINGS. It is an observed device-specific fix, not a universal guarantee.

Test launching from Termux:

```sh
am start --user 0 \
    -n local.termux.wirelessdebugging/.MainActivity \
    -a android.intent.action.MAIN
```

The interface should appear. `Starting: Intent ...` alone is not confirmation. The examples target Android user 0; other profiles require the correct user ID.

## Install the Termux command

Install the runtime dependencies and the isolated discovery environment (`android-tools` provides `adb`, `coreutils` provides `timeout`, and `zeroconf` is installed only in the venv):

```sh
pkg install android-tools python coreutils
python -m venv "$HOME/.venvs/adb-discovery"
"$HOME/.venvs/adb-discovery/bin/python" -m pip install zeroconf
```

From the repository root, install the command in `$HOME/bin`:

```sh
mkdir -p "$HOME/bin"
install -m 700 scripts/wireless-debugging "$HOME/bin/wireless-debugging"
install -m 700 scripts/adb-local-check "$HOME/bin/adb-local-check"
```

If `$HOME/bin` is not on your `PATH`, add it (for example to `~/.bashrc`) and reload the shell:

```sh
echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/bin:$PATH"
```

This replaces an existing command at that path. Back up a customized version first.

**Migrating from an earlier install location.** Inspect existing copies of the commands before changing anything; this only lists them and does not delete or run them:

```sh
type -a wireless-debugging
type -a wireless-reboot
type -a reboot
```

Remove or keep older copies (for example under `$HOME/.local/bin` or `$PREFIX/bin`) manually, after reviewing the output. The installer above never deletes anything.

Create the private token file using Bash. Copy the current 64-character token displayed in the app and enter it at the prompt, not as part of a shell command:

```bash
(
    umask 077
    mkdir -p "$HOME/.config/wireless-debugging"
    chmod 700 "$HOME/.config/wireless-debugging"
    read -r -s -p 'Control token: ' CONTROL_TOKEN
    printf '\n'
    if [[ ! "$CONTROL_TOKEN" =~ ^[0-9a-f]{64}$ ]]; then
        echo 'Error: invalid control token format.' >&2
        exit 1
    fi
    TOKEN_FILE="$HOME/.config/wireless-debugging/token"
    if [[ -e "$TOKEN_FILE" || -L "$TOKEN_FILE" ]]; then
        echo 'Error: token file already exists; it was left unchanged.' >&2
        exit 1
    fi
    (set -o noclobber; printf '%s\n' "$CONTROL_TOKEN" > "$TOKEN_FILE")
    chmod 600 "$TOKEN_FILE"
    unset CONTROL_TOKEN
)
```

The command refuses to overwrite an existing token. Never commit it. If the app's token changes, intentionally update the file after confirming the new token. The app control token is separate from ADB keys and pairing codes.

Usage:

```sh
wireless-debugging on
wireless-debugging off
wireless-debugging status
wireless-debugging --version
```

Behavior:

- `on` requests activation and `status` queries the app's setting, permission and installed version. Both perform a bounded ADB check after a successful app response. `off` changes the setting and never checks or connects. `--version` only asks the app for its version; it never uses `adb`, Python or discovery.
- The app operation result, observed `adb_wifi_enabled` setting and ADB connectivity verification are reported separately. `ADB check: available` is printed only when a specific discovered local target reports `device`; otherwise the output says `ADB check: not verified` with the observed reason. An unverified ADB check does not turn a successful `on`/`status` app operation into a failure.
- The installed `adb-local-check` helper is shared by the wrapper and reboot example. Its one global deadline covers dependency imports, `adb start-server`, discovery, local connects and each `get-state`. Discovery browses only `_adb-tls-connect._tcp.local.` (IPv4) with the Python `zeroconf` in `$HOME/.venvs/adb-discovery`, validates connection ports (1024-65535, at most 8 tried; 5555 is not assumed), and tries them only on `127.0.0.1`. It never connects to advertised remote addresses and never uses the pairing service or port. Availability requires `adb -s 127.0.0.1:PORT get-state` to return `device`. Other USB/remote transports already known to adb do not count.
- It does not pair, reboot, run `adb kill-server`, disconnect other devices, touch ADB keys, change security settings, download or install anything. The adb client server may be started if needed.
- Results: `available`; `not verified` with the observed reason (missing dependencies, discovery failure, timeout, `unauthorized`, `offline`, or no usable local port). No discovered service is not proof that pairing was lost.
- `WIRELESS_DEBUGGING_TIMEOUT` (default 15) and `WIRELESS_DEBUGGING_CHECK_TIMEOUT` (default 30) each accept only 1-300 decimal seconds, with at most three digits; leading zeroes are accepted and normalized as decimal. Zero, empty, non-decimal, overlong and out-of-range values are rejected. The ADB check timeout is one global deadline including dependency imports, server startup, discovery, connect and `get-state`; the app timeout bounds only the app request.

Example output of `wireless-debugging on`:

```text
Operation: on
Result: success
adb_wifi_enabled setting (observed): ON
Required permission: granted
App version: 1.1 (code 2)
ADB check: available
ADB target: 127.0.0.1:41234
```

Exit statuses: `on`, `off`, `status` and `--version` exit 0 when the app operation or query succeeds. For `on` and `status`, an unverified ADB check, including an ADB verification timeout, is reported on standard output and does not change the successful exit status. All commands exit 1 on usage errors, invalid timeout values, token/app/protocol errors, an app request timeout or no response; messages go to standard error.

On app failure (rejected token, missing WRITE_SECURE_SETTINGS, app-request timeout, no response, mismatched response) the message goes to standard error and the exit status is nonzero.

**Update after upgrading.** Reinstall the APK (`adb -s TARGET install -r dist/wireless-debugging.apk` as described in [Build and install the app](#build-and-install-the-app); with an unchanged signing identity the token and permission are kept) and reinstall both scripts with the `install -m 700` commands above (to `$HOME/bin`). Open the app once after installing; a force-stopped app does not receive broadcasts. The old script and the new APK are not compatible.

### Control interface

The wrapper sends an explicit ordered broadcast with `am broadcast` to `local.termux.wirelessdebugging/.ControlReceiver`, action `local.termux.wirelessdebugging.CONTROL`, and string extras `operation` (`on`, `off`, `status`, `version`), `nonce` (random 128-bit request ID) and `token`. `am start` is not used because it does not return activity output. The receiver is exported, so Termux can call it, but it validates the token (constant-time comparison) before reading or changing anything or disclosing state; unauthenticated callers only learn `error=unauthorized`. The result is returned as the broadcast result data, `wd2 nonce=<id> status=ok|error op=... setting=1|0|unknown permission=granted|denied version=<versionName> version_code=<n> [error=...]`, which `am` prints. No files or world-readable channels are used, and the token is never logged or returned. Each broadcast has its own result, so concurrent requests do not interfere, and the wrapper rejects responses whose nonce differs from its own. No root, ADB connection or extra permission is needed to obtain results. The token is passed as a process argument, visible only to the same Android user's processes at most, as before.

`wireless-debugging --version` prints `App version: <versionName> (code <versionCode>)` of the installed APK without changing any setting. The app reads both values from its own package metadata (`PackageManager`), shows them on the `About` screen, and returns them only to requests with a valid token; the script contains no version of its own. If the app cannot be contacted, answers with a different protocol (`wd1` from an older APK), or reports no version, the command fails with an error on standard error instead of printing a version.

### Testing

Host checks (bash, JDK; python3 optional; no Android needed). They use fake `am`, `adb`, build tools and discovery interpreters, so they do not verify real Termux, a device or Android compilation:

```sh
bash tests/run-tests.sh
```

Source-text UI checks are structural assertions only, not functional Android tests. The Java protocol tests and wrapper integration checks use fake tools; concurrent-request checks cover nonce correlation in host test doubles only, not Android broadcast scheduling or real concurrent device operations. Fake build-tool checks exercise stale-artifact cleanup, signing-state safety and atomic publication, not Android compilation or a valid installable APK. The suite does **not** compile Android activities/receiver, exercise real Termux `am`, install or run the APK on a device, test inactivity/authorization behavior, or execute the reboot example. Those require a real Android/Termux device and the build tools.

## Example: reboot this phone over wireless ADB

`examples/reboot.sh` integrates the wrapper with local ADB discovery. This is an example to review and test on your device, not a guarantee of support on all Android implementations.

Install runtime dependencies and the isolated discovery environment in Termux:

```sh
pkg install android-tools python coreutils
python -m venv "$HOME/.venvs/adb-discovery"
"$HOME/.venvs/adb-discovery/bin/python" -m pip install zeroconf
mkdir -p "$HOME/bin"
install -m 700 examples/reboot.sh "$HOME/bin/reboot"
```

`$HOME/bin/reboot` is this project's command (the source file stays `examples/reboot.sh`). With `$HOME/bin` early on `PATH` it may shadow another `reboot`; run `type -a reboot` to check, and use the explicit path `$HOME/bin/reboot` where disambiguation matters.

The example uses `adb`, `timeout`, the installed `wireless-debugging` wrapper and the adjacent `$HOME/bin/adb-local-check` helper, plus Python with `zeroconf` at `$HOME/.venvs/adb-discovery/bin/python`. Install the helper as shown in [Install the Termux command](#install-the-termux-command). Configure the app permission, Termux special access and private token first. An authorized initial ADB connection is still required for the permission grant.

Save your work before running:

```sh
"$HOME/bin/reboot"
```

This command actually reboots the phone once connected. It does not ask for a final reboot confirmation. Publishing, downloading or installing the script does not execute it.

The example:

1. Requests `wireless-debugging on`; the shared helper starts the ADB server and verifies discovery as part of the bounded check.
2. Reuses the wrapper's structured verified-target result when available, avoiding duplicate discovery. If the wrapper could not return a result, the example runs the helper directly.
3. Browses IPv4 `_adb-tls-connect._tcp.local.` services and tries their validated ports only on `127.0.0.1`, not on remote advertised addresses.
4. Requires `adb -s TARGET get-state` to return `device`.
5. Offers explicit interactive pairing if no connection is found. Open the phone's pairing-code dialog, provide its pairing port and enter the code directly at the ADB prompt.
6. Repeats bounded discovery after pairing, then runs `adb -s TARGET reboot`.

Discovery can fail if the network does not expose mDNS or the device does not accept local connections. Pairing and connection ports are distinct; the script rediscovers the connection port. It does not disable wireless debugging before reboot, because that would interrupt the required connection, and does not guarantee its state after reboot. If discovery is cancelled or connection fails, no reboot command is issued. The example's pairing/reboot behavior and on-device integration have not been executed or verified as part of host checks.

## APK versions and releases

The manifest is the single authoritative source for `versionCode` and `versionName`. Increase `versionCode` monotonically for every published APK and update `versionName` to the corresponding release label. See [CHANGELOG.md](CHANGELOG.md) for this release's changes.

## Troubleshooting

### Buttons work but Termux does not open the app

Test the MAIN activity command and check Termux's `Display over other apps` access. Enabling it resolved the tested device's launch issue.

### Invalid token or missing permission

Use the app's current token and refresh its permission status. Clearing app data or uninstalling can invalidate the saved token. Re-run the ADB permission grant if necessary.

### termuxam exception despite a working operation

During testing, `am` printed an InvocationTargetException with a nested NullPointerException in Android AppOps calls, although the activity opened and control worked. Its exact cause is unknown.

To keep errors off the terminal while retaining a diagnostic log:

```sh
wireless-debugging off 2>"$HOME/wireless-debugging-error.log"
```

This replaces the previous log and redirects all standard error from the wrapper, not only that exception. It does not fix the failure or verify success. Do not blindly suppress failures with `|| true`. The reboot example explicitly warns on activation-command failure and independently checks ADB availability.

## Security

- Treat the token as a control credential; the activity is exported and checks it before control operations.
- Keep tokens, pairing codes, signing keys, passwords and private configuration out of Git.
- Avoid `bash -x` and diagnostic sharing that exposes intent extras. Reading a token interactively avoids a literal shell-history entry but does not make intent extras a secret transport.
- The app disables Android backup and applies FLAG_SECURE to its window.
- Disable wireless debugging when not needed; an enabled setting is not a reachability check.

## License

Copyright (C) 2026 David González López-Tercero

SPDX-License-Identifier: GPL-3.0-or-later

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See [LICENSE](LICENSE) for details.

Third-party tools and SDK components retain their respective licenses.
