# HANDOFF — EasyTier Flutter (Android)

> Written for a **new agent with no prior chat context**. Everything below comes
> from the current code, the git history, or live tests on a real device.
> Facts and unverified claims are separated; anything untested says so.
>
> Read `README.md` first, then this file.

---

## 0. TL;DR

- Third-party (non-official) **EasyTier mesh-VPN client for Android**, built with
  Flutter + Material 3, package `io.github.xiaonan520.easytier_flutter`.
- It does **not** reimplement networking: it embeds the official
  `libeasytier_android_jni.so` (arm64-v8a) and drives it over a MethodChannel,
  with Android's `VpnService` supplying the TUN interface.
- Feature-complete for daily use and verified on a real device: connect /
  disconnect, real traffic stats, peer list with P2P-vs-relay detection,
  multi-profile management, official TOML import **and** export, theme presets,
  foreground service + notification.
- 33 tests pass; `flutter analyze` is clean; the APK builds.
- Planned but **not started**: Quick Settings Tile.

---

## 1. Architecture (read the code, not the diagram)

```
Flutter UI (lib/features/*, StreamBuilder)
    │
EasyTierService        lib/core/services/easytier_service.dart  (state machine + 3 s poll)
    │
EasyTierBridge         lib/native/easytier_bridge.dart          (MethodChannel + JSON parsing)
    │  MethodChannel 'easytier_flutter/core'
MainActivity.kt        android/app/src/main/kotlin/io/github/xiaonan520/easytier_flutter/
    ├─ EasyTierJNI.kt          (com.easytier.jni — official binding, copied verbatim)
    └─ EasyTierVpnService.kt   (VpnService: establish() → setTunFd)
    │
Rust core  libeasytier_android_jni.so → easytier-ffi → easytier-core
```

| Component | File | Responsibility |
| --- | --- | --- |
| `RootScaffold` | `lib/app/app.dart` | owns the single `EasyTierService`, bottom navigation, tab jumps |
| `EasyTierService` | `lib/core/services/easytier_service.dart` | `CoreState{idle,starting,running,stopping,error}`; connect = parseConfig → runNetworkInstance → wait for virtual IP → prepare/start VPN; 3 s status poll; traffic sampling |
| `EasyTierBridge` | `lib/native/easytier_bridge.dart` | MethodChannel calls; tolerant JSON parsing (prost serialises `u64` counters as **strings**, IPs as **u32 big-endian**) |
| `EasyTierVpnService` | `android/.../com/easytier/jni/EasyTierVpnService.kt` | `establish()`, keeps the TUN **fd ownership on the Java side** (the core uses `close_fd_on_drop(false)`), `stopNow()` for synchronous teardown, foreground notification, `dbg()` file logging |
| `EasyTierJNI` | `android/.../com/easytier/jni/EasyTierJNI.kt` | upstream binding — **must stay in sync with the bundled `.so`** |
| Storage | `lib/core/storage/*.dart` | `ProfileStore` (profiles), `ConfigStore` (legacy single config), `ThemeStore` (theme + mode) — all `shared_preferences` |

---

## 2. Features (all implemented and device-verified)

- **Connect / disconnect** with live state, node IP and core version.
- **Real traffic statistics** — RX/TX rates and totals, sampled differentially
  from the core's peer stats; shown on Home and in the notification. No fake
  numbers (0 renders as an em dash).
- **Peer list** — latency, cost, per-peer traffic and **connection type**
  (cost == 1 with conns ⇒ P2P, otherwise Relay).
- **Multi-profile** — create / edit / switch / delete; selection survives restart.
- **Import official TOML** — file picker (SAF) or pasted text; strict mapping
  against the core's `Config` struct; unknown sections skipped with a warning;
  legacy aliases (`inst_name`, top-level `network` / `network_secret` / `peers`)
  mapped with an explicit warning; parse errors report the offending line.
  Imports always create a **new** profile.
- **Export official TOML** — re-renders through the same builder fed to the core,
  so exported files round-trip and work with `easytier-core` / the official GUI;
  preview + red plain-text-secret warning + SAF save / system share.
- **Theme presets** — four Material 3 seed palettes (Default / Blue / Green /
  Purple) × light / dark / system, persisted.
- **Foreground service + notification** with rates and a disconnect action.
- **Settings**: appearance, diagnostics (core status, logs), about (GitHub link).

### UI tabs

| Tab | Contents |
| --- | --- |
| Home | connect/disconnect card, state, node IP, traffic card |
| Networks | profile list, import entry, export entry, full editor |
| Peers | peer list with latency / type, detail sheet with per-peer traffic |
| Settings | appearance, diagnostics, about |

(The README calls out four tabs; `app.dart` wires the navigation — check it
before assuming the exact count/order.)

---

## 3. Git / build state

*(verify before trusting — numbers move)*

| Item | Value |
| --- | --- |
| Local path | `/home/xiaonan/Easytier/easytier_flutter` |
| GitHub | `git@github.com:Xiaonan-520/easytier_flutter.git` (**public**) |
| Branch | `main` |
| Upstream reference clone | `/home/xiaonan/Easytier/easytier-upstream` (`main` @ `ff3921c`, which is what the bundled `.so` was built from) |
| Tests | 33 (`test/bridge_test.dart` 9, `config_exporter_test.dart` 5, `config_importer_test.dart` 16, `widget_test.dart` smoke) |
| License | LGPL-3.0 (matches upstream; see `LICENSE-NOTICES.md`) |

### Build environment — important

Use the standard Android/Flutter toolchain, but note the project-local caches:

```bash
export GRADLE_USER_HOME=/home/xiaonan/Easytier/.gradle
export ANDROID_USER_HOME=/home/xiaonan/.android
export ANDROID_SDK_ROOT=/opt/android-sdk
export PUB_CACHE=/home/xiaonan/Easytier/.home/.pub-cache
export PATH=/home/xiaonan/Easytier/.home/.cargo/bin:$PATH
```

**Do NOT export `HOME`** — gradle's debug signing reads
`$HOME/.android/debug.keystore`, so overriding `HOME` breaks debug builds.
**Do NOT set `http_proxy` / `https_proxy`** (the old proxy is dead; mirrors are
reached directly).

```bash
flutter pub get
flutter analyze          # must be clean
flutter test             # 33 passing
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

The bundled native library is **arm64-v8a only**.

### Device used for verification

Huawei **YAL-AL10**, Android 10, arm64-v8a, serial `ERLDU19920013465`
(an older HMA-AL00 was used in earlier sessions). The official EasyTier app is
also installed on it for interop testing.

### Debugging notes learned the hard way

- **EMUI suppresses the app's Kotlin `Log.i/e` in logcat** (only the Rust JNI
  logs and system logs get through). Use the file log instead:
  `getExternalFilesDir(null)/vpn_dbg.log`, read with
  `adb shell run-as <pkg> cat files/vpn_dbg.log`.
- Gboard pinyin can scramble `adb shell input text`; long text entry needs a
  human.
- `dbg()` logging in `EasyTierVpnService` is intentional — do not remove it as
  "noise".

---

## 4. Known issues / traps

1. **Static vs DHCP on this network.** DHCP needs ~55–60 s+ for OSPF
   convergence, so static IP is the recommended profile. `_withPrefix()` appends
   `/24` in Dart, because `VpnService` requires CIDR — a bare IP was rejected by
   Kotlin's `require()` and caused a 4 ms `establish()` failure.
2. **`instance_name` vs `inst_name`.** serde ignores `inst_name`; the TOML field
   must be `instance_name`. Getting this wrong registers the instance as
   `"default"` and makes `setTunFd` fail with "instance not found". The app now
   always uses the fixed instance name `easytier_flutter_default`.
3. **fd ownership.** The core uses `close_fd_on_drop(false)`, so `detachFd()`
   leaks; ownership must stay with the `ParcelFileDescriptor` from `establish()`.
4. **Teardown on EMUI 10.** `stopService()` alone never fires `onDestroy`, which
   leaked TUN / VPN network / notification. `stopNow()` must run synchronously
   before `stopService()`.
5. **BIND_VPN_SERVICE.** The manifest must declare
   `android:permission="android.permission.BIND_VPN_SERVICE"`, otherwise
   `establish()` always throws a SecurityException (this produced a "Connected"
   UI with no TUN in an early session).
6. `AppBgModeMgr fgService start→stop` with a tiny runningTime is a real failure
   signal for background-service starts on EMUI.
7. Keep `EasyTierJNI.kt` byte-compatible with the bundled `.so`; if you rebuild
   the `.so` from a different upstream commit, re-copy the binding and update
   `docs/integration.md`.

---

## 5. TODO / not done

1. **Quick Settings Tile** (not started). Design intent: a `TileService` reads
   the native `EasyTierVpnService.isRunning` as the single source of truth;
   OFF→ON hands off to `EasyTierService.connect(currentProfile)`. **Unverified
   risk**: EMUI restricts background service starts (`AppBgModeMgr`), which is
   fine while an Activity is foreground but must be tested for the Tile path.
2. Test-imported profile `"official"` may still exist on the device from import
   testing — harmless, delete at will.
3. No iOS / desktop targets; Android only.

---

## 6. Doing risky work safely

- The VPN internals are proven working — **do not touch them without a real
  device test**. A change to `EasyTierVpnService.kt` or the fd lifecycle can
  silently regress connect/disconnect.
- Never fake data. If a counter is unavailable, render nothing / an em dash
  rather than a plausible-looking number.
- Before every commit: `flutter analyze` + `flutter test` (+ build if the change
  is non-trivial), then a device check.
- The repository has **no secrets**; the network secret lives only in the
  device's `shared_preferences` and in profiles the user creates. Never commit
  `xiaonan@…`-style secrets or any real network secret; grep before committing.

---

## 7. Arch reinstall — how to resume

```bash
git clone git@github.com:Xiaonan-520/easytier_flutter.git
cd easytier_flutter
cat README.md && cat HANDOFF.md
flutter pub get && flutter analyze && flutter test
```

Nothing else is required from GitHub: no secret, key or database is needed to
build. Optional local conveniences that are **not** in the repo (recreate them if
you want them): the upstream analysis clone (`easytier-upstream/`, gitignored),
the project-local Gradle/Pub caches, and an emulator/device. The app's runtime
data (profiles, network secret) lives only on the phone.

To continue development, the most useful first steps are:
1. read this file + `README.md`,
2. `git log --oneline -20` to see the recent feature/checkpoint history,
3. run `flutter analyze && flutter test` to confirm a green baseline,
4. start with the Quick Settings Tile (item 5.1), verifying on a real device.
