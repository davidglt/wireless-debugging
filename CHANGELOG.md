# Changelog

## 1.1 (versionCode 2)

- Added bounded, shared local ADB discovery and stricter authenticated response validation.
- Reused verified ADB targets in the reboot example without changing its explicit pairing and reboot behavior.
- Hardened APK generation, signing-state checks, and publication after alignment and signature verification.
- Verified the setting after UI writes and clarified that setting status does not establish ADB connectivity.
- Added host-side protocol, shell, build-safety, and CI checks.

APK `versionCode` and `versionName` are defined only in `AndroidManifest.xml`. Increase `versionCode` monotonically for each release.
