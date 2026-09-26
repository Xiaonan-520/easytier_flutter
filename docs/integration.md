# EasyTier Native Integration Architecture

Upstream: https://github.com/EasyTier/EasyTier — **tag v2.6.4** (commit 8428a89).
PINNED for reproducibility. JNI APIs grew from 6 (v2.6.4) to 12 (main); we start
from the stable release and re-pin deliberately later.

## Chain

```
Flutter (Dart)
  └─ MethodChannel 'easytier_flutter/core'   (lib/native/easytier_bridge.dart)
       └─ Kotlin MainActivity / CoreService   (android/app/src/main/kotlin/...)
            ├─ com.easytier.jni.EasyTierJNI   (official JNI bindings, copied verbatim)
            │    └─ libeasytier_android_jni.so  → easytier-ffi → easytier-core
            └─ EasyTierVpnService (VpnService) — TUN fd → EasyTierJNI.setTunFd()
```

## Official components reused (not reimplemented)

| Piece | Source | Role |
|---|---|---|
| `libeasytier_android_jni.so` | `easytier-contrib/easytier-android-jni` | JNI facade: parseConfig, runNetworkInstance, retainNetworkInstance, collectNetworkInfos, setTunFd, getLastError |
| `libeasytier_ffi.so` | `easytier-contrib/easytier-ffi` | C-ABI instance cache over easytier-core |
| `EasyTierJNI.kt` / `EasyTierManager.kt` | `easytier-android-jni/kotlin/com/easytier/jni` | Java-side binding class (copied, package kept `com.easytier.jni`) |
| TUN wiring pattern | `tauri-plugin-vpnservice/.../TauriVpnService.kt` + `easytier-gui/src/composables/mobile_vpn.ts` | VpnService.establish() → fd → setTunFd; foreground notification; routes from running info |
| TOML config keys | `easytier-android-jni/example_config.toml` | inst_name, network, network_secret, peers, ipv4, dhcp, listeners... |
| Running-state schema | `easytier-proto/proto/api_manage.proto` + `api_instance.proto` | NetworkInstanceRunningInfoMap JSON: my_node_info, routes[], peers[], peer_route_pairs[] (latency in Route.path_latency) |

## JNI API (v2.6.4) — all return 0 / -1, error text via getLastError()

- `parseConfig(config: String)` — validate TOML only
- `runNetworkInstance(config: String)` — start instance (inst_name unique per FFI cache)
- `retainNetworkInstance(names: Array<String>?)` — keep listed, stop others (null = stop all)
- `collectNetworkInfos(maxLength: Int): String?` — JSON `NetworkInstanceRunningInfoMap`
- `setTunFd(instanceName: String, fd: Int)` — attach Android TUN fd
- `getLastError(): String?`

## Build of the native libs

`cargo ndk -t arm64-v8a build --release` inside `easytier-android-jni`
(workspace builds easytier-ffi too). Device ABI: arm64-v8a (Mate 20 / Android 10).
Output `.so`s go to `android/app/src/main/jniLibs/arm64-v8a/`.
NDK 28.2.13676358, cargo-ndk 4.1.2, rustc 1.95 (upstream toolchain pin).
