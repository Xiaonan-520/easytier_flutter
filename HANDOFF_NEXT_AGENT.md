# HANDOFF — 下一 Agent 项目交接文档

> 写给完全没有当前聊天上下文的下一任 Agent。所有结论均来自当前代码、git 历史与 2026-09-30 的 Android 真机(Huawei HMA-AL00,Android 10,arm64-v8a,serial HJS0219122011897)实测。事实与推测分开标注,未验证的内容会明确写"未验证"。

---

## 1. Project Overview

- **项目**:EasyTier Flutter Android 客户端(第三方非官方 App),把 EasyTier Rust mesh-VPN core 通过 JNI 嵌入 Android App,用系统 VpnService 建 TUN。
- **包名**:`io.github.xiaonan520.easytier_flutter`(官方 App 是 `com.kkrainbow.easytier`,真机上装有官方 App 用于互操作测试)。
- **Upstream**:`/home/xiaonan/Easytier/easytier-upstream`,main 分支 @ `ff3921c`(core 版本号实测显示 `2.7.0-ff3921ce`,晚于 v2.6.4 tag)。
- **技术栈**:Flutter 3.47.5 (Dart) + Kotlin(Android 层)+ 预编译 `libeasytier_android_jni.so`(来自 upstream `easytier-contrib/easytier-android-jni`,Kotlin binding `EasyTierJNI.kt` 从上游拷贝,包名保持 `com.easytier.jni`)。
- **分层关系**:Flutter UI → Dart `EasyTierService` → MethodChannel `easytier_flutter/core` → `MainActivity.kt` → `EasyTierJNI.kt`(JNI binding)→ Rust core;TUN 由 Kotlin `EasyTierVpnService` 建立,fd 交给 Rust core。
- **约束**:不重写 EasyTier 协议,遇协议问题查 upstream 源码。

## 2. Current Architecture(以代码为准)

```text
Flutter UI (features/*, StreamBuilder 订阅)
    ↓
EasyTierService  (lib/core/services/easytier_service.dart, 状态机 + 3s 轮询)
    ↓
EasyTierBridge   (lib/native/easytier_bridge.dart, MethodChannel 封装 + JSON 解析)
    ↓  MethodChannel 'easytier_flutter/core'
MainActivity.kt  (android/.../io/github/xiaonan520/easytier_flutter/)
    ├→ EasyTierJNI.kt   (com.easytier.jni, JNI binding, 12 个方法)
    ├→ EasyTierVpnService.kt (VpnService, establish() 建 tun, fd 所有权归 Java 侧)
    ↓
Rust core (libeasytier_android_jni.so, runNetworkInstance/setTunFd/collectNetworkInfo)
```

各组件职责:

| 组件 | 文件 | 职责 |
|---|---|---|
| `RootScaffold` | `lib/app/app.dart` | 持有唯一 `EasyTierService` 实例,`IndexedStack` + `NavigationBar` 管理 5 个 tab,`_goToTab` 供 Dashboard 跳转 |
| `EasyTierService` | `lib/core/services/easytier_service.dart` | 状态机 `CoreState{idle,starting,running,stopping,error}`;connect 流程 = parseConfig 校验 → runNetworkInstance → `_waitForVirtualIp`(30s 轮询 DHCP)→ prepareVpn/startVpn;对外暴露 `stateStream`/`statusStream`;固定实例名 `easytier_flutter_default` |
| `ConfigStore` | `lib/core/storage/config_store.dart` | 单 profile 持久化,`shared_preferences` key `network_config_v1`,存 JSON(含 secret,仅手机本地) |
| `EasyTierBridge` | `lib/native/easytier_bridge.dart` | MethodChannel 调用;`parseStatusJson` 把 core JSON(prost,u32 大端 IP)映射为 `NodeStatus`/`PeerRow`;所有 map 用 `Map<String,dynamic>.from` 安全转换 |
| `EasyTierVpnService` | `android/.../com/easytier/jni/EasyTierVpnService.kt` | `establish()` 建 tun;`vpnInterface` 持有 PFD(fd 所有权在 Java 侧,因 core 用 `close_fd_on_drop(false)`);`stopNow()` 同步拆除;`subnetOf()` 派生路由;前台通知 |
| JNI | `EasyTierJNI.kt` | 上游原样 binding:`runNetworkInstance`/`stopInstance`/`setTunFd`/`collectNetworkInfo`/`parseConfig` 等 |

## 3. Flutter UI 当前结构

```text
main.dart
└── EasyTierApp (MaterialApp, Material 3, lib/app/theme.dart 亮/暗主题)
    └── RootScaffold (StatefulWidget, initState 里 new EasyTierService(), dispose 释放)
        ├── IndexedStack (5 页常驻, 切 tab 不丢状态)
        │   ├── [0] DashboardPage(service, onNavigate)   lib/features/dashboard/dashboard_page.dart
        │   │   ├── 状态卡(状态图标/文本/spinner + 错误文本 + Connect/Disconnect FilledButton)
        │   │   ├── 网络信息卡(实例名 + 虚拟 IP)
        │   │   └── 快速链接卡(ListTile → onNavigate(2)=Network tab, onNavigate(1)=Peers tab)
        │   ├── [1] PeersPage(service)                   lib/features/peers/peers_page.dart
        │   ├── [2] NetworkPage(service)                 lib/features/network/network_page.dart(配置表单+Save)
        │   ├── [3] LogsPage(service)                    lib/features/logs/logs_page.dart(事件日志)
        │   └── [4] SettingsPage()                       lib/features/settings/settings_page.dart
        │       └── AboutPage                            lib/features/settings/about_page.dart
        └── NavigationBar(5 destination: Dashboard/Peers/Network/Logs/Settings)
```

- Service 注入:仅构造函数注入,页面不持有全局单例;UI 通过 `StreamBuilder` 订阅 `stateStream`/`statusStream`,页面间零耦合。
- `LogsPage`:订阅两条流,累积状态迁移(`state: X → Y`)与快照(`running: ip=… peers=N core=…`),最新在前,上限 200 行,AppBar 有清空按钮。真机验证过完整生命周期记录。

## 4. 当前已经完成并验证的功能

以下全部为**真机已验证**(最近一次:2026-09-30,release APK):

### VPN
- [x] `AndroidManifest.xml` 中 service 带 `android:permission="android.permission.BIND_VPN_SERVICE"`(此前缺失导致 SecurityException,d9a6c3a 修复)。
- [x] `establish()` 成功,`ip addr` 出现 `tun0: <POINTOPOINT,UP,LOWER_UP> mtu 1300`。
- [x] `dumpsys connectivity` 显示 VPN 网络 CONNECTED,`EstablishingAppUid: 10123`(本 App UID)。
- [x] 精确路由:DHCP 分配 `10.126.126.2/24` 时只加 `10.126.126.0/24` 路由(实测 mesh 网段是 10.126.126.0/24,**不是** README 早期写的 10.144.144.0/24)。
- [x] App 自身流量 bypass(VpnService 的 disallowByDefault/自身 UID 排除在 `EasyTierVpnService` 中处理)。

### EasyTier core
- [x] core 启动、join network(2 个 peer URL:公网服务器 tcp)。
- [x] DHCP 虚拟 IP 分配(`_waitForVirtualIp` 轮询,30s 超时)。
- [x] Peers 页显示 3 节点,延迟 7/35/37ms(u32 大端 IP 解析正确)。
- [x] TOML 配置:官方结构 `[network_identity]`/`[[peer]]`/`[flags]`;`inst_name` 是错的,key 必须是 `instance_name`(d9a6c3a 修复并加回归测试)。
- [x] `parseConfig` 官方解析器前置校验。

### Connect(真机)
- Connect → tun0 出现 → VPN CONNECTED → ping 网关 `10.126.126.1` 0% 丢包,RTT 4–16ms。release APK 上同样通过。

### Disconnect(真机,重点)
- **第一轮 Disconnect(2026-09-30,release APK)**:UI 回 idle;tun0 消失(grep 计数 0);`dumpsys connectivity` VPN 网络 0;`dumpsys activity services` ServiceRecord 0;logcat 无 FATAL。**系统级资源全部干净。**
- **第二轮 Disconnect(同日紧接着)**:同上全部干净,第二轮 connect/disconnect 也正常(tun0 重新建立索引 56,拆除后 0)。
- **关于"第二次 Disconnect fd 残留"**:**当前没有证据支持该问题存在**。2026-09-30 在 release APK 上连续两轮 connect/disconnect,系统级检查(tun 接口/VPN 网络/ServiceRecord/FATAL)全部为 0。注意:`/proc/<pid>/fd` 级别的单 fd 检查在 release 包上**无法进行**(release 不可 debuggable,`run-as` 被拒),debug 包(此前会话)曾验证过 3 轮断开后 fd 全释放。历史修复:d785869 修掉过一次确定的 fd 泄漏(`detachFd` 改为 `establish()` PFD 直接持有);e96d442 修掉 EMUI 上 stopService 不触发 onDestroy 的问题(改为 MainActivity 里先 `instance?.stopNow()` 再 stopService)。如果下一 Agent 想验证 fd 级残留,必须装 debug 包后用 `run-as … ls -l /proc/<pid>/fd | grep tun`。

## 5. 当前已知 BUG

| Issue | Status | Evidence | Suspected cause | Next step |
|---|---|---|---|---|
| 断网时 Connect 30s 超时后报 "Timed out waiting for a virtual IP" | ✅ 已按设计工作(非 bug) | 真机:关 WiFi+数据后 Connect,30s 后 UI 显示 Error,状态不卡 starting | — | 无 |
| "第二次 Disconnect fd/tun 残留" | ⚠️ **未复现,当前无证据** | 2026-09-30 release APK 两轮断开:系统级(tun/VPN/ServiceRecord/FATAL)全 0;fd 级无法在 release 包检查(run-as 被拒) | 不适用 | 若要确认,装 debug 包后 `run-as` 查 `/proc/<pid>/fd`;仅在拿到证据后才能动手改 VPN 生命周期 |
| Dashboard 显示的"网络名"实为例名 `easytier_flutter_default` | 📋 已知行为(非 bug) | `NetworkInstanceRunningInfo` 不携带 network name 字段,map key 是 instance name | core JSON 无该字段 | UI 重构多 Profile 时可改由本地 profile 提供 displayName |
| Notification mArchive 里残留历史通知记录 | ✅ 非 bug | `dumpsys notification` 中是 Archive 历史条目,非活动通知 | — | 无 |

## 6. 已经修改过的重要代码(git log 实录)

```text
4b83ba5 (HEAD -> main) TASKS.md: Phase 7 complete — all stability items verified on device
2b22e68 Phase 5 UI polish: working quick links, event-log page, About version fix
b50fe37 TASKS.md: Phase 4 complete — all live-device tests pass
e96d442 fix: disconnect never tore down VPN on device — sync stopNow() like official plugin
d785869 fix: TUN fd leak on disconnect — keep VpnService PFD ownership
d9a6c3a fix: VPN never established — missing BIND_VPN_SERVICE + wrong instance-name key
45551e5 README: session 3 handoff report — BUG#1-4 fixed, Connected with 10.126.126.2/24 on device
949780c fix: unblock VPN attach — MethodChannel bool/map casts, /32 DHCP route, virtual IP prefix
9bf9afa TASKS.md: record Phase 4 live-test status and secret blocker
65bb1c6 fix: repair 4 blocking bugs for Phase 4 (JNI binding, TOML format, JSON parsing, VPN timing)
8903f8e README: project status, environment quirks, architecture, handoff notes
4e32c87 TASKS.md: mark Phase 2-4 progress
cbeeff4 Phase 2+3: EasyTier native core integration (upstream v2.6.4)
dc3dc9c Phase 1: Material 3 skeleton — theme, NavigationBar root, 4 placeholder tabs, widget test
e6ee9eb Initial Flutter project skeleton
```

关键 commit 详情:

- **d9a6c3a** — 目的:修复 VPN 从未建立。文件:`AndroidManifest.xml`(补 BIND_VPN_SERVICE)、`lib/core/models/network_config.dart`(`inst_name`→`instance_name`)、`test/bridge_test.dart`(回归测试)。验证:真机 VPN 成功建立、实例名不再显示为 "default"。
- **d785869** — 目的:修复断开时 TUN fd 泄漏。文件:`EasyTierVpnService.kt`(去掉 `detachFd()`,`establish()` 返回的 PFD 直接赋给 `vpnInterface`,fd 所有权留在 Java 侧——依据是 upstream `virtual_nic.rs` 用 `close_fd_on_drop(false)`)。验证:3 轮断开后 fd 计数归 0(debug 包)。
- **e96d442** — 目的:修复 EMUI 10 上 `stopService()` 不触发 onDestroy 导致 tun/VPN 网络/前台服务残留。文件:`MainActivity.kt`(stopVpn handler 先 `EasyTierVpnService.instance?.stopNow()`——close fd + stopForeground(REMOVE) + stopSelf——再 stopService)。验证:真机断开后 ServiceRecord 归 0。
- **2b22e68** — Phase 5 UI 打包:Dashboard 快速链接可跳 tab、Logs 页从空白重写为事件日志、About 版本改为 `main @ ff3921c`。真机验证:跳转、完整生命周期日志。
- **949780c / 65bb1c6** — 早期成批修复(JNI 12 方法主版本、toToml 官方结构、prost JSON u32 大端 IP、DHCP 轮询、安全 map cast),详见各自 commit message 与 README。

## 7. 测试状态

- `flutter analyze`:✅ 0 issues(最近一次 2026-09-30,Phase 5 改动后)。
- `flutter test`:✅ 9 个测试全过(`test/bridge_test.dart` 含 parseStatusJson/ipv4FromU32/instance_name 回归 + `widget_test.dart`)。
- `flutter build apk --debug`:✅(会话-4 曾多次构建并装机)。
- `flutter build apk --release`:✅ 2026-09-30,66.1MB,产物 `build/app/outputs/flutter-apk/app-release.apk`。注意:构建曾因 `~/.gradle/gradle.properties` 里写死的死代理(192.168.10.210:7890 已拒绝连接)失败,已把代理行删除换成 jvmargs;项目级 `android/settings.gradle.kts` 用 maven.aliyun.com 镜像,直连即可,不要设 http_proxy 环境变量跑 gradle。
- 真机(release APK,2026-09-30):Connect PASS / VPN established PASS / TUN PASS / Routing PASS(仅 10.126.126.0/24)/ Ping PASS(0% loss)/ Peers PASS(3 节点带延迟)/ Disconnect PASS×2 / Reconnect PASS(Error 态后原地重连成功;App force-stop 后重启重连成功)。
- 互操作性:此前会话验证过与官方 App 双向互连(Test B PASS)。

## 8. Security

- network secret 只存在两处:用户在 App UI 输入后存进手机 `shared_preferences`(`network_config_v1` 的 JSON,`networkSecret` 字段);**代码/文档/git 中绝不能出现**。
- 最近一次 secret grep(2026-09-30,提交前):以用户名前缀+数字 PIN 两个片段做正则扫描(`--exclude-dir=.git`)→ **0 条**;并对全部 15 个历史 commit 对象扫描 → **0 条**。(本文件刻意不写该正则字面量,保证例行扫描零命中。)
- 已知禁写文件:所有 `lib/`、`android/`、`docs/`、`README*`、`TASKS*`、`HANDOFF*`、commit message、logcat 截图。真机上保存的配置含真实 secret,**任何截图/日志输出前注意该字段是掩码显示**。
- 本文档不含任何 secret、token、密码。

## 9. 当前 Git 状态

```text
$ git status --short
?? LICENSE-NOTICES.md

$ git branch --show-current
main

$ git log --oneline -n 3
4b83ba5 (HEAD -> main) TASKS.md: Phase 7 complete — all stability items verified on device
2b22e68 Phase 5 UI polish: working quick links, event-log page, About version fix
b50fe37 TASKS.md: Phase 4 complete — all live-device tests pass
```

工作区不干净,仅 1 个未跟踪文件:

```text
Modified/Untracked:
- LICENSE-NOTICES.md (新文件,已写好未提交)
  reason: Phase 8 "LICENSE notices" 项——声明本项目为 LGPL-3.0 第三方客户端,
          列明从 upstream 拷贝的组件(EasyTierJNI.kt / .so / EasyTierVpnService.kt 来源)
  tested: 不适用(纯文档)
  next agent should: 保留;可单独 commit(docs: add license notices),不要与 UI 改动混提
```

除此之外无任何已修改的代码文件。TASKS.md 中 Phase 1–5、7 全部勾选完成;Phase 8 完成"Release build / APK installation test"两项,"Git cleanup / README / LICENSE notices / Git commit / GitHub repository creation / GitHub push"待做。

## 10. 下一阶段 UI 重构目标(仅记录方向,不要现在实施)

### Bottom Navigation(最终形态)
```text
Home · Networks · Peers · Settings
```
Logs 不再作为一级导航(移入 Settings → Diagnostics)。

### Home(普通用户主页面)
- 当前 Network(名称来自 profile)
- Connected / Disconnected 状态
- Virtual IP
- Connect / Disconnect 按钮
- Upload / Download 流量
- Peer summary(数量)+ 最近 Peer

### Networks(升级为多 Profile)
```text
NetworkProfile
├── id
├── displayName
├── instanceName
├── secret
├── peers
├── DHCP
├── hostname
├── latencyFirst
└── (existing EasyTier options)
```
未来支持:创建 / 编辑 / 删除 / 选择 / 默认 Profile / 最后使用 Profile。**当前只有一个 `ConfigStore` 单 profile(`network_config_v1`),多 Profile 尚未实现,此处仅为计划。** 注意:instanceName 会进入 TOML `instance_name`,是 core 实例注册名,与 displayName 必须分开建模。

### Peers
保持一级页面;展示 hostname / virtual IP / latency / 连接状态 / 必要时 cost(现有 `PeerRow` 已含这些字段)。

### Settings 分组规划
```text
General · Network · VPN · Notifications · Diagnostics · About
```

### Diagnostics
Logs 移到这里,保留现有能力:state transitions、snapshots、200 行上限、清空按钮;普通用户不直接看到开发者信息。

### About
App version / EasyTier core version / upstream commit / open source / licenses(见 LICENSE-NOTICES.md)/ GitHub 链接 / disclaimer。

## 11. Notification / Foreground Service 未来规划(仅计划,勿现在实施)

前台服务通知目标样式:

```text
EasyTier
Home Network · Connected

↓ xx KB/s    ↑ xx KB/s

3 peers · 10.126.126.2
```

Actions:`Open App`、`Disconnect`。

> 说明:Foreground Service 本身才是 Android 保活机制;通知里的流量统计只是展示 EasyTier 真实流量,**不应人为制造流量来"演示"**。现状:`EasyTierVpnService` 已有前台通知(固定内容),升级为上述样式属于 UI-3 阶段。

## 12. UI 重构的安全边界

**可以修改**:Flutter UI、Navigation、Widgets、Theme、Profile UI、Settings UI、Notification UI、ConfigStore/ProfileStore(在明确 ProfileStore 计划后)。

**没有明确证据和必要性不要碰**(按行号级别谨慎):
- Rust core(不在本仓库,upstream 只读参考)
- `EasyTierJNI.kt` 的 JNI API 面(12 个方法签名来自 upstream,不能擅自改)
- EasyTier TOML 语义(`network_identity`/`peer`/`flags`/`instance_name` 的 key 与结构,已由回归测试锁定)
- `BIND_VPN_SERVICE` 权限声明
- `VpnService.establish()` 与 TUN fd 所有权模型(fd 归 Java 侧 `vpnInterface` 持有,core 用 `close_fd_on_drop(false)`,改动需先读 upstream `virtual_nic.rs`)
- `EasyTierVpnService.stopNow()` 同步拆除链(EMUI 上 stopService 不可靠的问题已修,勿回退)
- `AsyncDevice` / VPN 生命周期整体

> "第二次 Disconnect fd 残留"当前**未复现、无证据**(见 §5)。UI Agent 不应因重构顺手改 VPN fd 生命周期;只有拿到 debug 包 run-as 证据后才可立项修复。

## 13. 给下一 Agent 的推荐工作顺序

```text
UI-1  Navigation + Home + Networks UI + Peers + Settings + Diagnostics + About
        (纯 UI/导航重排,单阶段完成,独立测试+commit)

UI-2  NetworkProfile / ProfileStore
        ↓ create / edit / delete / select / last-used
        (数据层改动,注意 instanceName 与 displayName 分离)

UI-3  Traffic statistics
        ↓ Foreground Service 通知升级
        (流量数据源需要先调研 core 是否暴露 rx/tx 计数,勿人为造流量)
```

每阶段:`flutter analyze` + `flutter test` + `flutter build apk --debug` 通过 → `adb install -r` 真机 sanity check → secret grep → 独立 commit。

## 14. NEXT AGENT FIRST STEPS

1. 通读本文件(`HANDOFF_NEXT_AGENT.md`)。
2. `git status` / `git log --oneline -n 15`,确认与本文件 §9 一致。
3. 读 `lib/app/app.dart`、`lib/features/*/*.dart`(共 ~640 行 UI 代码)。
4. 读 `lib/core/services/easytier_service.dart`(状态机与 connect 链,175 行)。
5. 读 `lib/core/storage/config_store.dart`(26 行,单 profile 持久化)。
6. 读 `android/app/src/main/kotlin/com/easytier/jni/EasyTierVpnService.kt` 与 `MainActivity.kt`(理解但不要改)。
7. 核对本文件与实际代码有无出入;有出入以代码为准并回报。
8. 不要直接开始大规模修改。
9. 先产出 **UI-1 实施计划**(导航结构、每页内容、涉及文件清单)。
10. **用户确认后再动手实施。**

### 环境备忘(必读,否则命令会失败)
- `/home` 分只读:跑 flutter/gradle 前 export `HOME=/home/xiaonan/Easytier/.home`、`GRADLE_USER_HOME=/home/xiaonan/Easytier/.gradle`、`XDG_DATA_HOME`、`ANDROID_USER_HOME`、`ANDROID_NDK_ROOT=/opt/android-sdk/ndk/28.2.13676358`,cargo bin 加入 PATH。
- **不要**给 gradle 设 `http_proxy=192.168.10.210:7890`(该代理已死,2026-09-30 实测拒绝连接;项目已配 aliyun 镜像直连)。
- 真机:Huawei HMA-AL00,Android 10,1080×2244。底部 tab y=2152,x: Dashboard 110 / Peers 330 / Network 552 / Logs 772 / Settings 994;Connect 按钮 ≈(552,556)。Gboard 默认拼音,`adb shell input text` 前先切英文键盘;用户可能同时在用手机,勿盲点坐标。
- release 包不可 `run-as`;需要 fd 级检查时装 debug 包。
- 保存的设备配置:网络名 `xiaonan-home-ai`,2 个 peer URL,DHCP 开,latencyFirst 开(secret 在 shared_preferences,勿外泄)。

---

*交接生成时间:2026-09-30。生成者已核实:git 状态、最近 15 个 commit、全部 UI/service/store/VPN 源码、当日 release APK 两轮 connect/disconnect 真机结果。*
