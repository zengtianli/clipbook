# 下载版设置语言（2026-10-18）

Chapter task: `65b457397def40bf8d815cab7470e2ef`。复用 pid 3872 的原 claim，未新建或释放声明。

## 本轮修改与提交边界

- `Sources/Shared/AppLifecycle.swift`、`AppLifecycleUI.swift`：按用户要求同步共享原版，逐字节检查通过。共享窗口顶部提供语言三选项，写本 App 的 AppleLanguages、重开生效。
- 这两份文件开工时已有共享中英文本地化的未提交改动。本轮同步所需的语言实现依赖 LifecycleText；本轮纳入的是共享原版完整快照（含该依赖），不另拆改共享模块。此处通知同范围 Chapter 执行者核对，避免后续重复提交。
- `Sources/Native/SettingsView.swift`：只暂存本轮新增的 19 行语言设置。Clip 独立设置页并非共享窗口，因此接入相同 LifecycleLanguage；`!APP_STORE` 限定下载版。该文件原有其他会话本地化改动仍留工作区。
- `build-cloud.sh`：补上原 vendor-lifecycle.py 同步入口。沿现有 BuildSlot，未新增锁。
- project.yaml 与其他产品/商店目标均不提交。试过的截图精确允许项已撤回；现有扫描无需放宽。

## 已核验

- `./build.sh --build-only`：成功，生产 selftest 全通过，Developer ID signed 等级通过。候选 `.dd-cloud/Build/Products/Release/Clipbook.app` 为 1.2.1 (144)，来自本轮当前工作区（含开工时已有、保留的在途改动），不是纯提交快照。
- `bash scripts/accept/privacy.sh`：通过；17/17 运行检查、6/6 静态检查，共享逐字节一致。扫描规则未修改。
- `chapter l10n shots --app clipbook`、`chapter l10n check --app clipbook`：通过。已目视两种语言的 `settings-general.png`、`lifecycle-settings.png`，语言组均在顶部。原离屏入口隔离数据/偏好、不上屏、不抢焦点。
- 截图：`perf/acceptance/l10n/{en,zh-Hans}/`；日志：`build/language-*.log` 与 `build/language-l10n-*.json`。

## 原队列接续项（不能记作已通过）

- functionality、native_ui、recovery 三个原脚本等待同一个验收构建缓存时退出 75。隐私脚本随后完成该缓存构建。按用户要求不自行轮询重试，交原 Chapter 有界自动接续。具体命令：

```sh
cd /Users/tianli/Apps/clip/mac && bash scripts/accept/functionality.sh
cd /Users/tianli/Apps/clip/mac && bash scripts/accept/native_ui.sh
cd /Users/tianli/Apps/clip/mac && bash scripts/accept/recovery.sh
```

- `chapter sop accept --app clipbook --check product_basics --json`：返回契约阻断，原因为 TestFlight 装机与开发回执不能混用、装机可执行/版本/图标与 receipt 不符（详情 `build/language-product-basics.json`）。需原队列提供唯一当前源码候选及匹配回执；不以旧装机冒充本轮结果。
- 装机策略现场核验：`chapter local-install check --app clipbook --direct --json` 返回 `testflight_only`，明确禁止 Developer ID 直装。按任务例外跳过装机，未触碰 TestFlight 上传/商店目标。实际 `/Applications/Clip.app` 仍为 TestFlight 1.2.1 (1)，候选不是已装版。
- 本轮仅本地提交，不推送。未调用会间接推送的发行入口；后续推送仍归 Chapter，先过 Xcode Cloud 闸。
