# CLAUDE.md — clipbook（TL Clipbook · 自用剪贴板库）

替代 Deck 的自用剪贴板库，**PastePal 形态**（2026-09-05 用户否掉了第一版的 Maccy 式小面板，改成这样）：
菜单栏常驻，点图标开主窗口 —— 左栏筛（类型 / 来源 app / 收藏夹）、中栏自适应网格多选、右栏直接改。
**全 Swift 原生，无 SPM / 无后端进程。** 默认仅抓链接页面标题（可关）；2026-09-09 加可选 iCloud 历史归档，为 CloudKit 描述文件签名改用 XcodeGen 构建。

## 快捷键必须可配置，默认不绑定（用户本轮纠正）

旧版把「不要默认设置」误解成「没有快捷键功能」，已被用户否定。`ClipShortcuts.defaultBindings` 必须为空；设置页提供录制、应用内/全局作用域与清除。只有用户明确保存的全局绑定才能注册，失败不自动换键。**⌘⇧V 是用户 Keyboard Maestro 的宏，永远别在测试里按。** 主菜单里的 ⌘C/⌘V/⌘A/⌘Z 属于系统文本编辑，不注册全局键。
测试用独立 UserDefaults suite 和数据目录，绝不往用户偏好默认写入 ⌘, 或其他测试组合。`clipbook://toggle` 仍供外部自动化使用。快捷键与记录偏好测试在生产 `--selftest` 中。

用户进一步明确：⌘C 应在 Clip 内复制多条所选内容。标准编辑菜单和自定义复制动作共用 `ClipCopy`：文本选区优先，无文本选区才调用 AppModel.copySelection，按当前显示顺序写入全部所选记录。允许为复制动作录制应用内 ⌘C，不能拦成非法系统组合；不写入默认全局绑定。每一项都提供应用内/全局选择，不能擅自将部分动作固定为应用内。全局动作使用 Clip 保留的选择。

Clip 必须是正常独立应用：`LSUIElement=false` + `.regular` activation policy，显示 Dock / ⌘Tab / 前台应用菜单；启动打开主窗口，关窗可从 Dock 重开。菜单栏按钮只作为附加入口。

## 构建 / 装机

```bash
cd ~/Apps/clip/mac
git commit …      # 先提交（CFBundleVersion = commit 数）
./build.sh        # → build-cloud.sh → XcodeGen/Release → --selftest → 签名/描述文件检查 → 装 /Applications/Clip.app
open -a "Clip"
```

签名用 Apple Development 证书不是为了分发，是让「辅助功能」授权跨重编存活（adhoc 每次换 cdhash 授权就掉）。

## iOS / iCloud（2026-09-09）

iOS 客户端在 `/Users/tianli/Apps/clip/ios`。容器 `iCloud.cyou.tianli.clip`。
`MacClipSync` 按需初始化，未开启不创建 Core Data store、不做云请求。原有 ClipStore 保持主库；同步归档在 Clipbook/CloudLibrary。
首次开启整理最近 500 条，随后 watcher 新记录加入；云端新内容回流至本地。文件路径不上传、富文本降纯文本；Mac 清理与云端归档独立，不声称编辑/删除/收藏完整双向镜像。
`Sources/Native/PocketLibrary.swift` 是指向本家族 iOS `Shared/ClipLibrary.swift` 的相对软链；两端编译消费同一原版，构建 Mac 须同时检出家族 iOS 源树，安装包无运行时跨 App 依赖。
构建 `build-cloud.sh --build-only` 可只出包。保持 bundle ID、可执行名、数据路径与用户快捷键不变。

## 一条数据的路

`PasteboardWatcher`（0.25s 轮询）→ `extract()` 纯函数（**文件 > 文本(带 RTF) > 图片**，跳过 Concealed/Transient 与忽略名单）
→ `Classifier.kind(of:)`（link / color / code / text，**三处共用的唯一判据**：抓取、编辑保存、Deck 导入）
→ `ClipStore.ingest`（SHA256 去重：命中 = 顶上不新增；PNG/RTF 落 blobs/）→ `AppModel.reload` → 三栏。
编辑保存 `updateText`：覆盖原条目、按新内容重识别类型、富文本降纯文本、撞重删另一条。
粘贴：写剪贴板 → 收窗口 → `yieldActivation` + `activate(from:)` 切回「上一个前台 app」（workspace 通知持续跟踪，不依赖开窗那一刻）→ 授权了辅助功能才 CGEvent ⌘V。

## 硬约束 / 踩过的坑

- 键盘友好是应用基本要求：网格方向键与 Shift 扩选由稳定的 `GridKeyboard.Responder` 接收，不能让会被 LazyVGrid 回收的单张卡片持有导航焦点。编辑器、侧栏沿用自身按键行为，不用全局监视器抢方向键。
- 隐藏主窗口走 `hideWindow()`：卸载 HostingView，保留当前草稿与全局复制所需选择，暂停界面查询，恢复时重载。图片使用 ImageIO 按预览尺寸解码及有界缓存，禁止把原图当无限缓存的缩略图。

- **卡片点选走 AppKit `ClickCatcher`**（mouseDown 拿修饰键 + acceptsFirstMouse）：SwiftUI TapGesture 在窗口不在前台时第一下只激活不选中，`NSApp.currentEvent` 拿不到修饰键。
- **macOS 14 协作式激活**：切回别的 app 必须 `NSApp.yieldActivation(to:)` + `app.activate(from: .current)`；`open clipbook://` 能否把本 app 拉到前台**不稳定**，用户配热键建议 `osascript -e 'tell application "TL Clipbook" to activate' -e 'open location "clipbook://toggle"'`。
- 手搓 NSApplication **必须装主菜单**，否则文本框 ⌘V 不工作。
- 收藏夹对话框图标行用 LazyVGrid，HStack 会撑破 frame 被居中裁掉。
- Deck 只给最近的图留原图（Blobs/），更早的只剩 preview_data 缩略 —— 导入器回退用缩略，别丢。
- selftest 只驱动生产函数；Deck 导入用**Deck 表结构的夹具库**喂同一个导入器。
- 密码管理器条目（`org.nspasteboard.ConcealedType`）永不入库。
- 数据在 `~/Library/Application Support/Clipbook/`（`CLIPBOOK_HOME` 覆盖）；首次启动自动导 Deck（只读 Deck 的库，拷到临时目录再开）。

## 自动化入口

`clipbook://show[?q=关键词]` · `clipbook://hide` · `clipbook://toggle` · `clipbook://settings`。
外部 URL 通过 `application(_:open:)` 接收；窗口就绪前排队，不能等到 `didFinishLaunching` 才注册事件处理器（旧版会丢失第一次冷启动链接）。修改此入口后用已打包 .app 验证冷启动 show?q、运行中 show/settings、hide→toggle，并通过 CUA 核对目标搜索词/窗口；selftest 不覆盖 LaunchServices。证据见 `handoffs/url-open-fix.md`。
UI 自动化验收：按钮有 `accessibilityIdentifier`（save / saveAsNew / copy / paste / merge / batchDelete / batchAddToCollection / newCollection / collectionName / createCollection / importDeck）。

产品家族入口：/Users/tianli/Apps/clip/README.md。
