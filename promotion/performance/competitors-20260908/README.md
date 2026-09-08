# 竞品实测 · 进行中

用户已要求停止追加测试，本轮收尾。最新状态以 promotion/COMPETITOR-RESULTS.md 为准；下表保留过程范围。

本目录保存 Clip 竞品对比的原始计量、安装来源与方法。安装包和私有运行数据位于本仓 gitignored `build/competitor-benchmark/`，不上传剪贴板数据库或许可证。

## 范围与状态

| 应用 | 版本 | 当前完成 | 仍需完成 |
|---|---|---|---|
| Clip | 1.0 build 26 | 100 文本、20 图片，主窗口和隐藏后的采样 | 响应时间、重复轮次 |
| PastePal | 2.21.1 | 激活后文本、20 图片及隐藏后采样 | 响应时间、重复轮次 |
| Maccy | 2.7.1 | 官方签名安装；文本、20 图片及隐藏后采样 | 响应时间、重复轮次 |
| Paste | 6.6.10 MacKed | 安装包已下载、检验签名和摘要；首次启动未成功 | 恢复安装及成功运行后全套测试 |
| CleanClip | 2.4.7 MacKed | 安装包已下载、检验签名并安装 | 成功运行后全套测试 |
| Deck | 1.4.5 | 临时库补齐 100 文本/20 图片后重启后台采样；原数据已恢复 | 图片面板、响应时间 |

Paste 的 MacKed 页面明确声明没有同步功能，不能当作官方完整版本。PastePal 下载自开发者 GitHub，用户随后完成激活；没有把激活窗口的占用当作工作负载。Maccy 的 MacKed 下载入口重定向至官方 GitHub。其余变体以 installation-manifest.json 的签名和实际文件摘要为准。

来源：https://macked.app/pastepal-crack.html 、https://macked.app/paste-for-mac-crack.html 、https://macked.app/cleanclip-crack.html 、https://macked.app/maccy-clipboard-manage.html 。

## 计量方法及限制

- Apple M4，macOS 27.0。内存为主进程 physical footprint，单位 MiB；RSS 另存，不混用。每个稳定阶段观察 30 秒。
- CPU 是这 30 秒累计用户态与内核态时间差 / 实际墙钟时间，100% 表示一个核心。此机器 proc_pid_rusage 时间值经 mach_timebase_info 的 125/3 比例转换，已和 ps TIME 交叉检查。早期记录转换错误已在 samples.json 校正并标记，未经校正的 build 原片不用于展示。
- 不把应用文件的磁盘体积称为内存。安装签名完整性通过不等于 Apple 信任或公证有效。
- 测试文本为 feed.swift 的 100 条纯虚构字符串，间隔 600ms。PastePal/Maccy 另有少量初次测试记录；Clip 在隔离数据库中预置 100 条。记录数和是否连续录入/重启按 stage 单列，不能称为严格等同的输入与生命周期。
- 测 Clip 使用独立 CLIPBOOK_HOME 和 UserDefaults suite；不清空用户正常历史。对外不使用生产数据截图。
- `initial-state` 和 `main-closed` 是引导/窗口转换观察，不作为稳定后台结论。稳定后台以 `all-panels-hidden` 为准。
- 目前采样为探索性单轮观察，没有证明统计显著性、长期占用或跨机表现；不宣传比竞品快几倍或全面更省资源。
- 未给出毫秒级启动/搜索/粘贴数值。Computer Use 的调用耗时包含自动化开销，不能冒充应用响应延迟。
