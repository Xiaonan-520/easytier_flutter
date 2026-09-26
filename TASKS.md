# EasyTier Android Client Tasks

> ## 🚧 HANDOFF UPDATE (2026-09-26, session 2) — Phase 4 blocked on network_secret
> BUG#1–#4 all fixed (commit 65bb1c6): analyze ✓ / test ✓ (9 passed) / build ✓ / installed on device ✓.
>
> **Live test result (before device was unplugged):** Core starts and reaches the public
> server (peer_id assigned, foreign-network client sees other nodes in `xiaonan-home-ai`),
> but **no routes → DHCP stays in WaitForPeers → no virtual IP → connect() times out after
> 30 s** with "Timed out waiting for a virtual IP from the network".
> Per official `easytier-core/src/gateway/dhcp.rs` (evaluate/has_routes), DHCP only assigns
> an IP once at least one route exists; observing foreign peers without connecting provides none.
> Evidence points to **empty network_secret**: the network is secret-protected, our join with
> an empty secret authenticates but cannot establish peer connections.
>
> **Blocker (needs the user):** the network_secret must be typed into the App UI
> (Network tab → Network secret) — it must never be written to source/docs/git or handled
> by the agent. After the user enters it, re-run: Connect → expect virtual IP → VPN TUN →
> Dashboard Connected → Peers listed → ping tests → Disconnect/重启/重连 lifecycle → Test B.
>
> **Testing hazards learned:** (1) Gboard defaults to Pinyin — `adb shell input text` gets
> transliterated to CJK; switch the keyboard to English (tap globe) or clear the field
> first. (2) Don't blind-tap by coordinates while the user may be using the phone — taps
> landed in other apps (file manager) twice. (3) `adb shell am start ...` is safer than
> tapping. (4) VPN permission was already granted (no dialog appeared on Connect).

Third-party Flutter Material 3 client for [EasyTier](https://github.com/EasyTier/EasyTier).

## Phase 0 - Environment
- [x] Flutter environment check
- [x] Android SDK check
- [x] ADB device check
- [x] Java/Gradle environment check
- [x] Git/GitHub CLI check
- [x] Rust toolchain check (for later native integration)

### Environment notes
- Host `/home` partition is **read-only**; only `/home/xiaonan/Easytier` is writable.
  Flutter must run with `HOME=/home/xiaonan/Easytier/.home`, otherwise telemetry
  writes crash the tool ("Read-only file system, errno = 30").
- Flutter 3.47.5 stable (Dart 3.13.4), Android SDK 36.0.0, JDK 17.0.20 — all OK.
- Device: Huawei HMA-AL00 (Mate 20), Android 10 (API 29), **arm64-v8a**, serial HJS0219122011897.
- Rust 1.98.1 + cargo-ndk 4.1.2 + NDK 28.2.13676358 available (no rustup; system rust).
- gh CLI logged in as Xiaonan-520 (ssh protocol).
- flutter doctor warnings that do NOT block Android debug builds: missing Chrome
  (web only), multiple adb binaries in PATH, /opt/flutter read-only (tools run fine
  via the unionfs SDK cache).

## Phase 1 - Flutter foundation
- [x] Create Flutter project
- [x] Configure Material 3
- [x] Establish project architecture
- [x] Create app theme
- [x] Create navigation
- [x] Create basic Home screen
- [ ] Build debug APK
- [ ] Install APK with ADB
- [ ] Launch on physical device

## Phase 2 - EasyTier integration research
- [x] Clone official EasyTier repository
- [x] Analyze Android implementation
- [x] Analyze Rust FFI/JNI
- [x] Identify required native APIs
- [x] Determine integration strategy
- [x] Document integration architecture

## Phase 3 - Core EasyTier integration
- [x] Integrate EasyTier native core
- [x] Start EasyTier node
- [x] Stop EasyTier node
- [x] Read node status
- [x] Read peer information
- [x] Handle native errors
- [ ] Test on physical Android device  <!-- APK installed & launches; connect flow needs live network test by owner -->

## Phase 4 - Configuration
- [x] Network name
- [x] Network secret
- [x] Peer configuration
- [x] IPv4 / IPv6 configuration (static IP; DHCP default)
- [ ] Relay / STUN configuration if supported
- [x] Save configuration locally
- [x] Load configuration on startup

## Phase 5 - Material 3 UI
- [ ] Dashboard
- [ ] Connection status
- [ ] Network information
- [ ] Peer list
- [ ] Configuration page
- [ ] Logs/debug page
- [ ] Settings page
- [ ] About page

## Phase 6 - Android integration
- [ ] VPN service integration if required
- [ ] Android permissions
- [ ] Foreground service if required
- [ ] Background behavior
- [ ] App lifecycle handling
- [ ] Physical-device testing

## Phase 7 - Stability
- [ ] Error handling
- [ ] Reconnect behavior
- [ ] App restart behavior
- [ ] Configuration persistence
- [ ] Native resource cleanup
- [ ] Memory/resource checks

## Phase 8 - Release
- [ ] Release build
- [ ] APK installation test
- [ ] Git cleanup
- [ ] README
- [ ] LICENSE notices
- [ ] Git commit
- [ ] GitHub repository creation
- [ ] GitHub push
