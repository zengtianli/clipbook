# CLAUDE.md — clipbook（TL Clipbook · 自用剪贴板历史）

替代 Deck 的自用剪贴板历史。**全 Swift 原生，swiftc 直编，无 xcodeproj / 无 SPM / 无后端进程 / 无网络。**
只做 Deck 实测在用的 20%（2026-09-05 盘点 `~/Apps/mac/handoffs/own-tools-inventory.md`）：
记录（文本/链接/图片/文件）· 子串搜索 · 置顶 · 回车粘贴 · 同内容去重顶上 · 超 5000 条淘汰。
**不做**：AI、跨设备同步、SmartRules、标签、富文本保真。

> 与 /appmac 范本的偏离要说清：范本的「Swift 零业务、后端 Python」是给**控制台 app**的；
> 剪贴板监听必须在进程内轮询 NSPasteboard，逐条 spawn Python 荒唐，所以业务（SQLite/抓取/粘贴）就在 Swift 里。

## 构建 / 装机

```bash
cd ~/Apps/mac/clipbook
git commit …      # 先提交（CFBundleVersion = commit 数，build-after-commit-guard 会提醒）
./build.sh        # 四道 fail-closed 门 → swiftc → --selftest → 打包 → 签名 → 装 /Applications/TL Clipbook.app
open -a "TL Clipbook"
```

签名用本机 **Apple Development** 证书（不是为了分发，是让「辅助功能」授权跨重编存活；adhoc 每次换 cdhash 授权就掉）。

## 架构（一条数据的路）

`PasteboardWatcher`（0.25s 轮询 changeCount）→ `extract()` 纯函数（**文件 > 文本 > 图片**，跳过 Concealed/Transient）
→ `ClipStore.ingest`（SHA256 去重：命中 = 顶上不新增；图片 PNG 落 blobs/）→ `AppModel.reload` → `PanelView`。
回车：`Paster.write` 写回剪贴板（记 changeCount 让 Watcher 跳过自己）→ 面板 orderOut → 授权了辅助功能才 CGEvent ⌘V，否则如实提示「只复制」。

面板是 **nonactivating NSPanel**（`Panel.swift`）：能成 key window 接键盘，但不激活本 app，用户原 app 一直在前台，⌘V 直接落它身上。

## 硬约束

- **热键候选表登记在总部** `~/Dev/tools/configs/hotkeys.yaml`（`cmd-shift-v → ctrl-shift-v → cmd-opt-v`），build.sh 门②机检零交集。改候选先改 SSOT。
- **输入法组字期间 ↑↓↩esc 必须让给候选框**（`PanelView.composing`）。2026-09-05 实测搜狗拼音下回车被截成粘贴。
- selftest 只驱动生产函数（`ClipStore` / `PasteboardWatcher.extract`），禁另写一遍逻辑去验；已反向验证（拆去重/拆文件优先级 → 3 项红）。
- 密码管理器条目（`org.nspasteboard.ConcealedType`）永不入库；这是隐私底线不是可选项。
- 跨进程同热键（Deck 在跑）双方都注册成功，**谁后启动谁响应**（实测）。换用本 app = 退掉 Deck。
- 数据在 `~/Library/Application Support/Clipbook/`（`CLIPBOOK_HOME` 覆盖）。不迁移 Deck 的库。

## 自动化入口

`clipbook://show[?q=关键词]` · `clipbook://hide` · `clipbook://toggle`（Hammerspoon / Raycast 可调）。
