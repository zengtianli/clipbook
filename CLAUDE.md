# CLAUDE.md — clipbook（TL Clipbook · 自用剪贴板库）

替代 Deck 的自用剪贴板库，**PastePal 形态**（2026-09-05 用户否掉了第一版的 Maccy 式小面板，改成这样）：
菜单栏常驻，点图标开主窗口 —— 左栏筛（类型 / 来源 app / 收藏夹）、中栏自适应网格多选、右栏直接改。
**全 Swift 原生，swiftc 直编，无 xcodeproj / 无 SPM / 无后端进程。** 唯一网络访问 = 抓链接页面标题（设置里可关）。

## 🔴 不设任何快捷键（用户 2026-09-05 两次明确）

全局热键没有，窗口内也没有（连收藏夹对话框的回车/Esc 都不绑）。**⌘⇧V 是用户 Keyboard Maestro 的宏，永远别碰、别在测试里按。**
用户要快捷键自己在 KM / Hammerspoon 里配 `open 'clipbook://toggle'`。主菜单里的 ⌘C/⌘V/⌘A/⌘Z 是 macOS 文本框标配（没有它们文本框粘贴不进去），不算本 app 的快捷键。

## 构建 / 装机

```bash
cd ~/Apps/mac/clipbook
git commit …      # 先提交（CFBundleVersion = commit 数）
./build.sh        # 三道 fail-closed 门 → swiftc → --selftest → 打包 → Apple Development 签名 → 装 /Applications/TL Clipbook.app
open -a "TL Clipbook"
```

签名用 Apple Development 证书不是为了分发，是让「辅助功能」授权跨重编存活（adhoc 每次换 cdhash 授权就掉）。

## 一条数据的路

`PasteboardWatcher`（0.25s 轮询）→ `extract()` 纯函数（**文件 > 文本(带 RTF) > 图片**，跳过 Concealed/Transient 与忽略名单）
→ `Classifier.kind(of:)`（link / color / code / text，**三处共用的唯一判据**：抓取、编辑保存、Deck 导入）
→ `ClipStore.ingest`（SHA256 去重：命中 = 顶上不新增；PNG/RTF 落 blobs/）→ `AppModel.reload` → 三栏。
编辑保存 `updateText`：覆盖原条目、按新内容重识别类型、富文本降纯文本、撞重删另一条。
粘贴：写剪贴板 → 收窗口 → `yieldActivation` + `activate(from:)` 切回「上一个前台 app」（workspace 通知持续跟踪，不依赖开窗那一刻）→ 授权了辅助功能才 CGEvent ⌘V。

## 硬约束 / 踩过的坑

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
