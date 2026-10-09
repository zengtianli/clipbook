# Clip 官网校验文件修复 · 2026-10-10

本轮从 2026-10-09 延续，范围固定为：正式重建既有 1.2.1 (78) 本地发行包的站点；修正下载校验文件、窄屏首屏按钮换行和页面/分享正式标题；经 Lintel 单产品发布并回读正式 HTTPS。只提交本轮文件，不 push、不重出 App 包、不改其他会话的 Sources/Shared、project.yaml 或验收记录。

执行机：TianliMac-Mini。复用 Chapter 声明身份 `--pid 63515 --session chapter-task:a0b12a923f094a0e9a10452847f23369`，每次写前 check；不释放声明。入场站点源码干净，仓库有他人的 perf/project.yaml 改动。2026-10-10 开始落实；总预算 30 分钟，阶段为证据准备、正式构建及自洽检查、Lintel 发布、线上回读与限定提交。

已核：Lintel `apps` 原持续网站授权签名有效；当前执行机到 VPS 的只读 SSH 连接成功。发行文件 `Clip-1.2.1-local-arm64.zip`，release.json 登记 SHA256 `0257b371e5da46adf85111d687643a50f2605ad9e9485c2d7d962f6f7c147d47`，source_commit `37dae7a7daf323c0579ebb0a1b946ad93acad067`。站点构建入口为 project.yaml 的 `~/Dev/.venv/bin/python scripts/build-site.py`。

正式构建直接执行登记原命令，退出 0。起初按旧 handoff 排查 `--keep-history --history-tests`，但现有 recording.json 和 ai-sample/manifest.json 均已在原版登记 1.2.1 的复核及逐文件媒体 SHA；脚本的普通正式构建接受这些证据，不需要上述选项。未创建或改写测试证明，未降低脚本检查，未手改 site-manifest.json。构建后的清单逐文件 SHA 与实际目录完全一致（23 个文件，不含清单本身），下载 ZIP 与 release.json SHA 一致，SHA256SUMS.txt 为同一 1.2.1 下载包的一行。页面及 og:title 均为“Clip · 剪贴板”，`.actions` 的 flex-wrap 为 wrap。

仓外发布工作目录：`/private/tmp/clipbook-site-20261010-a0b12a9`。进展和最终结果在本文件续写。

第一次 Lintel ship：规范检查零错误，取证 6 页、播放 5 视频；review 阶段退出 1，提示预览计划过期。逐字段重算比对只有 Lintel 控制器 `engine/web_control.py` 的 SHA 在并发会话中由 `530306a6…` 变成 `1bcb8a22…`，本轮站点输入和产物未变。发布阶段未执行；失败后分别读正式 HTTPS 与 VPS 原目录校验行，均仍为 1.2.0 的 `d66f928d…`。不改 Lintel 源码；控制器已变化，保留首轮证据，按现行入口有界重试一次。

## 最终上线结果

2026-10-10 00:07（上海），重试完成，退出 0：`ok/shipped/published/verified = true`，源站核验成功，HTTPS 无不一致。调用命令为：

```sh
cd /Users/tianli/Apps/clip/mac
/Users/tianli/Dev/.venv/bin/python /Users/tianli/Apps/lintel/engine/lintel.py site ship --site apps --product clipbook --work /private/tmp/clipbook-site-20261010-a0b12a9/retry --json
```

Lintel 按既有产品族映射自动审查并发布 clipbook / clip-ios 的 35 个文件，检查 6 页、实播 5 视频；两条旧入口 `p/clipbook.html` / `p/clip-ios.html` 回读也一致。未编辑 iOS 文件。正式包仍是原来的 1.2.1 (78)，未构建、重新打包或安装 App。

独立 curl 回读正式 HTTPS（00:07:12）后，校验文件、release.json、首页、style.css、实际下载 ZIP 均逐字节等于本轮正式 build/site；VPS 原目录也读到相同校验行：

```text
0257b371e5da46adf85111d687643a50f2605ad9e9485c2d7d962f6f7c147d47  Clip-1.2.1-local-arm64.zip
```

首页和 og:title 为正式名“Clip · 剪贴板”。窄屏离屏截图实看确认首屏第三个入口换行；线上 CSS 包含 `.actions{flex-wrap:wrap}`。媒体沿用原复核素材及版本说明，未把它们宣称为新版新录。

原始回执保存于 [首轮失败回执](site-checksums-20261010/first-ship.json) 和 [正式发布回执](site-checksums-20261010/published-ship.json)。完整计划、桌面/窄屏截图和播放证据仍在上述仓外 retry 目录。web 抓取工具无法访问此链接，urllib 默认请求被拒；正式验证使用原发布器和 curl 的实际 HTTPS 字节，不以这两个工具的失败判断线上内容。

交付前执行 `app_sop.py run --app clipbook --stage promo --check-only --now --json`，退出 0，无自动动作：官网、卡片、两处图标和命名通过，媒体显示 1.2.1 (78) 沿用已标注录像；README 未推送及其他阶段输入已变化仍按原事实保留。原回执见 [推广阶段只读复检](site-checksums-20261010/promo-sop.json)。这些旧缺项不在本轮官网修复范围内，没有重跑 App 构建、性能或装机。

收尾仅提交 `site/index.html`、`site/style.css`、本交接和本轮原始回执；不 push。其他会话的 project.yaml、perf 和其余未提交文件保持原状，Chapter 声明仍由 Chapter 持有，本轮不释放。三项本轮目标均已完成。
