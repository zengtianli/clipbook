# native_ui 签名前提受阻 · 2026-10-17

## 本轮签名前提修复与装机复验

本轮 owner：Chapter `--pid 52030 --session chapter-task:090857d57de54a07a9141b551d719110`，写前沿原身份 check，不另开同范围声明、不释放原声明。源码写入仅 `cloud-project.yml` 的 `PROVISIONING_PROFILE_SPECIFIER`；交接写入本节；原脚本生成 build/、perf/build-receipt.json 与 native_ui、product_basics 验收产物。其他会话的 project.yaml、perf 差异、暂存及后台保持。

共享资源：Mini 登录钥匙串（只读身份）、ASC 中本 bundle 的 MAC_APP_DIRECT 描述文件、本机 Xcode profile 目录、既有 sim_lane.BuildSlot、/Applications/Clip.app 与原备份目录。构建用现有 BuildSlot，不加重构建全局锁；无模拟器或性能测量。有限阶段为一次签名前提修复、原入口构建装机、两项固定复验和本地提交；75 交原队列有界接续。完成须回读实际已装包、来源与两项真实验收；公开仓只本地提交，未推送按本轮完成谓词记 blocked，不伪报 done。

2026-10-17 现场核 `security find-identity -v -p codesigning`，Mini 有效 Developer ID 指纹为 `72F835AA663461521834BFF102A4C16A52892F9C`。经共享 ios/asc.py 凭据入口创建并 GET 回读 `Clip Developer ID 72F835AA`（API id `8FBVYJ2MQB`，UUID `c0cf62b9-1075-47b9-aa14-10b428c6b0a2`），包含该证书，MAC_APP_DIRECT / ACTIVE / Production / ProvisionsAllDevices=true / 无设备清单，原 Team 与 CloudKit 容器保持。旧 `Clip Developer ID` 未撤销、删除或替换；新名称防止影响旧消费者。正常构建仍只读获取 profile，不新增自动账号写逻辑。

仓库现场为 PUBLIC，起点 HEAD `7c3affd`，领先 origin/main 8 个提交；没有他人暂存。推前只读探针返回 push_allowed=true、workflow 全部手动；本轮仍遵守公开仓仅本地提交授权，不执行 push、公证、更新源或审核提交。

新 profile 的实际 iCloud services 为 Apple 通配值 `"*"`，原预检错误拒绝此值。必要范围补充 `scripts/developer-id-profile.py` 的服务授权类型识别与 `tests/test_developer_id_profile.py` 的边界回归：接受通配值或明确含 CloudKit 的数组，仍拒绝缺失、其他服务、任意字符串和字典；不放宽证书、Team、容器、Production 或设备约束。

结果：

- 本机获取后 `scripts/developer-id-profile.py --check` 退出 0，source=installed、signing_identity=72F835AA…、UUID 与 ASC 回读一致。
- `/Users/tianli/Dev/.venv/bin/python -m pytest -n auto tests/test_developer_id_profile.py tests/test_build_cloud.py tests/test_product_basics.py -q`：37 passed，退出 0。
- 原 `scripts/install-local.py` 退出 0，实际安装 `/Applications/Clip.app` 为 **1.2.1 (138)**；包内 `clip version --json`、深验签和 Chapter `verify_build_receipt` 均通过。来源提交 `17c1d1d039093b2b96c6a69c03faaa1014a38a28`，源码摘要 `9842cae01180510713837b581ecd3dc608578f2950268950a885a25bede62aa5`，已装可执行 SHA256 `b75602045b3ed4fa8dabbea3e324d0666c341f17a7b60d2c5ba707b410f8f69c`。原始来源回执 `perf/build-receipt.json`（同时保留构建原件 `build/accept/local-install.json`），编译日志 `build/local-install-xcodebuild.log`。原安装备份 `/Users/tianli/.Trash/clip-pre-icloud-20261017-135520/Clip.app`。原 PID 3064 的日常实例未重启；已装文件版本与原在途实例分开，不声称后者已加载新版。
- 原 `chapter sop accept --app clipbook --check native_ui --check product_basics --json` 退出 0，input_stable 均为 true。native_ui **26/26**，记录 `perf/acceptance/run-mjuql7iz/native_ui.json`；product_basics **22/22**，phase=installed、build_current=true，记录 `perf/acceptance/run-sstqrick/product_basics.json`。基础功能 raw 原件 `perf/acceptance/product-basics-73f8e63d940249b99e5c29b452dc8c6c/raw.json`，SHA256 `42ac58b29283fc91eed9824c48f8625ce1006dd5bdc64106ff934788d41a9fa6`。native_ui 是原入口单独编译的当前源码离屏包（SHA256 `d8b69f218ef2975bc1af7ec41b9c4e57ddc8e770fcfc3eddd2dab2fee6ffcc45`）；没有把它称为已装包。
- 已查看 native_ui 的 main/settings 离屏截图，布局与内容非空；选中材质的黑块是原验收明确列出的 cacheDisplay 限制。未验证真人键鼠、上屏激活或 Apple 跨设备 iCloud 传输；iCloud 基础验收是隔离本机链路。未改用户默认快捷键、偏好和通用剪贴板；未提交审核、公证或分发。

源码本地提交 `1615253`、`17c1d1d`；本次只提交本轮源码、测试、本节及真实构建回执，其他会话已脏的 perf 最新索引和 project.yaml 不纳入提交。新验收由 Chapter 自动记录，未手写通过证据。

最终状态 **blocked**：技术修复、已装版与两项复验通过，但 PUBLIC 仓本轮只授权本地提交，未满足“本轮提交已推送、分支不领先”的完成谓词。远端 main 回读仍为 `de098c4f84b1a7a2ca67e65025fb522760ef144e`；本轮不擅自推送，也不报 done。Xcode Cloud 现场前提为 ok / push_allowed=true，不把它误记为 unmet。

接手（仅在另获公开仓推送授权后）：先 `cd /Users/tianli/Apps/clip/mac && chapter xcode-cloud status --repo . --json`；读取本仓 push_allowed，仅 true 或统一规则允许的 unknown 才执行 `git log --oneline '@{u}..HEAD'` 审阅全部领先提交，再 `git push origin main && git rev-list '@{u}..HEAD' && git status -sb && git ls-remote origin refs/heads/main`。若 push_allowed=false，保持原队列 waiting_prerequisite，附探针实际 fix，不推送。

## 前轮只读排查（原记录）

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
