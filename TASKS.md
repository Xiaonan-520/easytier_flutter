# EasyTier Android Client Tasks

> ## ✅ Phase 4 COMPLETE (2026-09-30, session 4)
> All live-device tests passed on Mate 20 / Android 10:
>
> | Item | Result |
> |---|---|
> | VPN/tun established | PASS — tun0 10.126.126.2/24, MTU 1300, ConnectivityService VPN CONNECTED, route 10.126.126.0/24 only (no default-route hijack), self excluded via addDisallowedApplication |
> | In-network traffic | PASS — ping 10.126.126.1 (homeserver) 0% loss, RTT 4-16ms |
> | Peers page | PASS — 3 nodes with correct IP/latency(7,35,37ms)/cost; u32 big-endian IP parsing verified live |
> | Dashboard "default" | FIXED — root cause: TOML key `inst_name` is ignored by serde (field is `instance_name`); instance registered as "default" and setTunFd crashed with "instance not found" (the 19:13 Binder crash). Now shows easytier_flutter_default |
> | Disconnect→Connect ×3 | PASS — each cycle: fresh tun0, ping OK, after disconnect tun/fd/VPN-network/ServiceRecord all = 0, no FATAL |
> | Official App (Test B) | PASS — both directions: force-stop ours → official connects (tun0, ping OK); force-stop official → ours connects. No residue either way |
>
> **New bugs fixed this session (commits d9a6c3a, d785869, e96d442):**
> 1. Manifest VpnService lacked `android:permission=BIND_VPN_SERVICE` → establish() always threw SecurityException; the "Connected" seen in session 3 was core-only, no TUN.
> 2. TOML `inst_name` ignored → instance name "default" → setTunFd "instance not found" FATAL (also the 19:13 crash & "default" dashboard).
> 3. fd leak: detachFd() orphaned the fd (core uses close_fd_on_drop(false)); fixed by keeping establish() PFD ownership.
> 4. stopService() alone never fired onDestroy on EMUI 10 → Disconnect leaked TUN/VPN-network/notification; fixed with official-plugin-style sync stopNow() before stopService.
>
> Phase 5 (UI polish), 7 (stability), 8 (GitHub) can start next; no known blockers.

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
- [x] Test on physical Android device (2026-09-30: connect, TUN, ping, peers all verified live)

## Phase 4 - Configuration
- [x] Network name
- [x] Network secret
- [x] Peer configuration
- [x] IPv4 / IPv6 configuration (static IP; DHCP default)
- [ ] Relay / STUN configuration if supported
- [x] Save configuration locally
- [x] Load configuration on startup

## Phase 5 - Material 3 UI
- [x] Dashboard (state card + network info + working quick links to Peers/Network tabs)
- [x] Connection status (idle/starting/running/stopping/error with spinner + error text)
- [x] Network information (instance name, virtual IP/prefix)
- [x] Peer list (hostname, virtual IP, latency ms, cost; verified against live network)
- [x] Configuration page (name/secret/peers/DHCP/hostname/latency-first, persisted)
- [x] Logs/debug page (state transitions + status snapshots, clear button, newest-first)
- [x] Settings page (VPN permission hint, About link)
- [x] About page (version, core version corrected to main @ ff3921c, upstream, disclaimer)

## Phase 6 - Android integration
- [ ] VPN service integration if required
- [ ] Android permissions
- [ ] Foreground service if required
- [ ] Background behavior
- [ ] App lifecycle handling
- [ ] Physical-device testing

## Phase 7 - Stability
- [x] Error handling (no-network connect → clear 30s timeout error, state returns to Error, UI recoverable)
- [x] Reconnect behavior (after Error state, Connect retries successfully in-place; verified after wifi restore)
- [x] App restart behavior (force-stop → relaunch → config restored from prefs → one-tap reconnect works)
- [x] Configuration persistence (name/secret/peers survive restarts & process kills; secret stays on-device)
- [x] Native resource cleanup (3× Disconnect cycles: tun fd, VPN network, ServiceRecord all released = 0)
- [x] Memory/resource checks (RSS ~385MB incl. 33MB native heap, 45 threads, stable across 6+ connect cycles; no leaks observed)

## Phase 8 - Release
- [ ] Release build
- [ ] APK installation test
- [ ] Git cleanup
- [ ] README
- [ ] LICENSE notices
- [ ] Git commit
- [ ] GitHub repository creation
- [ ] GitHub push
