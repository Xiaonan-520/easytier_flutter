# EasyTier Flutter (Android)

A third-party [EasyTier](https://github.com/EasyTier/EasyTier) mesh VPN client for Android, built with Flutter and Material 3. **This is not the official EasyTier Android app** and is not affiliated with or endorsed by the EasyTier project or its authors.

The app does not reimplement any networking: it embeds the official EasyTier JNI library (`easytier-android-jni` → `easytier-ffi` → `easytier-core`) and drives it through a Flutter UI, with Android's `VpnService` providing the TUN interface.

## Core features

- **Connect / disconnect** to an EasyTier network with one tap; live connection state, node IP and version from the core.
- **Real traffic statistics** — RX/TX rates and session totals sampled differentially from the core's peer stats, shown on the Home card and in the notification.
- **Peer list with details** — latency, cost, and per-peer connection type (P2P vs. relayed) derived from route cost; per-peer traffic.
- **Multiple network profiles** — create, edit, switch and delete; the selected profile survives restarts.
- **Config import** — import official EasyTier `.toml` config files (file picker or pasted text) into a new profile; strict field mapping against the core's `Config` struct, unknown sections are skipped with a warning, legacy aliases are mapped with an explicit warning, parse errors report the offending line.
- **Config export** — render any profile as official EasyTier TOML (the exact bytes the core accepts), preview it, then save via the system file picker (SAF) or share it; a clear warning is shown when the network secret is written in clear text.
- **Theme presets** — four Material 3 seed palettes (Default / Blue / Green / Purple), each with light and dark variants plus a System mode; selection persists across restarts.
- **Foreground service + notification** with live rates and a disconnect action.

## UI overview

The app has four bottom-navigation tabs:

| Tab | Contents |
| --- | --- |
| **Home** | Connect/disconnect card, connection state, node IP, real-time traffic card (rates + totals) |
| **Networks** | Profile list with status dots, import (`.toml` file or pasted text) and export entry points, full profile editor (display name, instance name, secret, peer URLs, DHCP / static IPv4, hostname, advanced flags) |
| **Peers** | Connected peers with latency and connection type; detail sheet with per-peer traffic |
| **Settings** | Appearance (theme presets, light/dark/system), diagnostics (core status, logs), about |

## Configuration import & export

- **Import** lives on the Networks tab. Both the official config format (`instance_name`, `[network_identity]`, `[[peer]]`, `ipv4`, `dhcp`, `[flags]`) and the legacy aliases found in the wild (`inst_name`, top-level `network` / `network_secret` / `peers`) are accepted; anything unrecognized is reported, never silently guessed. Imported configs always become a **new** profile — the currently selected network is untouched until you switch.
- **Export** lives in the network editor. It re-renders the profile through the same TOML builder the app feeds to the core, so an exported file round-trips through import (and works with `easytier-core` / the official GUI) unchanged.

## Multiple profiles

Profiles are stored locally in `shared_preferences` (`flutter.`-prefixed keys) and managed by `ProfileStore`. One profile is "current" at a time; connecting starts the VPN for that profile. Deleting profiles never touches other profiles or the running state.

## EasyTier core / JNI / VPN architecture

```
Flutter (Dart)
  └─ MethodChannel 'easytier_flutter/core'   (lib/native/easytier_bridge.dart)
       └─ Kotlin MainActivity / VPN service   (android/app/src/main/kotlin/...)
            ├─ com.easytier.jni.EasyTierJNI   (official JNI bindings, copied verbatim)
            │    └─ libeasytier_android_jni.so  → easytier-ffi → easytier-core
            └─ EasyTierVpnService (Android VpnService) — TUN fd → EasyTierJNI.setTunFd()
```

- `libeasytier_android_jni.so` (arm64-v8a) is built from EasyTier upstream `main` @ `ff3921c` with `cargo ndk`; the Kotlin binding `EasyTierJNI.kt` is copied verbatim from [`easytier-contrib/easytier-android-jni`](https://github.com/EasyTier/EasyTier/tree/main/easytier-contrib/easytier-android-jni) and **must match the `.so`** — see [docs/integration.md](docs/integration.md).
- `EasyTierVpnService.kt` is adapted from the upstream `tauri-plugin-vpnservice` reference service: it owns `VpnService.establish()`, hands the TUN fd to the core via `setTunFd`, and tears down the instance on disconnect.
- Status, peer lists and traffic counters are polled from the core as JSON (`collectNetworkInfos`) and parsed tolerantly (prost serializes `u64` counters as strings).

## Build & run

Requirements:

- Flutter (Dart SDK ^3.13.4) with the Android toolchain
- Android SDK; a device or emulator running Android 10+ (arm64-v8a; the bundled `.so` is arm64 only)

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug      # or --release
flutter install                # or: adb install build/app/outputs/flutter-apk/app-*.apk
```

The app runs against any EasyTier network — join via public peers, a self-hosted server, or a direct connection; configure them per profile on the Networks tab.

## Upstream & license

- Upstream project: <https://github.com/EasyTier/EasyTier> (GNU LGPL-3.0)
- Official JNI example this app builds on: [`easytier-contrib/easytier-android-jni`](https://github.com/EasyTier/EasyTier/tree/main/easytier-contrib/easytier-android-jni)
- This repository: <https://github.com/Xiaonan-520/easytier_flutter>

This project's own code (the Flutter app under `lib/` and the Android app shell) is licensed under the **GNU Lesser General Public License v3.0 (LGPL-3.0)**, consistent with upstream. Bundled EasyTier components (`EasyTierJNI.kt`, the prebuilt `.so`, `EasyTierVpnService.kt`) remain subject to their original LGPL-3.0 license and copyright — see [LICENSE-NOTICES.md](LICENSE-NOTICES.md).

## Disclaimer

This is an independent third-party client. It is not the official EasyTier Android app and is not affiliated with or endorsed by the EasyTier project or its authors. EasyTier core is used under its upstream license. Use at your own risk.
