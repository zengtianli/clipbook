# Clipbook Air 签名段 · 2026-10-09

原任务 `20261009-2058-产品欠项接续-clipbook-Air-签名段`，仅接续 Mini 未能签名的部分。不公证、不推送、不发更新渠道、不部署，不使用合成输入，不启动会上屏或进 Dock 的日常实例。

- Air 实读 3 个有效签名身份。以当前工作区与源码提交 `7d61a323390035d2f8663aa20f3609b52cc96159` 构建；没有 reset、checkout 或 stash。
- 通过原 `app_sop.py build-receipt` 包住 `CLIP_DERIVED_DATA=build/.dd-accept ./build.sh`。Xcode 构建沿产品原 sim_lane 准入，32.41 秒完成快装与真实回执。
- 已装 Clip **1.2.1 (108)**，bundle ID `cyou.tianli.clipbook`，CloudKit `Production`。`codesign --verify --deep --strict` 退出 0；签名为 Apple Development，team `B9LJH93LA4`。原安装已由产品入口移至废纸篓。
- 固定验收逐项回读：functionality passed（生产 selftest 233 项、包内 CLI 52 项及链接标题测试）；recovery passed（18 项）；native_ui passed（26 项离屏自检）；privacy failed（`Lifecycle source drift: AppLifecycleUI.swift`）。隐私脚本在共享副本一致性检查处退出，后续隐私断言未执行。
- 产品内共享 UI 副本与总部现行文件不同。此任务限定 Air 签名段，未扩大到共享 UI 升级，不降低检查标准、不改写失败结果。
- 验收包与装机包完整可执行 SHA 不同（分别 `74f112a8677e…`、`522a55a8a57e…`），但 CDHash 同为 `18b504b0c08925f8de4e3df6b6deeeaa087f5fea`；装机二进制、图标、当前源码与真实 receipt 一致。
- Cadence 常规 bundle 同步要求 Developer ID 和公证；此快装包不满足。未 register，未改生产闸或自动同步策略，Mini 安装未发生。
- 单产品 check-only 刷新后，fresh 看板由 **11 项降至 8 项**。functionality、recovery、native_ui、build-receipt、install 已补齐；安装新版同时暴露 perf 与 release 过期。最终 `needs_check / pending_test`，不是产品完整收口。
- 留下的 8 项为 test、perf、input-binding、release、update-feed、delivery-privacy、delivery-cli_entry、delivery-agent_cli。性能和原 CLI 元证据不属于本轮签名接续；发布与更新源被合同禁止。原性能数字、旧回执和其他人的未提交改动保留。

详细报告与命令原件：`~/mac-pair/tasks/sop-clipbook-air-20261009/output/report.md`；独立结果 `~/mac-pair/tasks/sop-clipbook-air-20261009/result.md`。没有需要本人界面操作的阻塞。
