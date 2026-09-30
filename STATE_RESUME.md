# 状态记录 — 2026-09-30 深夜暂停点(明天继续)

> 本文由当次会话写入,记录 UI-6 验证进行到哪一步、下一个动作是什么。所有内容以当前代码与真机实况为准。

## 当前 Git / 环境

- 分支 `main`,HEAD `8d3fde1 feat(android): dynamic foreground notification + app icon`,**已推送 GitHub**(github.com/Xiaonan-520/easytier_flutter,public)。工作区干净。
- secret 扫描(用户名前缀+数字 PIN 两个片段,`--exclude-dir=.git`):0 命中(提交前查过)。
- 构建环境(必须 export,否则 gradle/签名出错):`HOME=/home/xiaonan/Easytier/.home`、`GRADLE_USER_HOME=/home/xiaonan/Easytier/.gradle`、`ANDROID_USER_HOME=/home/xiaonan/Easytier/.home/.android`、`ANDROID_SDK_ROOT=/opt/android-sdk`、`ANDROID_NDK_ROOT=/opt/android-sdk/ndk/28.2.13676358`、cargo bin 入 PATH。**不要设 http_proxy/https_proxy**(老代理已死)。
- **签名注意**(今天踩过坑):gradle 的 debug signing 默认读 `$HOME/.android/debug.keystore`。手机上现在装的包签名 = 默认 `/home/xiaonan/.android/debug.keystore`(SHA1 C1:24:B1:58…)。如果 export 了 `HOME=/home/xiaonan/Easytier/.home` 构建,会用另一个 keystore(SHA1 87:15:E0:01…),install 会报 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`。**两个选择:构建时不改 HOME(仅改 GRADLE_USER_HOME 等),或卸载重装(记得先备份 shared_prefs,见下)。**
- 手机上的 profile 数据(含网络 secret)存在 `shared_prefs/FlutterSharedPreferences.xml`;备份文件在 `/home/xiaonan/Easytier/.home/pref_backup2.xml`。恢复方法:`adb push 备份 /data/local/tmp/prefs.xml` 后 `run-as … cp` 到 `shared_prefs/`(仅 debug 包可 run-as)。
- 真机:HuaWei HMA-AL00,Android 10,1080×2244。底部 tab(y=2152):Home 135 / Networks 421 / Peers 707 / Settings 993。Home 页 Connect 按钮当前布局 ≈(552,838);Networks 页右上角 ＋ ≈(1013,148)。
- **输入法坑**:Gboard 拼音会把 `adb shell input text` 打乱(全角/联想)。已切到 Latin IME 仍会出问题(如 `18.3230`、`TCP：／／`)。**长文本一律请用户手动输入。**

## UI-6 当前进度

已完成并提交(`8d3fde1`):
- `NotificationHelper.kt`(新文件):通知内容渲染,状态文案/profile 名/peers·IP 摘要/traffic 占位(`↓ — ↑ —`,无假数据)。
- `EasyTierVpnService.kt`:通知初始渲染走 helper;`CHANNEL_ID`/`NOTIFICATION_ID` 改 public 共享;新增 `ACTION_NOTIFICATION_DISCONNECT`(engine 不在时走 `stopNow()` 正式拆除,VPN 生命周期未动)。
- `MainActivity.kt`:MethodChannel 新增 `updateNotification`。
- `easytier_bridge.dart`:`updateNotification()` fire-and-forget。
- `easytier_service.dart`:`_setState()` 与 running 时的 `refreshStatus()` 都会 `_syncNotification()`(单一状态源,Home 与通知永远一致)。
- 应用图标:用户提供的 `icon_easytier.png`(项目根目录)已生成全部 mipmap 密度,真机 launcher 已确认生效。
- 真机已验证:Connected 通知 = `EasyTier / xiaonan-home-ai · Connected` + bigText `↓ — ↑ — \n 3 peers · 10.126.126.2` + 2 个 action(Open App/Disconnect);HOME 退出后通知保留、tun 保持;App 内 Disconnect 后通知变 `· Disconnected` 且 tun/VPN 归 0;又跑 3 轮 connect/disconnect 全干净,0 FATAL。analyze 0 issues、10/10 tests、debug APK 构建通过。

## 暂停点:多 Profile 回归(UI-6 收尾,做到一半)

- 已在手机上手动创建了 Profile B:**TestNet / instance `easytier_flutter_testnet` / 无 secret / peer `tcp://183.230.36.171:11010`**(内容已核对无误,截屏 `.home/p5c.png`)。
- **卡在:编辑器右上角 ✓ 保存按钮点了两次都没生效**(页面仍停在 New Network,`.home/p9c.png`)。原因未查明——可能是键盘弹出遮挡 hit-test 或 tap 坐标偏差(✓ 在 ≈1013,62;键盘弹出时 AppBar 不应被遮挡,但需确认)。**这是下一步第一件事:让用户手动点 ✓,观察是否保存;若还不行,先在本地复现调查 `NetworkEditorPage._save()`(f52 的 `onPressed: _busy ? null : _save` 和 IconButton)是否有 bug——注意 `_save` 里 `Navigator.pop` 前没有 setState 复位 `_busy`,若 add/update 抛异常会卡死按钮,先查这个。**
- 保存成功后的回归清单:
  1. Networks 列表出现两张卡,xiaonan-home-ai 仍是 current(实心点);
  2. 菜单 Set as current 切到 TestNet → Home 显示 TestNet → Connect → 验证 tun/通知显示 `TestNet · Connected`、IP 来自 TestNet 网络;
  3. Disconnect → 切回 xiaonan-home-ai → Connect → 验证 IP=10.126.126.x、3 peers、secret 正确(连上即证明);
  4. App force-stop 重启 → currentProfile 仍是 xiaonan-home-ai,数据完整。
- 注意:TestNet 网络与主网络是不同 network_name,peer 只有公网节点,连上后可能只有 1-2 peers、IP 段不同——这是预期,不是 bug。

## 之后的待办

- UI-6 最终报告(用户要求的 9 点格式)。
- release APK 全流程验证(无 release signing,用 debug key;构建时注意上面的 HOME/keystore 坑)。
- TASKS.md 勾选 UI-6 相关项;README/HANDOFF 增补 Notification 架构一节。

## 今日新增截屏索引(`~/Easytier/.home/`)

`li1c.png` 新图标启动后 Home;`n1c/n3c.png` Connected 状态;`notif2/3.txt` 通知 dumpsys 文本;`p5c.png` TestNet 表单核对;`p8c/p9c.png` 保存卡住的现场;`launcher*.png` 桌面图标。
