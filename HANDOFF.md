# HANDOFF — EasyTier Flutter (Android)

> Written for a **new agent with no prior chat context**. Everything below comes
> from the current code, the git history, or live tests on a real device.
> Facts and unverified claims are separated; anything untested says so.
>
> Read `README.md` first, then this file.
>
> **Last verified:** 2026-10-17 on the Arch machine at
> `/home/xiaonan/Workspace/easytier_flutter` — `flutter analyze` clean,
> 33 tests passing, `flutter build apk --debug` succeeds. No device was
> attached during that check; the last device verification predates it.

---

## 0. TL;DR

- Third-party (non-official) **EasyTier mesh-VPN client for Android**, built with
  Flutter + Material 3, package `io.github.xiaonan520.easytier_flutter`, version
  `0.2.0+2`.
- It does **not** reimplement networking: it embeds the official
  `libeasytier_android_jni.so` and drives it over a MethodChannel, with
  Android's `VpnService` supplying the TUN interface.
- Feature-complete for daily use and verified on a real device: connect /
  disconnect, real traffic stats, peer list with P2P-vs-relay detection,
  multi-profile management, official TOML import **and** export, theme presets,
  foreground service + notification, **Quick Settings tile**, background-running
  guidance.
- 33 tests pass; `flutter analyze` is clean; the debug APK builds.
- CI (`.github/workflows/release.yml`) builds the native lib for three ABIs and
  publishes split-ABI APKs on tag push. Its build command was repaired on
  2026-10-17 but has not yet run on GitHub Actions — see §5.2.

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
    ├─ EasyTierTileService.kt  (QS tile: intent launcher + broadcast aggregator)
    ├─ VpnTileSupport.kt       (TileRuntime phase + TileBootstrapper snapshot)
    ├─ NotificationHelper.kt   (notification content for both start paths)
    └─ com/easytier/jni/
         ├─ EasyTierJNI.kt          (official binding, copied verbatim)
         └─ EasyTierVpnService.kt   (VpnService: establish() → setTunFd)
    │
Rust core  libeasytier_android_jni.so → easytier-ffi → easytier-core
```

| Component | File | Responsibility |
| --- | --- | --- |
| `RootScaffold` | `lib/app/app.dart` | owns the single `EasyTierService`, bottom navigation, tab jumps, `reconcileWithNative()` on start |
| `EasyTierService` | `lib/core/services/easytier_service.dart` | `CoreState{idle,starting,running,stopping,error}`; connect = parseConfig → runNetworkInstance → wait for virtual IP → prepare/start VPN; 3 s status poll; traffic sampling; tile-snapshot lifecycle |
| `EasyTierBridge` | `lib/native/easytier_bridge.dart` | MethodChannel calls; tolerant JSON parsing (prost serialises `u64` counters as **strings**, IPs as **u32 big-endian**); tile snapshot + `tileRuntimeState` |
| `EasyTierVpnService` | `android/app/src/main/kotlin/com/easytier/jni/EasyTierVpnService.kt` | `establish()`, keeps the TUN **fd ownership on the Java side** (the core uses `close_fd_on_drop(false)`), `stopNow()` for synchronous teardown, foreground notification, `ACTION_TILE_START` cold start, package-internal STARTED/STOPPED broadcasts, `dbg()` file logging |
| `EasyTierTileService` | `android/.../io/github/xiaonan520/easytier_flutter/EasyTierTileService.kt` | QS tile; decides from `Tile.getState`; listens to the VpnService broadcasts while visible; falls back to opening the app when no snapshot or no VPN consent |
| `TileRuntime` | `android/.../VpnTileSupport.kt` | sticky `Phase{IDLE,STARTING,RUNNING,STOPPING,ERROR}` hint; truth re-derived from `EasyTierVpnService.isRunning`; 150 s STARTING backstop |
| `TileBootstrapper` | `android/.../VpnTileSupport.kt` | Dart-rendered TOML snapshot in `FlutterSharedPreferences` (`flutter.tile_snapshot_v1`); lets the tile cold-start with **no Flutter engine** |
| `EasyTierJNI` | `android/app/src/main/kotlin/com/easytier/jni/EasyTierJNI.kt` | upstream binding — **must stay in sync with the bundled `.so`** |
| Storage | `lib/core/storage/*.dart` | `ProfileStore` (profiles), `ConfigStore` (legacy single config), `ThemeStore` (theme + mode) — all `shared_preferences` |

---

## 2. Features (implemented; device-verified unless noted)

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
- **Quick Settings tile** — `EasyTier VPN`, turns the VPN on/off from the shade.
  ON cold-starts the core from the saved snapshot (no Flutter engine); OFF tears
  down synchronously and frees the core. Missing snapshot or missing VPN consent
  opens the app instead of bypassing consent. Long-press → app settings.
- **Background-running guidance** (Settings) — vendor startup-manager jump with
  fallbacks plus the standard battery-optimization exemption; status readback is
  real for battery optimization and reported as *Unknown* where Android offers no
  readback.
- **Settings**: appearance, background running, diagnostics (core status, logs),
  about (GitHub link).

### UI tabs

| Tab | Contents |
| --- | --- |
| Home | connect/disconnect card, state, node IP, traffic card |
| Networks | profile list, import entry, export entry, full editor |
| Peers | peer list with latency / type, detail sheet with per-peer traffic |
| Settings | appearance, background running, diagnostics, about |

`app.dart` wires exactly these four `NavigationDestination`s.

### Quick Settings tile — how it works (non-obvious)

This is the part most likely to be broken by a careless change:

1. **Tap decision uses `qsTile.state`**, never an in-process flag. A second tap
   during a slow DHCP start must not flip into a stop.
2. **Colour** comes from `ACTION_VPN_STARTED` / `ACTION_VPN_STOPPED` broadcasts
   the VpnService sends (package-internal, registered only while listening).
   `requestListeningState` is not honoured by HarmonyOS 4, so it is not relied on.
3. **Truth** is calibrated once per listening window from
   `EasyTierVpnService.isRunning`.
4. **START** → `startForegroundService(ACTION_TILE_START)`; the service goes
   foreground *first* (FGS start exemption), broadcasts STARTED, then a thread
   runs `parseConfig → runNetworkInstance → wait for virtual IP → attach TUN`.
   A repeat TILE_START while running/starting re-broadcasts STARTED (idempotent).
5. **STOP** → `stopNow()` (synchronous; EMUI never fires `onDestroy` from
   `stopService()` alone) → `stopService()` → background thread calls
   `EasyTierJNI.deleteNetworkInstance`.
6. **Snapshot** (`TileBootstrapper`) is written by Dart after a verified-good
   in-app connect and on profile CRUD while idle. It is **deliberately kept**
   after an in-app disconnect so the tile can start that profile again.
7. **App-start reconciliation**: `EasyTierService.reconcileWithNative()` adopts a
   tile-initiated `running` / `starting` / `error` phase so the UI does not show
   "idle" while the TUN is actually up.

---

## 3. Git / build state

*(verify before trusting — numbers move)*

| Item | Value |
| --- | --- |
| Local path | `/home/xiaonan/Workspace/easytier_flutter` (the older `/home/xiaonan/Easytier/easytier_flutter` is gone) |
| GitHub | `git@github.com:Xiaonan-520/easytier_flutter.git` (**public**) |
| Remote used locally | `https://v6.gh-proxy.org/https://github.com/Xiaonan-520/easytier_flutter` |
| Branch | `main` |
| Version | `0.2.0+2` (`pubspec.yaml`) |
| Tests | 33 (`bridge_test.dart` 9, `config_exporter_test.dart` 5, `config_importer_test.dart` 16, `widget_test.dart` 3) |
| License | LGPL-3.0 (matches upstream; see `LICENSE-NOTICES.md`) |
| Platforms | Android only — no `ios/`, `linux/`, `macos/`, `windows/`, `web/` |

### Build environment — actual current paths

The previously documented project-local caches do **not** exist on this machine.
What works today:

```bash
export PATH=/home/xiaonan/dev/flutter/bin:$PATH
export ANDROID_SDK_ROOT=/home/xiaonan/dev/android-sdk
export ANDROID_HOME=/home/xiaonan/dev/android-sdk
export JAVA_HOME=/home/xiaonan/dev/jdk/jdk-17.0.20.1+1
# optional: adb is /usr/sbin/adb (android-tools 37.0.0)
```

| Tool | Version / path |
| --- | --- |
| Flutter | 3.47.5 stable, revision `6a19cca564`, at `/home/xiaonan/dev/flutter` |
| Dart | 3.13.4 (pubspec requires `^3.13.4`) |
| Android SDK | `/home/xiaonan/dev/android-sdk` (platforms 35/36, build-tools 35.0.0/36.0.0) |
| NDK | 28.2.13676358 |
| JDK | `/home/xiaonan/dev/jdk/jdk-17.0.20.1+1` |
| Gradle cache | default `$HOME/.gradle` — nothing special needed |

`android/local.properties` already points at the right SDK/Flutter.

**Do NOT export `HOME`** — gradle's debug signing reads
`$HOME/.android/debug.keystore`, so overriding `HOME` breaks debug builds.
**Do NOT set `http_proxy` / `https_proxy`.**

```bash
flutter pub get
flutter analyze          # must be clean
flutter test             # 33 passing
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**Careful:** running `flutter analyze` / `flutter test` / `flutter pub get` on this
machine rewrites `pubspec.lock` (the committed lock points at the
`pub.flutter-io.cn` mirror; with no `PUB_HOSTED_URL` set the resolver uses
`pub.dev` and also bumps `android_file_picker` 2.0.0 → 2.1.1). That is unrelated
114-line churn — `git checkout -- pubspec.lock` unless you intend to re-pin. To
keep it stable, export the same `PUB_HOSTED_URL` the lock was made with
(verify the mirror is reachable before relying on it).

### Native ABI

- The repository contains **only** `android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so`.
- A local arm64-only build therefore installs on arm64 phones/emulators only.
- CI builds arm64-v8a, armeabi-v7a and x86_64 and produces split-ABI APKs.

### Device used for verification

Huawei **YAL-AL10**, Android 10, arm64-v8a, serial `ERLDU19920013465`
(an older HMA-AL00 was used in earlier sessions). The official EasyTier app is
also installed on it for interop testing. No device was attached during the
2026-10-17 baseline check.

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

1. **Static vs DHCP on this network.** DHCP needs ~55–90 s for OSPF
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
8. **Tile and app share one process.** `TileRuntime` / `TileBootstrapper` are
   plain singletons precisely because the core runs in-process. Do not move the
   core into a separate process without redesigning the tile path.
9. **Tile START timeout is 150 s** (DHCP/OSPF headroom) in both
   `TileRuntime.START_TIMEOUT_MS` and `EasyTierVpnService.IP_WAIT_MS`. Keep them
   in sync with the Dart-side wait.

---

## 5. TODO / open items

1. **Add a CI job for `flutter analyze` / `flutter test`.** Only the tag-driven
   release workflow exists; there is no push/PR validation.
2. **Confirm the release workflow actually runs.** The APK build command was
   fixed on 2026-10-17 (it was split across two shell lines, so the step failed
   with `--target-platform: not found`; a second unsplit build now produces the
   universal APK, and artifact names are derived from `pubspec.yaml`). It has
   **not** been exercised on GitHub Actions yet — trigger a `workflow_dispatch`
   run and check both jobs.
3. Test-imported profile `"official"` may still exist on the device from import
   testing — harmless, delete at will.
4. No iOS / desktop targets; Android only.
5. The bundled `.so` in the repo is arm64-only even though CI produces three
   ABIs — decide whether to commit all three or keep them CI-only.
6. Neither README nor the in-app UI mentions the Quick Settings tile. Adding it
   to the README feature list (and maybe to the Settings "Background running"
   card) would help discoverability.

---

## 6. Doing risky work safely

- The VPN internals are proven working — **do not touch them without a real
  device test**. A change to `EasyTierVpnService.kt`, `EasyTierTileService.kt`,
  or the fd lifecycle can silently regress connect/disconnect.
- Never fake data. If a counter is unavailable, render nothing / an em dash
  rather than a plausible-looking number.
- The tile's tap decision must keep reading `qsTile.state`; deriving it from an
  in-process flag reintroduces the double-tap stop bug.
- Before every commit: `flutter analyze` + `flutter test` (+ build if the change
  is non-trivial), then a device check — **including one tile ON→OFF cycle** if
  you touched anything under `android/`.
- The repository has **no secrets**; the network secret lives only in the
  device's `shared_preferences` and in profiles the user creates. The tile
  snapshot also contains the rendered TOML (i.e. the secret) in
  `FlutterSharedPreferences` on-device — never log or commit it. Never commit
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
you want them): the upstream analysis clone (`easytier-upstream/`, gitignored)
and an emulator/device. The app's runtime data (profiles, network secret) lives
only on the phone.

To continue development, the most useful first steps are:
1. read this file + `README.md`,
2. `git log --oneline -20` to see the recent feature/checkpoint history,
3. run `flutter analyze && flutter test` to confirm a green baseline,
4. add an analyze/test workflow (§5.1) and confirm the release workflow runs
   end-to-end (§5.2),
5. then any feature work — always verifying on a real device.
