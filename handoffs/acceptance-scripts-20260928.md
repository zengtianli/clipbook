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

## 第四轮（同日）
- 待办只剩 perf：实测版本还是 1.1.1 (48)，当前是 1.1.2 (59)。开工时回读：接着交流电，但 HID 空闲 0 秒（用户正在用），loadavg 7.6/14.9/81.5，过不了空闲门。`app_sop.py run --stage perf` 连试 5 分钟都拿不到锁，每次返回 busy（其他产品的 app_sop 正在运行），没有采样。
- 等空闲后由 Chapter 自动补测。补测后按第三轮的顺序接手：build-site，然后 products-only 部署，再回读线上 release.json。

## 第五轮（2026-09-29 01:00）
- 仍然只有 perf 未完成。`app_sop.py run --stage perf` 拿到了锁，但空闲门（steady）没放行：接着交流电，但 15 分钟内 HID 空闲最多约 330 秒，门槛是 600 秒，1 分钟负载 13.7 到 17.9。没有采样，等 Chapter 在条件满足时自动补测。补测后按第三轮的顺序接手：build-site，然后 products-only 部署，再回读 release.json。

## 第六轮（2026-09-29 05:00，perf 补测 + 发版上线）
- 空闲门放行（空闲超过 3 小时、接交流电、负载降到 6.8）后跑了 `run --stage perf`。1.1.2 (59) 已实测：安装后 2.43 MB，空闲内存 53–55.6 MB，CPU 0.07%，速度 474 ms。结果在 perf/lightweight.json（4c3d018）。README 数字由 app_sop 自动更新（b80472b）。
- 当时 GitHub 的 TLS 和 VPS 的 SSH 都间歇超时：第一次推送失败；第一次产品页部署在备份这一步就断了（日志里没有触发回滚，线上未改）。网络恢复后重新推送成功，远端 HEAD 为 b80472b。之后又跑了一次 `run --stage promo --stage perf --retry --now`，目录门户和产品页都部署完成。
- 线上回读：https://app-mac-clips.tianli.cyou/release.json 显示 1.1.2 build 59，sha a7a98436，对应 3a9f0aa；下载 zip 为 200，1839509 字节。homepage_desktop 和 homepage_mobile 已重跑 accept，都通过。
- 最后的 check-only 没有剩余问题，machine_state 为 current_passed。仍待本人在 Chapter 里确认装机图标。
