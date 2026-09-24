# Mac → iOS 正式 iCloud 同步 · 2026-09-24

## 目标与根因

用户要求 Mac 复制的内容自动出现在 iPhone Clip，手机安装来源为 App Store / TestFlight；要求先由本机验证再交给本人使用。

已安装 Mac 1.1 (33) 的运行日志在 11:35:15 明确显示 `iCloud.cyou.tianli.clip:Sandbox`，applicationBundleID 为 `cyou.tianli.clipbook`。手机商店包使用 Production，两套环境不互通。Mac 旧云库有 570 条且有成功上传事件，这些不能证明商店手机收到了记录。

## 修复

- Mac Release 显式签入 Production，Debug 使用 Development；构建脚本核对实际签名 entitlement 和 Info.plist，避免只改源码未生效。
- Production 使用 `CloudLibrary-Production`、独立归档标记和 `cloudAccount.Production`。原 `CloudLibrary` 和主剪贴板库保留，不混用开发环境的 CloudKit 元数据或账户身份。
- 启动后补充最近 500 条，覆盖首次迁入正式环境及云库打开期间的复制；不重复注册数据变化观察者。
- iOS 唯一源 `Shared/ClipLibrary.swift` 增加可选账户偏好键；iOS 默认行为不变，Mac 经现有软链消费。
- 两端中英文 README 增加 Mac 复制 → iPhone 查找 → 复制粘贴的操作步骤与排错。
- Mac 新增 `--background`，启动记录和同步但不打开主窗口，便于更新后保持用户焦点。

## 已执行验证

- Mac Release 构建、完整 `--selftest`、实际签名 Production 检查通过；共享库 23 项隔离回归通过。
- iOS Simulator Debug 构建通过。原 Clip Guide 设备多次安装/启动卡住；新建隔离设备 `8EEF1C1B-D2F5-454C-BB63-1D7551F1734E` 后启动并查看了历史列表。截图：`../../ios/01-源程序/shots/guide/review/history-20260924.png`。均为虚构数据，模拟器已关机。没有把演示数据当成云端收到的真实记录。
- 正式云端测试 token：`clip-prod-20260924-87971b88`。两个隔离 Mac 实例经 LaunchServices 后台启动，独立偏好、主库、CloudKit 库和命名剪贴板；首条标记在接收端主库读回。
- 在发送实例的命名剪贴板写入 `Clip live copy <token>`，由真实 Watcher → AppModel → MacClipSync 自动归档；11:54:46 复制，11:54:48 获得成功 export 事件。
- 用 iOS 的 bundle ID `cyou.tianli.clipmobile`、macOS 描述文件、Production entitlement 和实际共享库构建独立接收器；11:58 读到原标记及上述新复制标记。此接收器运行在 Mac 上，**不是 iPhone 真机或已登录 iCloud 的 iOS 模拟器**。
- 同一 bundle ID 的多个 Mac 进程未在观察窗口内自动推送给所有实例，因此没有用它们宣称真机后台到达延迟。不同 iOS 身份的接收库实际 import 成功。

诊断产物在 `build/cloud-verification/`（忽略入库）；`tests/CloudProductionProbe.swift` 复用 iOS `Sources/CloudProbe.swift`。签名探针必须通过 LaunchServices 后台启动；直接运行可执行文件时本机系统调度出现 `BGSystemTaskSchedulerErrorDomain Code=3`，仅完成 setup，不能据此把连接成功当收发成功。探针必须使用隔离路径，iOS 签名带 sandbox 时路径须落在其容器内。

## 边界

真机本轮 unavailable，未操作手机或替换手机安装包；没有发布、送审或推送。iOS 已有 GuideDemo / GuideUITests / guide-shots.sh 等未提交改动保留。照片分享截图旧测试失败、快捷指令旧测试只验证配置步骤；不把它们当作本轮完整验收。

本轮安装、清理和最后运行回读见同目录对应后续记录；正式收发验证使用合成标记，必须仅清除这些标记，不删除用户云库或主历史。
