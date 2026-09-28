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

## 第三轮（同日，已获装机/发版/推送长期授权）
- 版本升到 1.1.2（commit 3a9f0aa，build 59）。docs/demo 的 recording.json 和 ai-sample/manifest.json 都登记了 reused_for 1.1.2，原因是自 1.1.1 以来 Sources 只加了自检入口，没有改视图。
- `./build.sh` 已把 1.1.2 (59) 装到 /Applications/Clip.app。又用 `app_sop.py build-receipt --artifact /Applications/Clip.app --build-command ./build.sh` 重建一次并写了 receipt，回读已装版本与 receipt 一致。常驻实例在 Chapter 里点重启。
- `bash release-local.sh` 已出本地包：build/local-release/Clip-1.1.2-local-arm64.zip，sha256 a7a98436…f91b。
- **发版页面没部署**：`scripts/build-site.py` 要求 perf/lightweight.json 是当前版本的实测。perf 采样要过空闲/电源门，本轮没法测。接手顺序：
  1. `~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py run --app clipbook --stage perf`，等空闲门放行。
  2. `~/Dev/.venv/bin/python scripts/build-site.py`
  3. `cd ~/Apps/apps-portal/site && bash deploy.sh --products-only clipbook --dry-run`，核对计划后再 `--deploy --plan <plan.json>`。
  4. 回读 https://app-mac-clips.tianli.cyou/release.json。
- 另外，build/local-release/release-notes.md 还是 1.1 build 36 的旧文案，看起来不参与站点构建，需要时手工更新。
- 版本变更后重跑了 accept：functionality、recovery、privacy、native_ui 都通过。media_playback 第一次线上视频 readyState 0，curl 回读 200/206 正常，重试一次通过。
