# Wireless Debugging

Minimal Android companion app to control the wireless debugging system setting from Termux without root. Built directly on Android using command-line tools, without Gradle.

## Requirements and limitations

- Android 11 or later (minimum API 30; target API 33).
- Termux and Android-compatible build tools.
- An initial authorized ADB connection to grant WRITE_SECURE_SETTINGS. The app cannot grant this permission to itself.
- Developer options and wireless debugging support.

The app writes `Settings.Global.adb_wifi_enabled`. An ON setting does not guarantee ADB reachability: Android may still require network approval and pairing. The companion app itself does not pair devices or discover ports. Device behavior can vary.

## Repository layout

- `AndroidManifest.xml`: package, permission and activity declaration.
- `src/local/termux/wirelessdebugging/MainActivity.java`: interface and token-protected control.
- `build.sh`: packaging, compilation, alignment, signing and verification.
- `scripts/wireless-debugging`: Termux command wrapper.
- `examples/reboot.sh`: local wireless ADB reboot integration example.
- `build/` and `dist/`: generated files, excluded from source control.

## Build environment

Required commands on PATH:

```text
javac jar keytool aapt2 d8 zip zipalign apksigner
```

Install Android-compatible versions in Termux. Desktop SDK binaries are not necessarily executable on Android. Dependencies are not installed automatically by this repository.

The build expects the API 33 platform JAR at:

```text
$HOME/.local/share/android-sdk/platforms/android-33/android.jar
```

Provision this file or edit `PLATFORM` in `build.sh` to point to an API 33 platform JAR. Check the environment:

```sh
for tool in javac jar keytool aapt2 d8 zip zipalign apksigner; do
    command -v "$tool" || break
done
test -f "$HOME/.local/share/android-sdk/platforms/android-33/android.jar"
```

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

## Grant the app permission once

Using an authorized ADB shell connection, run:

```sh
adb shell pm grant local.termux.wirelessdebugging android.permission.WRITE_SECURE_SETTINGS
```

Use USB ADB from a computer or an already paired wireless ADB connection. Establish the initial connection before disabling wireless debugging. An ordinary Android permission dialog cannot grant this permission.

Open the app from its launcher icon to create its token. Press `Refresh status` and verify `Required permission: GRANTED`. The buttons are `Turn ON`, `Turn OFF` and `Refresh status`.

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

From the repository root:

```sh
install -m 700 scripts/wireless-debugging "$PREFIX/bin/wireless-debugging"
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

This replaces any existing token file. Never commit it. Reconfigure it if the app's token changes.

Usage:

```sh
wireless-debugging on
wireless-debugging off
wireless-debugging status
```

`status` requests an Android toast; it does not return structured status on standard output. `Request sent` is not confirmation that the setting changed. Verify using `Refresh status` in the app. The wrapper retains the activity launcher's error behavior rather than silently converting failures to success.

### Intent interface

The wrapper sends an explicit intent to `local.termux.wirelessdebugging/.MainActivity` with action `local.termux.wirelessdebugging.CONTROL` and string extras `operation` (`on`, `off`, `status`) and `token`. The handler validates the token, reports a toast and finishes. Shell exit status does not reliably represent the app's operation result.

## Example: reboot this phone over wireless ADB

`examples/reboot.sh` integrates the wrapper with local ADB discovery. This is an example to review and test on your device, not a guarantee of support on all Android implementations.

Install runtime dependencies and the isolated discovery environment in Termux:

```sh
pkg install android-tools python coreutils
python -m venv "$HOME/.venvs/adb-discovery"
"$HOME/.venvs/adb-discovery/bin/python" -m pip install zeroconf
install -m 700 examples/reboot.sh "$PREFIX/bin/wireless-reboot"
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
