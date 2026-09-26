# EasyTier Android Client Tasks

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
