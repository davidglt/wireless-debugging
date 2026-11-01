# Set up the Android API 33 platform

[Back to the project README](../README.md)

The build uses an Android SDK platform JAR for compilation and resource linking. Installing Android 13 on the phone does not supply this SDK file to Termux. This guide documents setup; the commands have not yet been tested end to end on the reported Samsung device.

## Required location

`build.sh` expects:

```text
$HOME/.local/share/android-sdk/platforms/android-33/android.jar
```

The platform is separate from the Termux-native `aapt2`, `d8`, `zipalign` and `apksigner` tools. Continue using those Termux tools; do not replace them with desktop-native SDK executables.

Before downloading or using the SDK, review the applicable [Android SDK terms](https://developer.android.com/studio/terms). The manual method below does not run the SDK Manager or record license acceptance for other SDK tools.

## Option A: install the platform directly in Termux

Install download and archive utilities:

```sh
pkg install curl unzip coreutils
```

Also install the Java/build tools described in the README. The verification commands below require `jar` on PATH.

This procedure pins Google's `platform-33-ext5_r01.zip`: Android API 33 with extension level 5. The extension level does not change the base API level to 34 or upgrade the phone. This project does not rely on extension-only APIs.

The SHA-256 digest is taken from the Android Perfetto dependency definition for that exact archive:

```text
3d6189a18d0cebd4e518b8728de0e6b940d95c96b57316769dd56ee2d1708d10
```

Source: [Perfetto dependency definitions](https://android.googlesource.com/platform/external/perfetto/+/refs/heads/ui-stable/tools/install-build-deps).

Run the following in Bash. It downloads into a temporary directory, verifies the digest before extraction, checks API metadata and JAR contents, and refuses to overwrite an existing installation.

```bash
(
    set -euo pipefail

    destination="$HOME/.local/share/android-sdk/platforms/android-33"
    url='https://dl.google.com/android/repository/platform-33-ext5_r01.zip'
    expected='3d6189a18d0cebd4e518b8728de0e6b940d95c96b57316769dd56ee2d1708d10'

    for tool in curl unzip sha256sum jar find grep cp mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            printf 'Error: required command not found: %s\n' "$tool" >&2
            exit 1
        fi
    done

    if [[ -e "$destination" || -L "$destination" ]]; then
        printf 'Existing platform directory: %s\n' "$destination" >&2
        printf 'Verify it first; no files were replaced.\n' >&2
        exit 1
    fi

    work="$(mktemp -d)"
    trap 'rm -rf -- "$work"' EXIT

    curl --fail --location --retry 3 \
        --output "$work/platform.zip" "$url"
    printf '%s  %s\n' "$expected" "$work/platform.zip" | sha256sum --check -

    unzip -q "$work/platform.zip" -d "$work/extracted"
    mapfile -t jars < <(find "$work/extracted" -type f -name android.jar)
    if (( ${#jars[@]} != 1 )); then
        printf 'Error: expected exactly one platform android.jar.\n' >&2
        exit 1
    fi

    platform="$(dirname -- "${jars[0]}")"
    grep -Eq '^AndroidVersion\.ApiLevel[[:space:]]*=[[:space:]]*33[[:space:]]*$' \
        "$platform/source.properties"
    jar --list --file "$platform/android.jar" > "$work/jar-entries"
    grep -Fx 'android/app/Activity.class' "$work/jar-entries" >/dev/null

    mkdir -p -- "$(dirname -- "$destination")"
    cp -R -- "$platform" "$destination"
    printf 'Installed platform: %s\n' "$destination"
)
```

The entire extracted platform directory is copied, not only the JAR, preserving its metadata and supporting files. The fixed local directory name matches this project's build script; this manual copy is not a substitute for SDK Manager package management.

If the URL fails or the checksum differs, stop. Do not remove checksum verification, substitute a random mirror, or change the digest merely to make a download pass. Recheck Google's SDK package metadata or use Option B.

## Option B: use an official SDK installation on a computer

On a supported computer with Android Studio, open SDK Manager and select `Android SDK Platform 33` under Android 13. Install it and review any license prompts. See [Set up the Android 13 SDK](https://developer.android.com/about/versions/13/setup-sdk).

Alternatively, with Google's command-line SDK tools installed on that computer and `sdkmanager` on PATH, run:

```sh
sdkmanager --install "platforms;android-33"
```

Use the SDK root configured for that installation and respond to any license prompts. Do not pipe automatic acceptance into license prompts. If necessary, pass `--sdk_root` with that installation's actual SDK root.

Transfer the installed `platforms/android-33` directory from the computer to the phone using a trusted file-transfer method. Then place it under:

```text
$HOME/.local/share/android-sdk/platforms/android-33
```

For example, if you transferred the complete directory to the phone's Downloads folder, first grant Termux shared-storage access:

```sh
termux-setup-storage
```

Then copy it, refusing to overwrite an existing platform:

```bash
(
    set -euo pipefail
    source="$HOME/storage/downloads/android-33"
    destination="$HOME/.local/share/android-sdk/platforms/android-33"
    test -s "$source/android.jar"
    if [[ -e "$destination" || -L "$destination" ]]; then
        printf 'Error: destination already exists; no files were replaced.\n' >&2
        exit 1
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    cp -R -- "$source" "$destination"
)
```

Adjust the source path to where you actually transferred the platform. Copy only the platform directory; continue using the native Termux build-tools packages.

## Verify and build

```bash
(
    set -euo pipefail
    platform="$HOME/.local/share/android-sdk/platforms/android-33"
    test -s "$platform/android.jar"
    grep -Eq '^AndroidVersion\.ApiLevel[[:space:]]*=[[:space:]]*33[[:space:]]*$' \
        "$platform/source.properties"
    jar --list --file "$platform/android.jar" >/dev/null
    printf 'API 33 platform is available at: %s\n' "$platform"
)
```

These checks establish that metadata reports API 33 and the JAR is readable; they do not replace archive provenance and integrity checks.

From the repository directory:

```sh
bash build.sh
```

Expected output: `dist/wireless-debugging.apk`, with alignment and signature verification performed by the build script. Installing the platform does not change the app's minimum SDK, target SDK, Android permissions, token or ADB pairing.

## Existing installation or a different SDK root

If `android.jar` already exists and the build works, you do not need to download it again. Verify the existing metadata and preserve a working installation before replacing anything.

If a valid API 33 platform already lives elsewhere, edit the `PLATFORM` assignment in `build.sh` to its `android.jar` path. Merely exporting `ANDROID_HOME` does not change the current script's hard-coded `PLATFORM` assignment.

Do not commit the downloaded SDK, extracted platform or temporary archives into this project. Keep them under the external SDK directory shown above.
