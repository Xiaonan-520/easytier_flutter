# EasyTier Flutter (Android)

第三方 EasyTier Mesh VPN 的 Flutter + Material 3 Android 客户端(**非官方**)。
底层复用 EasyTier 官方 JNI 库(`easytier-android-jni` → `easytier-ffi` → `easytier-core`),不重新实现网络协议。

- 应用包名: `io.github.xiaonan520.easytier_flutter`
- GitHub 账号: Xiaonan-520 (gh CLI 已登录, ssh 协议)
- 目标设备: Huawei HMA-AL00 (Mate 20), Android 10 (API 29), **arm64-v8a**, 序列号 HJS0219122011897

---

## 📋 HANDOFF 报告(2026-09-26 会话 3 结束时更新)

### 已完成
- **BUG#1~#4 全部修复**(commit 65bb1c6 + 949780c):
  1. 恢复 main 版 EasyTierJNI.kt(12 个 JNI 方法,与 .so 匹配)
  2. toToml() 改为官方 Config 结构:`[network_identity]` / `[[peer]]` / listeners / `[flags]`(latency_first, bind_device, dev_name)
  3. prost JSON 解析:Ipv4Addr.addr 为大端 u32 数字;latency 用 Route.path_latency;parseStatusJson 可测试化
  4. VPN 时序:connect() 先轮询 collectNetworkInfos 等真实虚拟 IP(30s 超时),再 prepareVpn/startVpn;路由由分配到的地址推导(实测网段是 10.126.126.0/24,不是默认 10.144.144.0/24!)
- 修复过程中新发现并修复:MethodChannel 返回 bool 的类型转换崩溃(prepareVpn/isVpnRunning)、jsonDecode const map 强转崩溃、network_length 缺失导致 startVpn 无前缀。analyze ✓ test(9) ✓ build ✓,均通过。
- 真机:APK 已安装;**密钥已由用户通过 UI 输入**(存手机 shared_preferences,从未写入任何文件);Connect 后核心成功入网,Dashboard 显示 **Connected,Node IP: 10.126.126.2/24**。

### 未完成 / 下一步(Phase 4 收尾)
- 设备在最后验证前被拔出,**TUN 接口(ip addr 看 tun0)与网内 ping 未验证**;19:13:09 logcat 里有一条 EasyTierVpnService Binder 报错待复查。
- 网络名显示 "default"(map key 是实例名?待查 —— 我们的实例名是 easytier_flutter_default,collectStatus 显示的是 entry.key,需确认 native 侧实例命名)。
- 剩余测试:Peers 页节点/延迟、ping 网内节点、Disconnect 生命周期、force-stop 重启重连、Test B(官方 App 恢复)。
- 测试注意:Gboard 拼音会吞 adb input text(先切英文);用户可能同时在用手机,勿盲点坐标。

### 安全
- network_secret 仅存在于手机 shared_preferences;仓库 grep 无密钥(已知片段确认)。

---

## ⚠️ HANDOFF — 交接给下一个 Agent 的当前状态(2026-09-26)

### 项目位置
- Flutter 项目: `/home/xiaonan/Easytier/easytier_flutter` (本目录)
- EasyTier 官方仓库克隆: `/home/xiaonan/Easytier/easytier-upstream` (当前 checkout 在 main @ ff3921c, 已 fetch 全部 tag)
- 编译产物日志: `/home/xiaonan/Easytier/easytier-upstream/logs/`
- Git: 本目录已 `git init`, 分支 `main`, 共 3 个 commit, **尚未创建 GitHub remote**

### 环境须知(极其重要, 不做这些 Flutter/Gradle 全部失败)
宿主机 `/home` 分区**只读**! 只有 `/home/xiaonan/Easytier` 可写。必须用以下环境变量:

```bash
export HOME=/home/xiaonan/Easytier/.home
export GRADLE_USER_HOME=/home/xiaonan/Easytier/.gradle
export XDG_DATA_HOME=/home/xiaonan/Easytier/.home/.local/share
export ANDROID_USER_HOME=/home/xiaonan/Easytier/.home/.android
export ANDROID_NDK_ROOT=/opt/android-sdk/ndk/28.2.13676358
export PATH=/home/xiaonan/Easytier/.home/.cargo/bin:$PATH
# 网络代理(用户要求直接用, 下载快很多):
export http_proxy=http://192.168.10.210:7890 https_proxy=http://192.168.10.210:7890
```

其他环境事实:
- Flutter 3.47.5 stable (Dart 3.13.4), SDK 在 `/opt/flutter`, 也有 unionfs 缓存于 `~/.cache/flutter_sdk`
- `flutter` 命令实际是 `/usr/sbin/flutter` 包装脚本
- Android SDK: `/opt/android-sdk`, platform 36, NDK 28.2.13676358
- Rust: rustup 装在 `$HOME/.cargo/bin` (1.98.1 default + 1.95 toolchain), cargo-ndk 4.1.2 已复制到该路径
- Gradle 代理配置在 `$GRADLE_USER_HOME/gradle.properties`; 项目内 `android/build.gradle.kts` 和 `android/settings.gradle.kts` 已加 aliyun 镜像
- 系统原生 rustc 1.98.1 在 /usr (无 aarch64 target), **必须用 rustup 版**, 即 PATH 里的 `$HOME/.cargo/bin` 优先
- rustup 已安装 target `aarch64-linux-android`

### 已完成的 Phase
- **Phase 0 环境**: 完成
- **Phase 1 Flutter 基础**: 完成 (Material 3 + NavigationBar 5 tab + IndexedStack + widget test)
- **Phase 2 官方研究**: 完成, 见 `docs/integration.md`
- **Phase 3 Native 集成**: 代码完成 (详见下方"架构"), APK 已构建、已安装真机、已启动验证
- **Phase 4 真机连接测试**: **进行中 — 卡在最后一轮代码审查, 尚未真正执行连接测试**

### 架构(已实现)
```
Flutter (Dart)
  └─ MethodChannel 'easytier_flutter/core'   (lib/native/easytier_bridge.dart)
       └─ MainActivity.kt (MethodChannel handler + VPN permission flow)
            ├─ com.easytier.jni.EasyTierJNI  (官方 Kotlin 绑定, 包名保持 com.easytier.jni)
            │    └─ jniLibs/arm64-v8a/libeasytier_android_jni.so (16.4MB, cargo-ndk release 编译)
            └─ com.easytier.jni.EasyTierVpnService (VpnService: establish TUN → setTunFd 给核心)
```

关键文件:
- `lib/native/easytier_bridge.dart` — MethodChannel + EasyTierError + PeerRow/NodeStatus 模型 + collectStatus() JSON 解析
- `lib/core/services/easytier_service.dart` — 状态机 idle/starting/running/stopping/error + 3 秒轮询 + connect/disconnect 编排
- `lib/core/models/network_config.dart` — 配置模型 + toToml() 渲染官方 TOML
- `lib/core/storage/config_store.dart` — shared_preferences 本地持久化
- `lib/features/{dashboard,peers,network,logs,settings}/` — Material 3 UI
- `android/app/src/main/kotlin/io/github/xiaonan520/easytier_flutter/MainActivity.kt`
- `android/app/src/main/kotlin/com/easytier/jni/EasyTierVpnService.kt`
- `android/app/src/main/kotlin/com/easytier/jni/EasyTierJNI.kt` — ⚠️ 见下方 BUG#1
- `android/app/src/main/jniLibs/arm64-v8a/libeasytier_android_jni.so`

### 🚨 已确认但尚未修复的 BUG (Phase 4 阻塞项, 下一 Agent 的首要任务)

**BUG#1 — Kotlin 绑定与 .so 版本不匹配(致命)**
`libeasytier_android_jni.so` 是从 **main 分支 @ ff3921c** 编译的(12 个 JNI 方法: setTunFd, parseConfig, runNetworkInstance, retainNetworkInstance, deleteNetworkInstance, collectNetworkInfos(maxLength), listInstances, callJsonRpc, getLastError, startConfigServerClient, stopConfigServerClient, isConfigServerClientConnected — 已用 `nm -D` 验证全部导出)。
但最后一步误把 **v2.6.4 版**的 `EasyTierJNI.kt`(只有 6 个方法, 且 `collectNetworkInfos()` 无参)覆盖了 main 版 Kotlin 文件。
调用无参 `collectNetworkInfos()` 会因 JNI 签名不匹配产生未定义行为(垃圾 maxLength → vec 分配 OOM/崩溃)。
**修复(二选一):**
- 方案 A(推荐, 快): 恢复 main 版 Kotlin 文件: `cd /home/xiaonan/Easytier/easytier-upstream && git show HEAD:easytier-contrib/easytier-android-jni/kotlin/com/easytier/jni/EasyTierJNI.kt > /home/xiaonan/Easytier/easytier_flutter/android/app/src/main/kotlin/com/easytier/jni/EasyTierJNI.kt`
- 方案 B(慢, 但符合"锁定稳定版"策略): `git -C easytier-upstream checkout v2.6.4` 后重新 `cargo ndk -t arm64-v8a build --release`(约 20-40 分钟, 多数 crate 已缓存), 同时保留 v2.6.4 Kotlin 文件; 若选 B, `collectNetworkInfos()` 无参, MainActivity 里要改成无参调用, 且 v2.6.4 没有 deleteNetworkInstance(用 retainNetworkInstance(null) 停全部)。
当前代码与 main 版 .so 对齐是既定事实, 方案 A 最快。文档 docs/integration.md 声称 pin v2.6.4, 若选 A 需更正文档为 "main @ ff3921c (v2.6.4 之后)"。

**BUG#2 — TOML 配置格式错误(致命, 静默失败)**
`lib/core/models/network_config.dart` 的 `toToml()` 用了旧版顶层键: `network = "..."`, `network_secret = "..."`, `peers = [...]`。
v2.6.4/main 的 `TomlConfigLoader` 的 Config 结构体没有这些顶层字段, serde **静默忽略未知键**, 结果实例启动了但没加入任何网络!
正确格式(依据 v2.6.4 `easytier/src/common/config.rs` Config 结构 + 官方测试用例):
```toml
inst_name = "easytier_flutter_default"     # 顶层, instance_name 也可
instance_id = "9065a0c0-6664-4492-af46-bc48494b227b"   # 可选, UUID
hostname = "xiaonan-phone"
dhcp = true                                # 顶层
# ipv4 = "10.144.144.X/24"                 # 仅 DHCP=false 时
listeners = ["tcp://0.0.0.0:11010", "udp://0.0.0.0:11010", "wg://0.0.0.0:11011"]

[network_identity]                          # ← 网络名/密钥放这里!
network_name = "xiaonan-home-ai"
network_secret = "..."                      # 运行时由用户输入, 绝不入库

[[peer]]                                    # ← 每个 peer 一个 [[peer]] 段
uri = "tcp://183.230.36.171:11010"

[flags]
latency_first = true
bind_device = false
dev_name = "easytier0"
```
( listeners 已确认: 官方 easytier-gui 移动端默认就带 tcp+udp 0.0.0.0:11010 和 wg 0.0.0.0:11011, 且 listener 绑定失败非致命, 可安全复制。`[[peer]]` 的 PeerConfig 字段是 `uri`; 顶层 peer 数组字段名是 `peer` 不是 `peers`!)

**BUG#3 — 状态 JSON 字段解析错误**
`collectNetworkInfos` 返回 JSON(serde + preserve_proto_field_names, snake_case), 结构(prost u32 序列化为 **JSON 数字**, u64 序列化为 **字符串**):
```json
{"map": {"<inst_name>": {
  "dev_name": "easytier0",
  "my_node_info": {"virtual_ipv4": {"address": {"addr": <u32大端数字>}, "network_length": 24}, "hostname": "...", "version": "...", "peer_id": N, "ips": {...}},
  "routes": [{"peer_id": N, "ipv4_addr": {"address": {"addr": <u32>}, "network_length": 24}, "hostname": "...", "cost": 1, "path_latency": <ms int>, "version": "...", "proxy_cidrs": []}],
  "peers": [{"peer_id": N, "conns": [{"conn_id": "...", "stats": {"latency_us": "<字符串µs>"}, ...}], "default_conn_id": {...}}],
  "peer_route_pairs": [{"route": {...}, "peer": {...}}],
  "running": true, "error_msg": null }}}
```
`easytier_bridge.dart` 里 PeerRow.fromRoute 把 `ipv4_addr.addr` 当字符串 — 错, 是 u32 大端数字。需要转换: octets = [(v>>24)&255, (v>>16)&255, (v>>8)&255, v&255]。官方 GUI 的延迟取 `peer.conns[].stats.latency_us`(µs 字符串, 除以 1000 得 ms), route 里也有 `path_latency`(ms 整数)可直接用。

**BUG#4 — VPN 启动时序错误(致命)**
`easytier_service.dart` 当前: runNetworkInstance → 立即 startVpn(用占位 IP "10.144.144.1/24")。
官方 GUI 流程(mobile_vpn.ts): run instance → **轮询 collectNetworkInfos 等 DHCP 分配出 my_node_info.virtual_ipv4** → 用**真实 IP** 建 VPN → TUN fd 交给 setTunFd。
DHCP 需要先有 peer 路由才分配 IP(evaluate() 里 WaitForPeers), 且 Android VpnService 的 addAddress 必须用真实分配 IP, 否则本机收发包 dst 不匹配直接丢。
**修复**: connect() 里在 runNetworkInstance 之后轮询(每 500ms~1s, 超时 ~30s)直到 virtual_ipv4 出现且 running=true, 再 startVpn(instanceName, 真实IP/真实前缀, 路由=虚拟网段)。EasyTierVpnService.kt 里硬编码的 addRoute("10.144.144.0", 24) 应改为按传入 IP 的前缀推导或由 Dart 传入。

### Phase 4 测试计划(修复 BUG 后执行)
用户参考配置(官方 App 同款): 网络 `xiaonan-home-ai`, DHCP=true, peers: `tcp://183.230.36.171:11010` + `tcp://easytier.weiai.org.cn:11010`, latency_first=true, bind_device=false, dev_name=easytier0, hostname=xiaonan-phone。
**🔒 安全: network_secret 由用户私下提供, 只允许通过 App UI 输入并存在手机本地 (shared_preferences), 严禁写入任何源码/测试/文档/Git/GitHub/日志。每次提交前用 secret 的已知片段跑 grep 确认为空。**
测试步骤: (1) 修 4 个 BUG → analyze/test/build → `adb install -r` → (2) Test A: `adb shell am force-stop com.kkrainbow.easytier`(官方 App 先停, 避免双 VPN 冲突) → App 内输入配置 Connect → VPN 授权 → logcat 观察(`adb logcat -c` 后 `adb logcat -d | grep -iE "EasyTier|VpnService|JNI|tun"`) → (3) Dashboard 应显示 Connected/虚拟IP, Peers 页有节点+延迟 → (4) `adb shell ip addr` 看 tun 接口, ping 网内其他节点 → (5) Disconnect 后确认 core 停止/通知消失 → (6) force-stop 重启 App 再连 → (7) Test B: force-stop 本 App, 官方 EasyTier 恢复正常使用。
完成条件: Connect → VPN 授权 → EasyTier running → Peer connected → Dashboard Connected → Disconnect → 资源释放 → 再次 Connect, 全链路真机可用。

### 版本/工具链记录
- EasyTier native: main @ ff3921c (若重编译则 v2.6.4 = 8428a89)
- Flutter 3.47.5 / AGP 9.1.0 / Kotlin 2.4.0 / Gradle 9.3.1 / JDK 17 / NDK 28.2 / cargo-ndk 4.1.2 / minSdk 24 / targetSdk 36 / Android 10 真机
- AndroidManifest 已含: INTERNET, ACCESS_NETWORK_STATE, FOREGROUND_SERVICE, FOREGROUND_SERVICE_SPECIAL_USE, POST_NOTIFICATIONS + specialUse FGS property

---

## 构建 / 运行
```bash
# 用上文环境变量块
cd /home/xiaonan/Easytier/easytier_flutter
flutter pub get
flutter analyze && flutter test
flutter build apk --debug
adb devices        # 确认真机
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n io.github.xiaonan520.easytier_flutter/.MainActivity
```

## 重编译 native 库(如需)
```bash
cd /home/xiaonan/Easytier/easytier-upstream
git checkout main   # 或 v2.6.4
cd easytier-contrib/easytier-android-jni
cargo ndk -t arm64-v8a build --release
cp ../../target/aarch64-linux-android/release/libeasytier_android_jni.so \
   /home/xiaonan/Easytier/easytier_flutter/android/app/src/main/jniLibs/arm64-v8a/
```

## License / 归属
- EasyTier 上游: https://github.com/EasyTier/EasyTier (native 库与 Kotlin 绑定复制自官方, 遵循上游许可证)
- 本项目是**第三方客户端**, 未获官方授权, 不得声称官方。JNICopyright 归属见 docs/integration.md。
