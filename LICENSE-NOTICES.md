# License Notices

## This project (easytier_flutter)

The Flutter/Kotlin application code in this repository (`lib/`, `android/app/src/main/kotlin/io/github/xiaonan520/`) is an independent third-party client, released under the GNU Lesser General Public License v3.0 (LGPL-3.0), consistent with the upstream EasyTier license.

This is NOT the official EasyTier Android app and is not affiliated with or endorsed by the EasyTier project or its authors.

## EasyTier upstream components

- `android/app/src/main/kotlin/com/easytier/jni/EasyTierJNI.kt` — copied from
  [`easytier-contrib/easytier-android-jni`](https://github.com/EasyTier/EasyTier/tree/main/easytier-contrib/easytier-android-jni)
  (upstream main @ ff3921c), package name kept as `com.easytier.jni`.
- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so` — built from the
  same upstream commit with `cargo ndk`; bundles easytier-ffi and easytier-core.
- `EasyTierVpnService.kt` — adapted from the official
  [`tauri-plugin-vpnservice`](https://github.com/EasyTier/EasyTier/tree/main/tauri-plugin-vpnservice)
  `TauriVpnService.kt` and the easytier-android-jni reference service.

EasyTier is licensed under the GNU LGPL-3.0
(https://github.com/EasyTier/EasyTier/blob/main/LICENSE).
These components remain subject to their original license and copyright.

Upstream project: https://github.com/EasyTier/EasyTier
