# Wireless Debugging

Minimal Android companion app to control the wireless debugging system setting from Termux without root. Built directly on Android using command-line tools, without Gradle.

## Requirements and limitations

- Android 11 or later (minimum API 30; target API 33).
- Termux with the build tools listed below.
- An initial ADB connection with shell privileges to grant WRITE_SECURE_SETTINGS. Root is not required, but the app cannot grant this permission to itself.
- Developer options and wireless debugging support on the device.

The app writes the global `adb_wifi_enabled` setting. An ON value does not guarantee that ADB is reachable: Android may still require network approval, pairing, or other setup. The app does not perform pairing or discover ADB ports. Behavior can vary by device.

## Repository layout

- `AndroidManifest.xml`: package, permissions and activity declaration.
- `src/local/termux/wirelessdebugging/MainActivity.java`: interface and token-protected control handler.
- `build.sh`: resource packaging, Java compilation, DEX generation, APK alignment, signing and verification.
- `build/`: generated intermediate files, not source.
- `dist/`: generated APK and possible signature sidecar, not source.

The standalone `wireless-debugging` shell wrapper used during development is not included in this repository. Direct Termux commands are documented below.

## Build environment

The build script requires these commands on PATH:

```text
javac jar keytool aapt2 d8 zip zipalign apksigner
```

Install Android-compatible versions of the tools in Termux. A desktop SDK binary is not necessarily executable on Android. The repository does not install these dependencies automatically.

The script expects the Android API 33 platform JAR at:

```text
$HOME/.local/share/android-sdk/platforms/android-33/android.jar
```

Provision that platform JAR before building, or edit `PLATFORM` in `build.sh` to point to your API 33 platform JAR.

Check the environment:

```sh
for tool in javac jar keytool aapt2 d8 zip zipalign apksigner; do
    command -v "$tool" || break
done
test -f "$HOME/.local/share/android-sdk/platforms/android-33/android.jar"
```

## Build

```sh
git clone https://github.com/davidglt/wireless-debugging.git
cd wireless-debugging
bash build.sh
```

For an existing checkout, run `bash build.sh` from the project directory.

Output:

```text
dist/wireless-debugging.apk
```

The script verifies APK alignment and signatures before reporting success.

### Signing key

On the first build, the script creates a local PKCS12 signing key and password file outside the repository:

```text
$HOME/.local/share/wireless-debugging/signing/local-signing.p12
$HOME/.local/share/wireless-debugging/signing/store-password
```

Keep both files private and back them up securely. Reuse the same signing key for updates to an installed copy. Do not commit either file.

## Install

From Termux, request installation through Android's package installer:

```sh
termux-open --view --content-type application/vnd.android.package-archive dist/wireless-debugging.apk
```

Allow installation from the source Android identifies if prompted, and confirm installation. Alternatively, transfer the APK to a computer with ADB and run:

```sh
adb install -r wireless-debugging.apk
```

Open Wireless Debugging from the launcher once to create its private control token.

## Grant the app permission once

Using an authorized ADB connection, run:

```sh
adb shell pm grant local.termux.wirelessdebugging android.permission.WRITE_SECURE_SETTINGS
```

This may use a computer over USB or an already paired wireless ADB connection. If wireless ADB is the only connection, establish it before trying to disable wireless debugging.

Open the app and press `Refresh status`. It should show `Required permission: GRANTED`. The interface provides `Turn ON`, `Turn OFF` and `Refresh status`.

## Allow Termux to open the activity

On the device tested during development, enabling the following special access for Termux was necessary:

```text
Settings → Apps → Special app access → Display over other apps → Termux → Allow
```

Names vary by manufacturer. Spanish labels include `Mostrar encima`, `Mostrar sobre otras aplicaciones` and `Aparecer encima`. Grant this access to Termux, not to Wireless Debugging. This is separate from WRITE_SECURE_SETTINGS, which is granted to the companion app.

To test activity launching from Termux:

```sh
am start --user 0 \
    -n local.termux.wirelessdebugging/.MainActivity \
    -a android.intent.action.MAIN
```

The app interface should appear. The text `Starting: Intent ...` alone does not confirm that it appeared. The `--user 0` examples assume the owner Android user; other profiles require the corresponding user ID.

## Control from Termux

The app accepts explicit intents with:

- Action: `local.termux.wirelessdebugging.CONTROL`
- Component: `local.termux.wirelessdebugging/.MainActivity`
- String extra `token`: the private token displayed by the app.
- String extra `operation`: `on`, `off` or `status`.

Read the token without putting its literal value in shell history:

```bash
read -r -s -p 'Control token: ' CONTROL_TOKEN
printf '\n'
```

Enter the token displayed in the app. Then send a request, for example:

```bash
am start --user 0 \
    -a local.termux.wirelessdebugging.CONTROL \
    -n local.termux.wirelessdebugging/.MainActivity \
    --es token "$CONTROL_TOKEN" \
    --es operation off
```

Replace `off` with `on` to enable the setting, or with `status` to request a status toast. When finished:

```bash
unset CONTROL_TOKEN
```

Requests launch an activity; they are not a structured command-response API. The handler reports results using Android toasts and then finishes. A successful launch, wrapper message such as `Request sent`, or shell exit code does not prove that the requested setting was applied. Verify with `Refresh status` in the app. Status reports the setting, not network reachability.

## Troubleshooting

### Buttons work, but Termux does not open the app

Test the MAIN activity command above. Check Termux's `Display over other apps` access first; enabling it resolved the observed launch problem on the tested device. This is an observed device-specific fix, not a guarantee for every Android version or manufacturer.

### Permission is not granted

Run the ADB permission command, then refresh the interface. The ordinary Android permission dialog cannot grant this special permission.

### Invalid control token

Open the app and use its current token. Clearing app data or reinstalling after uninstalling can invalidate previously stored tokens. Never publish the token.

### termuxam exception after the app opens

During testing, Termux's `am` printed an InvocationTargetException with a nested NullPointerException in Android AppOps calls. The app still opened and control requests worked on that device. The exact cause has not been established.

To save standard error without displaying it, append this redirection to the `am start` command:

```sh
2>"$HOME/wireless-debugging-error.log"
```

Place it at the end of the command, continuing the preceding line with a backslash if necessary. This hides all standard-error output from that command, not only this exception, and replaces the previous log. It does not fix the exception or establish success. Do not add `|| true` to conceal failures.

## Security

- The exported activity checks a private token before changing the setting. Treat that token as a control credential.
- Do not commit tokens, signing keys, passwords or private configuration.
- Avoid shell tracing such as `bash -x` when the token is in use; intent extras may also be exposed in diagnostic output.
- Read the token interactively rather than typing its literal value into commands saved in shell history. This does not make intent extras a secret transport.
- The app disables Android backup and applies FLAG_SECURE to its activity window.
- Disable wireless debugging when it is not needed.
