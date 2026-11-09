# Chapter product_basics 修复（2026-11-09）

本轮范围：Mac `Sources/Native/ProductBasicsSelfTest.swift` 的更新检查断言、`tests/test_product_basics.py` 隔离夹具与本交接，按需保留 Chapter 原验收生成证据。不改共享源、Chapter、登记、版本或用户设置，不发行、不推送、不装机。沿派出身份 pid 5143 / chapter-task:83694ea8748549779dcd95eb4f8a2d10 核写权，不释放声明。

原失败：`perf/acceptance/product-basics-a5936f761e1e466ba58c4ddfd90ab213/raw.json`。22 项中仅 `updates.check_result` 失败，并导致 `settings.process_exit_success` 连带失败。共享窗口已本地化为英文/中文，产品验收仍硬编码查找中文“有新版 99.0”；实际更新源、恢复、数据保持及其它项目已通过。

修复：原真实离屏更新检查依次使用共享引擎已有语言覆盖入口执行英文和中文两次，分别确认真实版本 99.0 / 构建 999 的可用更新状态；同时保留 CLI 结构化结果断言。结束恢复原语言环境，并输出每种语言结果以便定位。回归就在实际候选包中执行，不以源码文本断言替代。

完成条件：原 `chapter sop accept --app clipbook --check product_basics --json` 取得真实通过结果；回读 22 项与候选来源；只提交本轮路径。候选验证不声称已装机，iCloud 仅隔离本机配置链路。

定向测试同时发现原夹具只替换 `Path()`，但脚本已提前把安装路径保存为 `INSTALLED`，两项测试因此误读真正安装包后被来源检查拒绝。改为直接替换 `INSTALLED`，并清除继承的 Chapter 候选参数，保持测试完全隔离。

## 最终验证

- `python -m pytest -n auto tests/test_product_basics.py -q`：12 passed；`git diff --check` 通过。
- `chapter sop accept --app clipbook --check product_basics --json`：退出 0，passed，22/22，input_stable=true。settings、shortcuts、icloud、updates 四组全部 passed；真实更新窗口 `en=true` / `zh-Hans=true`，CLI 正确读回 99.0 / 999 可用更新。
- 候选构建使用原 `sim_lane.BuildSlot`；Xcode BUILD SUCCEEDED、生产 selftest 全通过、Developer ID 验签通过。此次没有副本构建错误，不改构建脚本，也不改 Chapter。
- 真实候选 `/Users/tianli/Apps/clip/mac/build/candidate/Clipbook.app`，版本 1.2.1、构建 163（原脚本按提交数生成），来源 `570f5944bbbcfa1044fb96b9657103f1dd6d9fd3`；主程序 SHA256 `5077b254c0974eac354fbffceaaf117181584e3d319d05c6833c3043623dcb0b`。
- 原 Chapter 结果 `perf/acceptance/run-ms5epw7_/product_basics.json`；原始检查 `perf/acceptance/product-basics-9aee93ea3d95493fb92a89c1cad9020f/raw.json`，同目录 process.log 包含两种语言的真实结果；来源回执 `build/accept/candidate-receipt.json`。
- 原件 owner_before / owner_after 完全相同：已装主程序与用户偏好没有变化；本轮不安装，不声称候选为已装版，不测 Apple 跨设备同步，不需要用户动作，无阻塞。

## 并行改动与提交

复用 Chapter 原声明，路径检查均退出 0；没有另开/释放声明。提交 `570f594` 的 `git show -U0` 已核对，仅含本轮三个文件的改动；此处同时通知派出者，未含其他会话内容。

开工时已有 `perf/acceptance/product_basics.json`、`.log`、`.detail.json`、`perf/build-receipt.json`、`perf/delivery-evidence.json` 未提交内容，原字节保存在持久目录 `build/accept/before-chapter-83694ea8/`。Chapter 重跑自动更新的默认索引留在工作区；`perf/build-receipt.json` 与备份逐字节一致。为不混入他人原差异，最终只提交本轮独立 run/raw/process 证据、候选回执与交接，默认 perf 文件仍不暂存。没有推送、发行或终止他人后台。
