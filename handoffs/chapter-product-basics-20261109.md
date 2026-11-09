# Chapter product_basics 修复（2026-11-09）

本轮范围：Mac `Sources/Native/ProductBasicsSelfTest.swift` 的更新检查断言、`tests/test_product_basics.py` 隔离夹具与本交接，按需保留 Chapter 原验收生成证据。不改共享源、Chapter、登记、版本或用户设置，不发行、不推送、不装机。沿派出身份 pid 5143 / chapter-task:83694ea8748549779dcd95eb4f8a2d10 核写权，不释放声明。

原失败：`perf/acceptance/product-basics-a5936f761e1e466ba58c4ddfd90ab213/raw.json`。22 项中仅 `updates.check_result` 失败，并导致 `settings.process_exit_success` 连带失败。共享窗口已本地化为英文/中文，产品验收仍硬编码查找中文“有新版 99.0”；实际更新源、恢复、数据保持及其它项目已通过。

修复：原真实离屏更新检查依次使用共享引擎已有语言覆盖入口执行英文和中文两次，分别确认真实版本 99.0 / 构建 999 的可用更新状态；同时保留 CLI 结构化结果断言。结束恢复原语言环境，并输出每种语言结果以便定位。回归就在实际候选包中执行，不以源码文本断言替代。

完成条件：原 `chapter sop accept --app clipbook --check product_basics --json` 取得真实通过结果；回读 22 项与候选来源；只提交本轮路径。候选验证不声称已装机，iCloud 仅隔离本机配置链路。验证结果待补。

定向测试同时发现原夹具只替换 `Path()`，但脚本已提前把安装路径保存为 `INSTALLED`，两项测试因此误读真正安装包后被来源检查拒绝。改为直接替换 `INSTALLED`，并清除继承的 Chapter 候选参数，保持测试完全隔离。
