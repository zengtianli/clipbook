# 本轮性能输入绑定核验 · 2026-10-17

## 范围、身份与完成条件

本轮只处理固定失败项 `perf / input-binding`。原日志为 `/Users/tianli/Library/Application Support/app-sop/workbench/logs/0b2beb50b7b54c8d9f8e6a25e1c8b797.log`；其中测量在装机来源核验处跳过，未进入实际性能采样。

复用派出者精确身份 `--pid 48107 --session chapter-task:200d788f0e004c9bbaae6df0cba8c68c`，写入前已用 `claims.py check` 核对本文件；不另开、不释放 Chapter 原声明。

排查块限定为 `project.yaml` 的 `sop.source`、`perf/build-receipt.json` 与 `perf/lightweight.json` 的绑定关系，以及 Chapter 原核验器的只读判定；实际写入仅本交接。未发现本产品实现或验收脚本有可修复的误判，不为消除失败修改生产输入分类或回执。

共享资源只读取装机包、签名和来源文件；不构建、不占构建槽、不启动模拟器、不进入性能安静门、不启动本人 App，不改数据、偏好、剪贴板、账号授权或后台。保留其他会话的 `project.yaml`、`perf/`、文档与暂存。

本轮完成条件为核清真实原因并本地提交准确交接；`input-binding` 通过仍须有效来源的真实构建及原固定脚本产生新实测，不能将本交接称为修复通过。当前授权禁止推送、发版、装机、部署和改授权。

## 实际只读结果

通过 Chapter 原 `load_apps('clipbook')`、`acceptance_code_environment`、`verify_build_receipt` 和 `artifact_snapshot` 核验，无产品启动或正式验收证据写入：

- `SOP_CODE_BINDING_SHA256=bb262c20f7d6303330d08648053c75c720b5efc34bcdfe8364942d32f3fd7f92`，`SOP_BUILD_CURRENT=0`。
- 普通 verifier 返回 `false / 当前构建输入与装机来源不同`；`code_only=True` 返回 `false / 构建 receipt 未完整覆盖 Chapter 的生产源码集合`。因此不是仅由 Tests、验收脚本、handoffs 或 perf 文件变化引起的失效。
- 装机实际原件为 `/Applications/Clip.app`，版本 `1.2.1 (124)`，主程序 SHA256 为 `8c52b4d6773b7dc2308739a488c2d79e35a27de51072b95f618e3e771580201b`，身份、版本、可执行文件及图标与 `perf/build-receipt.json` 完全一致。
- 原回执构建于 `2026-10-15T01:55:30+08:00`，来源提交 `73a58be99d310ad63fb25f1b4337a39ad42e2576`。用 Chapter 原生产分类比较，已有生产输入 `build-cloud.sh` 的内容已变化，回执还缺少 `release-local.sh`、`scripts/install-cli.py`、`scripts/package-local.py`。不能手补哈希来冒充真实构建。
- `/usr/bin/codesign --verify --deep --strict /Applications/Clip.app` 退出 0；签名详情为 Developer ID Application、Team `B9LJH93LA4`、hardened runtime、时间戳 `2026-10-15 01:55:15`，并显示 stapled notarization ticket。本轮只核签名，没有将其等同于当前源码来源匹配。
- `perf/lightweight.json` 的实际测量日期仍为 `2026-10-06`，版本 `1.2.1 (78)`，被测主程序 SHA256 为 `3ac16dba30a36fa81a34505c861d3c97b1b42f20b5d900c411948909a9b34c77`，与当前装机原件不同。

没有实现改动，未新增或重跑不相关回归；未运行会采样或改写正式证据的 SOP run/accept/measure，未写 perf 通过记录。固定脚本最终复验仍由原 jobs 队列执行；原输入与装机未变化前，复验应继续如实保留未通过。

## 受阻与接续

本轮不能解除真实生产输入和装机来源不一致：必须先沿原入口完成包含当前完整生产输入的真实构建回执及装机，再由原性能脚本复测；装机不在本轮授权内。这里只交接本项依赖，不追加其他产品欠项，也不改测量标准。

用户 cd 进入本仓后，需要交给 Chapter 独立装机阶段时可用以下现有 CLI；本轮没有执行该派单，不另建复验队列：

```sh
chapter agent-send --app clipbook --task install --message '仅解除性能输入绑定的装机来源阻塞：沿既有构建与装机入口，以当前完整生产输入生成真实构建回执并核验装机来源和发行签名；完成后让原 jobs 固定性能任务复验。保留本人数据、快捷键和其他会话改动；不推送、不发版、不部署、不改账号授权；前提缺失时如实报告，不补写通过。定位见 handoffs/input-binding-20261017.md。'
```

构建、装机及后续性能采样由 Chapter 原阶段管理；不以本轮文档提交、旧实测日期或已装包签名有效替代来源绑定与实际测量通过。
