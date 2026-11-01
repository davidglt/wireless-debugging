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
- `examples/reboot.sh`: local wireless ADB reboot integration example.
- `build/` and `dist/`: generated files, excluded from source control.

## Build environment

Required commands on PATH:

```text
java javac jar keytool aapt2 d8 zip zipalign apksigner
```

### Install build tools in Termux

Run these commands inside Termux, not in an ADB shell or a desktop Linux terminal:

```sh
pkg update &&
pkg install git openjdk-21 aapt aapt2 d8 apksigner zip
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

The Android tool package ownership above was checked in the development device's installed package database: `zipalign` belongs to `aapt`, not to a separate package named `zipalign`. OpenJDK 21 is the installation option documented here; the original device's Java package/version was not established by that check. A missing package owner for a command path does not by itself prove a manual installation, because the path may be a symlink.

Use Termux-native tools for the device architecture. Desktop SDK binaries are not necessarily executable on Android. This project does not need Gradle, Android Studio, a Linux distribution in proot, or root for this build pipeline. The build script does not install dependencies automatically.

These packages do not provision the API 33 platform JAR at the project-specific path below. That is a separate requirement. The reboot example's `android-tools`, Python and `zeroconf` dependencies are also separate from compilation tools.

Official package definitions: [aapt](https://github.com/termux/termux-packages/tree/master/packages/aapt), [aapt2](https://github.com/termux/termux-packages/blob/master/packages/aapt/aapt2.subpackage.sh), [d8](https://github.com/termux/termux-packages/tree/master/packages/d8), and [apksigner](https://github.com/termux/termux-packages/tree/master/packages/apksigner).

### Check all required commands

Run in Bash. The subshell reports every missing command and returns a nonzero status without closing your interactive shell:

```bash
(
    missing=0
    for tool in java javac jar keytool aapt2 d8 zip zipalign apksigner; do
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
termux-open --view --content-type application/vnd.android.package-archive dist/wireless-debugging.apk
```

Allow installation from the source Android identifies if prompted, then confirm installation. Alternatively, transfer the APK to a computer and run `adb install -r wireless-debugging.apk`.

The build verifies alignment and signatures. It creates a local signing key and password outside the repository:

```text
$HOME/.local/share/wireless-debugging/signing/local-signing.p12
$HOME/.local/share/wireless-debugging/signing/store-password
```

Keep both files private, back them up securely and reuse the same key for updates. Do not commit them.

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

For the integration example, `wireless-reboot` performs discovery and connection, but it will actually reboot the phone as soon as it connects. Do not use it merely as a harmless connection test. Use the manual `get-state` command above for a non-rebooting check.

Official background: [Android Debug Bridge wireless pairing](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi) and [Android authorization-timeout implementation](https://android.googlesource.com/platform/packages/apps/Settings/+/master/src/com/android/settings/development/AdbAuthorizationTimeoutPreferenceController.java). Newer Android features described in upstream documentation are not necessarily available on Android 13.

## Grant the app permission once

Using an authorized ADB shell connection, run:

```sh
adb shell pm grant local.termux.wirelessdebugging android.permission.WRITE_SECURE_SETTINGS
```

Use USB ADB from a computer or an already paired wireless ADB connection. Establish the initial connection before disabling wireless debugging. An ordinary Android permission dialog cannot grant this permission. If several devices are connected, specify the intended device with `adb -s TARGET`, as in the local pairing example above.

Open the app from its launcher icon; this creates the token if none exists. The main screen shows the current setting and permission status with `Turn ON`, `Turn OFF`, `Refresh status`, `Setup` and `About`. Press `Refresh status` and verify `Required permission: GRANTED`. `Setup` shows the permission command (with `Copy command`), Termux instructions and the control token, which stays hidden until `Show token` is pressed (`Hide token`, `Copy token` also available; opening Setup never replaces an existing token, and the screens use `FLAG_SECURE`). `About` shows the installed version (read from package metadata), author, copyright, license and project link.

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

From the repository root, install the command in the user-local directory:

```sh
mkdir -p "$HOME/.local/bin"
install -m 700 scripts/wireless-debugging "$HOME/.local/bin/wireless-debugging"
```

If `$HOME/.local/bin` is not on your `PATH`, add it (for example to `~/.bashrc`) and reload the shell:

```sh
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"
```

This replaces an existing command at that path. Back up a customized version first.

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
    printf '%s\n' "$CONTROL_TOKEN" > "$HOME/.config/wireless-debugging/token"
    chmod 600 "$HOME/.config/wireless-debugging/token"
    unset CONTROL_TOKEN
)
```

This replaces any existing token file. Never commit it. Reconfigure it if the app's token changes. The app control token is separate from ADB keys and pairing codes.

Usage:

```sh
wireless-debugging on
wireless-debugging off
wireless-debugging status
wireless-debugging check
wireless-debugging --version
```

Behavior:

- `on` and `status` run the app operation and, if it succeeds, a bounded ADB check. `off` changes the setting and never checks or connects. `--version` only asks the app for its version; it never uses `adb`, Python or discovery.
- `check` queries the app state without changing the setting (it sends `status`) and then verifies a usable local ADB transport.
- The observed `adb_wifi_enabled` setting and the ADB check are reported separately. An ADB check that is not verified does not turn a successful `on`/`status` into a failure.
- The ADB check browses only `_adb-tls-connect._tcp.local.` (IPv4) with the Python `zeroconf` in `$HOME/.venvs/adb-discovery`, validates each advertised connection port (1024-65535, at most 8 tried; 5555 is not assumed), and tries them only on `127.0.0.1`. It never connects to advertised remote addresses and never uses the pairing service or port. For each port it runs `adb connect 127.0.0.1:PORT` and `adb -s 127.0.0.1:PORT get-state`, and requires `device`. Other USB/remote transports already known to adb do not count.
- It does not pair, reboot, run `adb kill-server`, disconnect other devices, touch ADB keys, change security settings, download or install anything. The adb client server may be started if needed.
- Results: `available`; `not verified` with the observed reason (missing dependencies, discovery failure, timeout, `unauthorized`, `offline`, or no usable local port). No discovered service is not proof that pairing was lost.
- `WIRELESS_DEBUGGING_CHECK_TIMEOUT` (integer 1-300 seconds, default 30) bounds the whole ADB check including discovery and all connection attempts. `WIRELESS_DEBUGGING_TIMEOUT` still bounds the app request.

Example output of `wireless-debugging on`:

```text
Operation: on
Result: success
adb_wifi_enabled setting (observed): ON
Required permission: granted
App version: 1.0 (code 1)
ADB check: available
ADB target: 127.0.0.1:41234
```

Exit statuses: `on`, `off`, `status` and `--version` exit 0 when the app operation succeeded (the ADB check result is on standard output only). `check` exits 0 only when the local transport is verified as `device`, and 1 otherwise. All commands exit 1 on usage errors, invalid timeouts, token/app/protocol errors, timeouts or no response; messages go to standard error.

On failure (rejected token, missing WRITE_SECURE_SETTINGS, timeout, no response, mismatched response) the message goes to standard error and the exit status is nonzero.

**Update after upgrading.** Reinstall the APK (`adb install -r dist/wireless-debugging.apk` or the `termux-open` method above; the signing key is unchanged so the token and permission are kept) and reinstall the script with the `install -m 700` command above. Open the app once after installing; a force-stopped app does not receive broadcasts. The old script and the new APK are not compatible.

### Control interface

The wrapper sends an explicit ordered broadcast with `am broadcast` to `local.termux.wirelessdebugging/.ControlReceiver`, action `local.termux.wirelessdebugging.CONTROL`, and string extras `operation` (`on`, `off`, `status`, `version`), `nonce` (random 128-bit request ID) and `token`. `am start` is not used because it does not return activity output. The receiver is exported, so Termux can call it, but it validates the token (constant-time comparison) before reading or changing anything or disclosing state; unauthenticated callers only learn `error=unauthorized`. The result is returned as the broadcast result data, `wd2 nonce=<id> status=ok|error op=... setting=1|0|unknown permission=granted|denied version=<versionName> version_code=<n> [error=...]`, which `am` prints. No files or world-readable channels are used, and the token is never logged or returned. Each broadcast has its own result, so concurrent requests do not interfere, and the wrapper rejects responses whose nonce differs from its own. No root, ADB connection or extra permission is needed to obtain results. The token is passed as a process argument, visible only to the same Android user's processes at most, as before.

`wireless-debugging --version` prints `App version: <versionName> (code <versionCode>)` of the installed APK without changing any setting. The app reads both values from its own package metadata (`PackageManager`), shows them on the `About` screen, and returns them only to requests with a valid token; the script contains no version of its own. If the app cannot be contacted, answers with a different protocol (`wd1` from an older APK), or reports no version, the command fails with an error on standard error instead of printing a version.

### Testing

Host checks (bash, JDK; python3 optional; no Android needed). They use fake `am`, `adb` and discovery interpreters, so they do not verify real Termux, a device or Android compilation:

```sh
bash tests/run-tests.sh
```

It also does simple source-level checks of the UI structure (buttons, token not on the main screen, `FLAG_SECURE`, non-exported screens). This tests `ControlProtocol` (valid status/on/off/version, invalid token, missing permission, bad operation/nonce, concurrent requests) and the wrapper against a fake `am` (same cases plus `--version`, an incompatible old-protocol app, timeout, malformed and mismatched responses, missing token file, parallel invocations). It does **not** compile `ControlReceiver`/`MainActivity` against Android, run the aapt2/d8 build, or exercise real Termux `am`; verify those on a device by running `./build.sh`, installing, then `wireless-debugging status|on|off`. Whether Termux's `am` prints `Broadcast completed: result=..., data="..."` on a given version has to be confirmed on a device.

## Example: reboot this phone over wireless ADB

`examples/reboot.sh` integrates the wrapper with local ADB discovery. This is an example to review and test on your device, not a guarantee of support on all Android implementations.

Install runtime dependencies and the isolated discovery environment in Termux:

```sh
pkg install android-tools python coreutils
python -m venv "$HOME/.venvs/adb-discovery"
"$HOME/.venvs/adb-discovery/bin/python" -m pip install zeroconf
mkdir -p "$HOME/.local/bin"
install -m 700 examples/reboot.sh "$HOME/.local/bin/wireless-reboot"
```

The example uses `adb`, `timeout`, the installed `wireless-debugging` wrapper, and Python with `zeroconf` at `$HOME/.venvs/adb-discovery/bin/python`. Configure the app permission, Termux special access and private token first. An authorized initial ADB connection is still required for the permission grant.

Save your work before running:

```sh
wireless-reboot
```

This command actually reboots the phone once connected. It does not ask for a final reboot confirmation. Publishing, downloading or installing the script does not execute it.

The example:

1. Starts the ADB server and requests `wireless-debugging on`.
2. Continues with discovery even if the launcher reports an error, because an observed launcher exception did not prevent the operation.
3. Browses IPv4 `_adb-tls-connect._tcp.local.` services for eight seconds and tries their advertised ports on `127.0.0.1`, not on remote advertised addresses.
4. Requires `adb -s TARGET get-state` to return `device`.
5. Offers interactive pairing if no connection is found. Open the phone's pairing-code dialog, provide its pairing port and enter the code directly at the ADB prompt.
6. Repeats discovery after pairing, then runs `adb -s TARGET reboot`.

Discovery can fail if the network does not expose mDNS or the device does not accept local connections. Pairing and connection ports are distinct; the script rediscovers the connection port. It does not disable wireless debugging before reboot, because that would interrupt the required connection, and does not guarantee its state after reboot. If discovery is cancelled or connection fails, no reboot command is issued. The polling and pairing flow is retained from the supplied example; the newly added activation integration still needs device testing.

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
