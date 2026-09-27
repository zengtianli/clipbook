# Chapter 固定验收脚本 · 2026-09-28

## 结果
- `project.yaml` 的 `sop.accept` 登记了 functionality / recovery / privacy / native_ui 四项，命令都是 `bash scripts/accept/<名>.sh`。
- `~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app clipbook --check functionality --check recovery --check privacy --check native_ui --json` 退出码为 0，四项结果都是 passed，证据由 app_sop 写入 `perf/delivery-evidence.json`。
  - functionality：生产 `--selftest` 120 项断言，加上 `tests/test-link-title.sh`。
  - recovery：`--recovery-test` 18 项，覆盖重开、WAL、blob 丢失、库损坏、Deck 源缺失、链接不可达、淘汰后无孤儿 blob。
  - privacy：`--privacy-test` 17 项，外加 6 项构建静态检查：签名 entitlements 只含 iCloud、只链系统库、无权限用途串、网络 API 只在 LinkTitle/MacClipSync、ephemeral 会话、二进制里没有第三方 URL。
  - native_ui：`--ui-self-test` 26 项。离屏渲染真实的 MainView/SettingsView，直接调用模型动作，截图存 `perf/acceptance/native_ui/`。
- 各入口用到的内容都是隔离的：`CLIPBOOK_HOME`、`CLIPBOOK_PREFERENCES_SUITE`、`CLIPBOOK_BACKGROUND=1`、命名 pasteboard。activation policy 设为 `.prohibited`，不建状态栏，不上屏，不激活，也不合成输入。缺少隔离环境变量时，入口 exit 2。

## 机制
- `scripts/accept/_build.sh`：多个验收并行运行，共用一把锁，只构建一次。用 `build-cloud.sh --build-only` 构建，DerivedData 在 `build/.dd-accept`，构建过程里会跑 `--selftest` 门。输入哈希没变时跳过构建。这个脚本从不装机。
- 各入口的检查名和 not_covered 写在 `perf/acceptance/<名>.detail.json`。

## 顺带修复
- 23e458a 把 `display_name` 改成了 `Clip · 剪贴板`，而 `build-cloud.sh` 拿 display_name 去核对 `CFBundleDisplayName=Clip`，导致 build.sh 和装机都失败。现在改为优先用 `name_en` 核对。`scripts/package-local.py` 的 bundle 名也同步改用 `name_en`。

## 未做（边界）
- 4 个本地提交领先 origin/main：23e458a、7c7dfb4、07c473e、8e10aaa，加上本轮新提交。按边界不推送。
- build-receipt 与装机来源不一致：`/Applications/Clip.app` 仍是 build 48（commit 2c18539）。需要 `./build.sh` 装机后执行 `app_sop.py build-receipt`，按边界本轮没做。
- installed_icon 由本人在 Chapter 确认。

## 第二轮（同日）
- Chapter 复检：没有待修的验收脚本（media_playback 已重新通过，其余证据仍有效）。剩下的 readme 未推送、build-receipt 两项分别要 push 和装机，按边界没做，也没有派子 agent。
- 发版决定（1.1.1 (48) 之后有源码改动）留给本人。装机后可按 `release-local.sh` 的既有流程出本地包。
