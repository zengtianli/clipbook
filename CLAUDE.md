# CLAUDE.md — clipbook

SwiftUI macOS app（脚手架生成自 macapp_scaffold，范本 ssot-console）。Swift 层只做 GUI
（列表/卡片/按钮/调 Process/显示结果），**不解析 YAML、不写 SQL、不重写业务逻辑** ——
真实工作全委托给外部 Python CLI（经 `uv run --project ~/Dev` 调用，返回 JSON）。

新需求先读 playbook：`~/Dev/tools/configs/playbooks/native-console-app.md`（决策树 + 全部坑单）。

## 构建

```bash
cd ~/Apps/mac/clipbook
./build.sh          # 构建 + 装 /Applications（Xcode 自动挑，见下）
```

**别自己写 `DEVELOPER_DIR=/Applications/Xcode.app/...`。** 本机 `xcode-select` 指向
CommandLineTools（`xcodebuild` 在那儿直接报 requires Xcode），而盘上可能同时躺着好几个
Xcode、其中一些已被当前 macOS 判为不支持。该用哪个由总部 SSOT 现算：

```bash
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh && xcode_env_use macosx
# build.sh 里已经内置这一行；想单独看它挑了谁：
python3 /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.py list
```

## 硬约束（与范本 ssot-console 一致）

- bundle id `cyou.tianli.Clipbook`；部署目标见 pbxproj `MACOSX_DEPLOYMENT_TARGET`。
- **JSON 契约**：后端 stdout 纯 JSON；`gui-*` 子命令一律 exit 0，失败 = `{"ok": false, "error": "人话"}`；
  字段 snake_case（Swift 侧 `.convertFromSnakeCase` 自动映射）。改 `Models.swift` = 同步改后端输出。
- 正式后端放 `~/Dev/tools/dev/lib/tools/` 下（平台-子公司模型），改 `BackendClient.defaultScriptPath`
  指过去；多后端 = 多 script 常量 + `runDecoding(args:script:)` 路由。`backend_demo.py` 是占位，可删。
- 新增源文件要动 pbxproj 4 处（PBXBuildFile / PBXFileReference / Sources group / Sources build
  phase）—— 小增量优先 append 进现有 5 文件，MARK 分节。
- UI 坑单（语义色零硬编码 / 禁 `fixedSize(h:false,v:true)` / detail 根 minWidth 600 / 并发 drain /
  GUI PATH 注入）已以代码+注释固化在 Sources/ 里，删注释前先读 playbook。
