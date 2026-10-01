# 状态记录 — 2026-10-01 暂停点

> 本文由当次会话写入。所有内容以当前代码与真机实况为准。

## 当前 Git / 环境

- 分支 `main`,HEAD `114fef3 feat: real traffic stats, peer connection type, faster static-IP connect`,**已推送 GitHub**(github.com/Xiaonan-520/easytier_flutter,public)。
- 最近提交:`114fef3` 真实流量统计+peer连接类型+静态IP快速连接 → `c61debb` profile 保存错误提示 → `1c489b1` docs checkpoint → `8d3fde1` UI-6 通知 → `11e10fd` spinner fix → `d5b1b8a` UI redesign → `a0140a6` fd 证据 → `4b83ba5` Phase 7。
- secret 扫描(`xiaonan@`/`147369`):0 命中。
- 构建环境(不要 export HOME!gradle debug signing 读 `$HOME/.android/debug.keystore`,必须用默认 `/home/xiaonan/.android` 的):
  `export GRADLE_USER_HOME=/home/xiaonan/Easytier/.gradle ANDROID_USER_HOME=/home/xiaonan/.android ANDROID_SDK_ROOT=/opt/android-sdk PUB_CACHE=/home/xiaonan/Easytier/.home/.pub-cache PATH=/home/xiaonan/Easytier/.home/.cargo/bin:$PATH`
  **不要设 http_proxy/https_proxy**(老代理已死,aliyun 镜像直连)。
- **真机已换**:HuaWei YAL-AL10,Android 10,arm64-v8a,serial ERLDU19920013465(旧 HMA-AL00 已不用)。prefs 已从 `pref_backup3.xml` 恢复。App UID 10112。
- Gboard 拼音会打乱 `adb shell input text`——长文本仍需用户手动输入。

## 本阶段完成(114fef3,全部真机验证过)

1. **真实流量统计(RX/TX)**:核心 `peer_route_pairs[].peer.conns[].stats`(rx_bytes/tx_bytes/prost u64-as-string)+ `route.cost`。`TrafficStats`(差分速率 + 累计值)在 `easytier_service.dart` 采样;Home Traffic 卡显示 `0.2 KB/s / Total 8.2 KB` 等真实数据;通知 bigText 同步真实速率(`formatRate`,0 显示 em dash,无假数据)。测试含 u64 字符串计数器 fixture,12/12 过。
2. **Peer 连接类型**:cost==1 且有 conns → P2P,否则 Relay(+distinct tunnel_type 数)。Peer 详情 sheet 显示 Connection: P2P / Relay (n) + per-peer Traffic。真机确认 homeserver=P2P。
3. **关键修复——establish 4ms 失败根因**:静态 IP `10.126.126.2`(裸 IP)被 Kotlin `createVpnInterface` 的 `require` 拒绝(`invalid ipv4 addr`)。Dart 端 `_withPrefix()` 规范化补 `/24`;设备存量 prefs 也已修正为 `10.126.126.2/24`。
4. **静态 IP 立即建 TUN**(不再傻等 DHCP 90s);DHCP 超时 30s→90s(EMUI 对称 NAT OSPF 收敛实测 ~60s,公网服务器上残留的僵尸 peer 会拖慢收敛);错误路径补 `stopVpn()` 回收 TUN。
5. **EMUI 诊断手段**:`EasyTierVpnService.dbg()` 文件级日志(`getExternalFilesDir(null)/vpn_dbg.log`,run-as 读取)。**EMUI logcat 会吞 App 的 Kotlin Log.i/e(只放行 Rust 的 EasyTier-JNI 和系统日志)**——以后排查 Android 侧问题直接看文件,别信 logcat 缺失。
6. 验证记录:tun0 ~5s 建立(10.126.126.2/24, mtu 1300)、ping 10.126.126.1(homeserver)0% loss、两轮 connect/disconnect 干净(tun0 归零)、0 FATAL。

## 设备当前状态(暂停时)

- App 已断开(tun0=0),UI Disconnected,两 profile 完整(xiaonan-home-ai current,静态 IP 10.126.126.2/24;TestNet dhcp)。
- 安装的是 debug APK(默认 keystore)。
- ping homeserver 走 VPN 正常;`best 6 ms`。

## 下一步(按用户优先级)

1. **Quick Settings Tile**:TileService 读 native `EasyTierVpnService.isRunning` 作为唯一状态源;ON→OFF 走 service teardown,OFF→ON 走 engine handoff 到 `EasyTierService.connect(currentProfile)`。注意 EMUI 对 Tile 启动 service 的后台限制(AppBgModeMgr 会拦 background start——Activity 前台时没事,Tile 场景需验证)。
2. **通知状态失步加固**:App 启动时(init)主动 push 一次状态到通知;5 状态全覆盖验证(含 force-stop 重启、系统吊销 VPN onRevoke)。
3. **统一数据架构**:Home/Notification/Tile 全部从 EasyTierService 单一数据源取(目前 Home 直接 collectStatus 的部分可迁到 service stream)。
4. **DHCP 模式用户提示**:静态 IP 是当前网络的可靠路径(DHCP 在新手机上要 60s+ 且曾撞过 90s 超时);编辑器里可给 DHCP 加提示文案。
5. `flutter analyze` / `test` / build 每阶段照旧;最后更新本文档并推送。

## 已知非问题(勿重复调查)

- tun0 MTU 9000/172.19.0.1 = Clash Meta 的 TUN;我们的是 mtu 1300。
- EMUI "DollieAdapterService"/"SEAPP"/AppBgModeMgr 日志是噪声;但 **AppBgModeMgr 的 fgService start→stop 4ms 是真实信号**(service 快速死亡,当时根因就是 establish 抛异常)。
- 公网服务器上残留的历史 peer(旧 process 的 peer_id)会拖慢 OSPF 收敛,但静态 IP 路径不受影响。
- TestNet 连不上是预期(不同 network 身份)。
