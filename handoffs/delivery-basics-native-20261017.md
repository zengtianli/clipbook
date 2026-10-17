# 两项固定交付失败核验 · 2026-10-17

本轮仅处理 `delivery-product_basics`、`delivery-native_ui`，复用 Chapter 精确身份 `--pid 96860 --session chapter-task:1c6d199849b4434fb6be5a97b7879ddb`；写入前已用此身份对本文件执行 `claims.py check`，退出 0，不另建或释放声明。

## 范围、资源与完成条件

- 排查块限定为 `scripts/accept/product_basics.py` 的生产来源和实际产物核验、`scripts/accept/native_ui.sh` → `_build.sh` → `build-cloud.sh` → `scripts/developer-id-profile.py` 的退出 4，以及直接相关回归和原交接。
- 实际修改只有本交接。已有 `a353d86` 的 Chapter 生产绑定、`c24a56c` 的证书匹配及共享 BuildSlot 修复仍适用；未发现可在本轮边界内继续修复的实现或验收脚本缺陷。
- 共享资源仅作装机文件、钥匙串/profile 和 ASC GET 的只读查询；不构建、不占构建/模拟器/性能槽，不启动本人 App，不改数据、偏好、剪贴板、账号/profile、其他会话改动、暂存和后台作业。
- 本轮完成条件：核清两项原失败及当前状态，提交准确 handoff；两项验收通过仍须固定脚本产生真实证据，原 jobs 队列负责复验。本轮禁止推送、发版、装机、部署和改授权，不补写或改写 perf/receipt 通过记录。

## 原件与当前只读结果

基础功能原日志为 `/Users/tianli/Library/Application Support/app-sop/workbench/logs/52c08a494614416da879e7a230489cd4.log`，对应 `perf/acceptance/run-1xu0i17i/product_basics.{log,json}`；原生界面原日志为 `/Users/tianli/Library/Application Support/app-sop/workbench/logs/9a772fcd610f45ee82c59dabf3eef2f4.log`，对应 `perf/acceptance/run-4y8ra3r5/native_ui.{log,json}`。

### 基础功能

原固定命令使用 `build/accept/product-basics-installed.json`。本轮以此精确路径调用 Chapter 原 `verify_build_receipt`，并调用 `acceptance_code_environment`、`artifact_snapshot`，结果为：

- `SOP_CODE_BINDING_SHA256=bb262c20f7d6303330d08648053c75c720b5efc34bcdfe8364942d32f3fd7f92`、`SOP_BUILD_CURRENT=0`。
- `code_only=True` 返回 false / “构建 receipt 未完整覆盖 Chapter 的生产源码集合”；完整核验返回 false / “当前构建输入与装机来源不同”。
- Chapter 原生产分类确认旧回执缺少 `release-local.sh`、`scripts/install-cli.py`、`scripts/package-local.py`，已有生产输入 `build-cloud.sh` 的内容已变化；并非仅因 Tests、验收脚本、handoffs 或 perf 改动失效。
- 实际 `/Applications/Clip.app` 的身份、版本、主程序及图标与上述回执一致，版本 `1.2.1 (124)`，主程序 SHA256 为 `8c52b4d6773b7dc2308739a488c2d79e35a27de51072b95f618e3e771580201b`；`codesign --verify --deep --strict /Applications/Clip.app` 退出 0。

因此生产绑定拒绝是正确结果，原失败尚未执行基础功能夹具；不能忽略真实生产变化或手补构建回执来判通过。解除它需要包含当前完整生产输入的真实构建和装机，装机不在本轮授权内。

### 原生界面

原固定命令在签名前提预检退出 4，尚未进入 SDK 编译、生产 `--selftest` 或 `--ui-self-test`，不是 UI 断言已执行失败。

本轮实际执行 `/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check`，仍退出 4，结构化错误：

```json
{"error":"signing_profile_unavailable","profile":"Clip Developer ID","bundle_id":"cyou.tianli.clipbook","signing_identities":["72F835AA663461521834BFF102A4C16A52892F9C"],"detail":"No compatible all-device Production profile includes a valid local signing certificate; account profiles were not changed"}
```

随后直接调用生产 `fetch(...)`，只经 ASC GET 查询已有候选，返回 `compatible_profile=false`，本机有效签名身份仍为上述指纹。没有创建、重发、缓存、删除或更改任何 profile/证书/账号权限。查询成功，不能据此报告 Apple 账号未登录、协议未接受或其他共享前提 unmet。

缺失签名描述文件属于真实前提，不能改报环境 75，也不能改用无发行签名的包冒充固定验收通过。共享 BuildSlot、锁忙 75 和签名等级规则保持原样。

## 验证边界与接续

本轮无实现或测试改动，不重复此前输入未变且已记录的单元回归，不重跑同因必败的构建或固定验收；未运行会改写正式证据的 app_sop accept/run。原 jobs 在本轮结束后自动复验；当前两项仍未通过，本次本地文档提交不能称为修复通过。

以下为用户 cd 进入本仓后的独立接续入口，本轮没有执行派单，也不创建平行复验队列：

1. 签名前提：另开明确授权的 Clip 任务，提供包含本机 Developer ID 证书的 `MAC_APP_DIRECT` / Production / all-devices 描述文件，保持 Team、容器和发行签名等级，不撤销旧证书/profile，不修改账号权限。可用 `chapter agent-send --app clipbook --message '单独维护 Clip 签名前提：先只读核验并优先复用已有兼容描述文件；确无兼容文件时，授权沿既有开发者账号入口为 cyou.tianli.clipbook 创建包含本机有效 Developer ID 证书的 MAC_APP_DIRECT Production all-devices 描述文件，保持原 Team 和 iCloud 容器，不撤销旧证书或描述文件，不改账号权限，不装机、不推送、不发版、不部署；完成后运行 scripts/developer-id-profile.py --check 回读，交原 jobs 复验 native_ui。定位见 handoffs/delivery-basics-native-20261017.md。'`；前提补齐后，本仓只读检查命令为 `/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check`。
2. 已装来源：签名前提补齐后，可用 `chapter agent-send --app clipbook --task install --message '仅解除 Clip 基础功能的装机来源阻塞：沿既有构建和装机入口，以当前完整生产输入生成真实构建回执并装机，回读来源绑定、实际产物和发行签名，随后交原 jobs 复验 product_basics；保留本人数据、快捷键和其他会话改动，不推送、不发版、不部署、不改账号授权，缺前提如实报告。定位见 handoffs/delivery-basics-native-20261017.md。'`。

上述均为依赖另一个授权阶段的接续，不属于等锁、负载或采样造成的临时 75。本轮不要求用户重复重试相同失败命令，不将当前阻塞转成产品通过。
