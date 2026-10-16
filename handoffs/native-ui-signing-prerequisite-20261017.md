# native_ui 签名前提受阻 · 2026-10-17

本轮仅接续 `delivery-native_ui`，复用 Chapter 的精确身份 `--pid 24643 --session chapter-task:bbb3eb5e08fe4f3894a31dd16132c2a3`；不另开或释放声明。

## 范围、资源与完成条件

- 排查块：`scripts/accept/native_ui.sh` → `scripts/accept/_build.sh` → `build-cloud.sh` → `scripts/developer-id-profile.py` 的失败链；只针对原退出 4，不追加其他产品欠项。
- 实际写入：只有本文件；未发现本仓实现或验收脚本需要再修的缺陷，不为消除失败改写验收合同。
- 共享资源：仅本机钥匙串/profile 与 ASC `/profiles` 的只读查询；未使用构建槽、模拟器、性能安静门，未创建 GUI 实例，未触碰本人数据、偏好、剪贴板、后台或其他会话暂存。
- 本轮可完成条件：核清原始错误与当前签名前提，留下准确接续命令并本地提交；固定 native_ui 的通过仍须由原脚本执行，最终复验交 jobs。
- 当前边界禁止改授权、推送、发版、装机或部署，不能在本轮创建或重发开发者账号描述文件。

## 原件与现场核验

原日志：`/Users/tianli/Library/Application Support/app-sop/workbench/logs/a7b80c5ff6f540e6b80e6f4f1865164f.log`；实际命令日志：`perf/acceptance/run-cuih646k/native_ui.log`。

原命令在构建前返回 `signing_profile_unavailable` / 退出 4，尚未进入编译、生产 `--selftest` 或 `--ui-self-test`；不是已经执行后的 UI 断言失败。

本轮真实执行 `/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check`，仍退出 4，结构化错误为：

```json
{"error":"signing_profile_unavailable","profile":"Clip Developer ID","bundle_id":"cyou.tianli.clipbook","signing_identities":["72F835AA663461521834BFF102A4C16A52892F9C"],"detail":"No compatible all-device Production profile includes a valid local signing certificate; account profiles were not changed"}
```

随后通过现有 `asc.get('/profiles', {'filter[profileType]': 'MAC_APP_DIRECT', 'limit': 200})` 只读枚举账号候选，并用系统 `security cms -D` 解码比较；没有后续分页：

- 本机有效 Developer ID 签名身份：`72F835AA663461521834BFF102A4C16A52892F9C`。
- 本机和账号中同名 profile 均为 UUID `51f6ff8d-1c77-4799-a8de-40816f8f350c`，其中证书只有 `A0F5AE165F8F84EDC1787ACCE21E2F7551B7830A`。
- 账号 profile 为 ACTIVE，`ProvisionsAllDevices=true`，没有设备清单；但不包含当前本机证书，生产函数 `usable(...)` 返回 false。
- API 查询成功，不把证书/profile 不匹配误报为 Apple 账号未登录、协议未接受或接口权限不足。

现有提交 `c24a56c` 已修正 profile 证书匹配、只读获取及精确签名参数，当前拒绝是正确的。改成不带发行签名的验收包、跳过预检、改报 75 或补写通过证据，都不能补齐缺失的描述文件；本轮未采用。

## 验证边界与接续

本轮没有修改实现或测试，未重复此前输入未变的回归；未重跑已知同因必败的构建或固定验收，未手写通过证据。native_ui 仍为未通过，不能把本交接的本地提交称为修复通过。原 perf、project.yaml、其他文档及暂存均保留。

解除条件：另行授权 Clip 签名前提维护任务，在现有开发者账号为 `cyou.tianli.clipbook` 提供包含上述本机 Developer ID 证书的 `MAC_APP_DIRECT`、Production、all-devices 描述文件，保持原 Team、CloudKit 容器与签名等级；优先复用兼容文件，不撤销或删除旧证书/profile，不修改账号权限。本轮不执行这些写操作。

用户 cd 进入本仓后的接手命令（第一条验证前提，成功后才执行第二条；正常由原 jobs 自动复验，无需另建队列）：

```sh
/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check
/Users/tianli/Dev/.venv/bin/python /Users/tianli/Apps/chapter/engine/app_sop.py accept --app clipbook --check native_ui --json
```

若尚未补齐 profile，第一条会继续准确退出 4；脚本没有安全的本地重试修复方式。该阻塞属于 Clip 的签名前提，不涉及其他产品或 Chapter 实现。
