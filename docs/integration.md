# EasyTier Native Integration Architecture

Upstream: https://github.com/EasyTier/EasyTier — main branch @ ff3921c
(post-v2.6.4; the packaged .so was built from this commit). The Kotlin binding
`EasyTierJNI.kt` MUST match the .so: 12 JNI methods incl. `deleteNetworkInstance`
and `collectNetworkInfos(maxLength)`. Do not swap in the older v2.6.4 (6-method)
binding — mismatched signatures cause JNI undefined behavior.

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
| TOML config keys | `easytier-core/src/config/toml.rs` Config struct | inst_name, instance_id, hostname, dhcp, ipv4, listeners; `[network_identity]` (network_name, network_secret); `[[peer]]` (uri); `[flags]` (latency_first, bind_device, dev_name). NOTE: top-level `network`/`network_secret`/`peers` do NOT exist in the struct and are silently ignored by serde |
| Running-state schema | `easytier-proto/proto/api_manage.proto` + `api_instance.proto` | NetworkInstanceRunningInfoMap JSON: my_node_info, routes[], peers[], peer_route_pairs[] (latency in Route.path_latency) |

## JNI API (main @ ff3921c) — all return 0 / -1, error text via getLastError()

- `parseConfig(config: String)` — validate TOML only
- `runNetworkInstance(config: String)` — start instance (inst_name unique per FFI cache)
- `retainNetworkInstance(names: Array<String>?)` — keep listed, stop others (null = stop all)
- `deleteNetworkInstance(name: String)` — stop one instance, no-op if absent
- `collectNetworkInfos(maxLength: Int): String?` — JSON `NetworkInstanceRunningInfoMap`
- `listInstances(maxLength: Int): String?` — JSON {name: instance_id}
- `callJsonRpc(service, method, domain?, payload)` — raw protobuf-JSON RPC
- `setTunFd(instanceName: String, fd: Int)` — attach Android TUN fd
- `getLastError(): String?`

## Build of the native libs

`cargo ndk -t arm64-v8a build --release` inside `easytier-android-jni`
(workspace builds easytier-ffi too). Device ABI: arm64-v8a (Mate 20 / Android 10).
Output `.so`s go to `android/app/src/main/jniLibs/arm64-v8a/`.
NDK 28.2.13676358, cargo-ndk 4.1.2, rustc 1.95 (upstream toolchain pin).
