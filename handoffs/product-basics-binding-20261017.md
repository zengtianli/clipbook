# 本轮基础功能验收来源绑定修复

范围：只修 delivery-product_basics；owner 为 Chapter 原派出身份 `--pid 69757 --session chapter-task:671cb7c82a264749a73982025dffb941`。具体可写文件为 `scripts/accept/product_basics.py` 的来源绑定及失败阶段描述、`tests/test_product_basics.py` 的验收边界回归、本交接；写前使用原身份 check，不另建或释放声明。

共享资源：本轮不构建、不申请构建槽、不启动模拟器、不做性能采样、不操作本人 App/偏好/剪贴板，不修改 Chapter、其他工作树改动、暂存或后台。固定正式复验留给原 jobs 队列，验收原件仍由固定脚本产出。

完成条件：改用 Chapter 提供的 `SOP_CODE_BINDING_SHA256` / `SOP_BUILD_CURRENT`，保留实际包身份、版本、主程序 SHA 和深验签；覆盖非生产回执变化可继续、生产绑定缺失/失配拒绝、原件变化/签名失败拒绝、候选与已装判据独立的回归；测试通过后仅本地提交。

原件：`perf/acceptance/run-1gtbhxg1/product_basics.log` 与对应 raw.json。实际包匹配为 true，原脚本自行逐文件比较为 false，自检尚未启动。失败时旧文案把空 binding 称为候选，现于检查开始即标明实际选择阶段。

只读实查：Chapter `acceptance_code_environment` 返回 `SOP_BUILD_CURRENT=0`；原 `verify_build_receipt(..., code_only=True)` 返回“构建 receipt 未完整覆盖 Chapter 的生产源码集合”。旧装机回执缺 `release-local.sh`、`scripts/install-cli.py`、`scripts/package-local.py`，且 `build-cloud.sh` 与原构建不同。因此修复不会绕过生产差异或补写构建回执；当前已装包不能据此判通过，后续由 Chapter 独立构建/装机阶段接续，本轮不执行这些动作。

显式候选仍支持：环境中的已装 verdict 不适用于另一份候选，故仅该分支调用 Chapter 原只读 `verify_build_receipt(..., receipt_path=..., code_only=True)`；不在产品脚本维护第二套生产文件分类。

验证：`/Users/tianli/Dev/.venv/bin/python -m pytest -n auto tests/test_product_basics.py -q` 实际退出 0，11 passed in 0.76s；覆盖非生产回执变化、绑定缺失/非法/生产失配、主程序变化、深验签失败、早期失败的已装阶段描述、显式候选使用原 verifier。测试只写 pytest 临时夹具，不生成正式产品通过记录；未运行无关旧检查。

另以 Chapter 当场生成的真实环境只读调用修复后的两个来源判定分支：已装分支返回 false，候选分支调用原 verifier 返回 false/“构建 receipt 未完整覆盖 Chapter 的生产源码集合”；摘要为 `bb262c20f7d6303330d08648053c75c720b5efc34bcdfe8364942d32f3fd7f92`。这证明真实生产差异仍被拒绝，不将单元回归通过称为产品基础验收通过；固定验收仍由本轮结束后的 jobs 队列自动复验。

接续：若需解除真实装机输入阻塞，由 Chapter 单独执行构建/装机任务；用户在本仓可用 `chapter agent-send --app clipbook --task install --message '仅以当前完整生产输入生成真实构建回执并沿既有入口装机，随后运行 product_basics 固定验收；不推送、不发版、不部署。'` 交回既有入口。不要手改旧回执、忽略生产输入、覆写已装包或在本轮追加安装。

提交范围仅以上三个文件；本轮无推送、发版、装机、部署、授权变更或正式验收证据改写，原 Chapter claims 留待派出者释放。
