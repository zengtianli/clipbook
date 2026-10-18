# Chapter 固定四项失败修复 · 2026-10-18

任务 `b468dc63aa9c41ba832b8c88333d6499`，复用 Chapter 原 claims 身份 `--pid 46182 --session chapter-task:b468dc63aa9c41ba832b8c88333d6499`；每次写前 check，不另建或释放声明。

## 范围与完成条件

仅处理 delivery-functionality、delivery-cli_entry、delivery-agent_cli、delivery-product_basics。实际修改 `scripts/accept/_build.sh`、新增同目录 `prepare_build.py`、`scripts/accept/product_basics.py`、`tests/test_accept_source.py`、`tests/test_product_basics.py` 和本交接。原 project.yaml、perf 证据、其他文档、暂存与后台保持。

共享资源：构建沿 `build-cloud.sh --build-only` 的原 `sim_lane.BuildSlot`，没有外包构建锁、模拟器开机或性能采样；原验收缓存锁只保护本产品缓存。验证用独立目录、数据、偏好和命名剪贴板，不启动或退出本人的 App，不装机、公证、推送、发布、部署或改授权。

完成条件：修正本仓独立工作树下的共享源及路径问题；必要回归与真实隔离功能构建通过后仅本地提交。正式四项复验交原 jobs 队列，不能将本轮隔离功能结果等同于四项全部通过。

## 原件与原因

- functionality：`perf/acceptance/run-bti661ls/functionality.log` 在共享 CodingKeys 检查读取 `Sources/Native/PocketLibrary.swift` 时 FileNotFoundError，尚未编译或运行自检。原工作树此链接正常，实际指向同族 iOS `Shared/ClipLibrary.swift`。Chapter `app_sop.isolated_build` 检出独立 worktree 并提供 `SOP_SOURCE_REPO`，副本旁没有 iOS 仓，原相对链接失效。
- cli_entry：`perf/acceptance/run-fsvu0a08/cli_entry.detail.json`，已装包缺 `Contents/Resources/bin/clip`。
- agent_cli：`perf/acceptance/run-j2no0k3n/agent_cli.detail.json`，同一断链导致 `clip --help` 无法启动。
- product_basics：`perf/acceptance/run-bd4ttaoi/product_basics.log` 和 `perf/acceptance/product-basics-3c46693550be4fdb84f15c20ea4da703/raw.json`，实际包不匹配构建回执，正确拒绝执行夹具。另检查发现该脚本原来按脚本所在 worktree 定位回执和限定输出，但 Chapter 的输出、回执仍在原仓库；该路径缺陷一并修复。

## 实现

`prepare_build.py` 在普通完整检出中直接使用原目录；仅当独立副本的 PocketLibrary 相对链接断开时，在自己的 `build/.accept-source` 生成构建副本。Mac 源码和构建输入取自当前快照，只有链接文字与原仓一致的同族文件读取 `SOP_SOURCE_REPO` 的实际目标；缺失、链接变更或其他坏链接仍失败。原仓及 worktree 的受跟踪文件不改，不退回用实时 Mac 源码替代快照。共享文件的内容参与原缓存 SHA；Chapter 原输入前后核验仍负责外部源码的稳定性。构建产品和日志使用绝对路径，原 BuildSlot、签名及生产自检门保持。

`product_basics.py` 按 Chapter 的 `SOP_SOURCE_REPO` 定位原仓回执和证据根，普通调用仍按本文件路径定位；继续使用 `SOP_CODE_BINDING_SHA256` / `SOP_BUILD_CURRENT`，保留实际包身份、版本、可执行 SHA 和深验签，不补写或放宽回执。

## 验证

- 定向 pytest：`/Users/tianli/Dev/.venv/bin/python -m pytest -n auto tests/test_accept_source.py tests/test-accept-build.py tests/test_product_basics.py -q`，23 项通过；覆盖快照与实时 Mac 源码不同、同族源变化、坏链接拒绝、构建 4/65/75 原码保留、缓存锁不误删。随后把路径断言增强为 worktree 默认回执/证据落在原仓的完整流程，仅重跑受影响的 `tests/test_product_basics.py`，12 项通过；未重复输入未变的其余测试。
- `bash -n scripts/accept/_build.sh scripts/accept/functionality.sh`、`git diff --check` 通过。
- 在 `build/accept/chapter-b468dc63/snapshot` 建独立源码副本，保留相对软链并断言其失效，使用真实 `SOP_SOURCE_REPO` 执行现有 `scripts/accept/functionality.sh`；没有运行 app_sop accept/run 或写正式 perf 结果。实际退出 0，原 `sim_lane.BuildSlot` admitted、`BUILD SUCCEEDED`、Developer ID signed 等级检查通过，生产 selftest 233 项断言通过、包内 clip 隔离入口 52 项通过、链接标题有界抓取通过、通用剪贴板未变。
- 上述脚本原始日志：`build/accept/chapter-b468dc63/functionality.log`，Xcode/签名日志在 `snapshot/build/accept-{build,selftest}.log`；固定功能脚本自动生成的本轮隔离详情为 `build/accept/chapter-b468dc63/evidence/functionality.detail.json`。它不是 Chapter 正式复验记录，不手工写通过。
- 只读签名前提 `scripts/developer-id-profile.py --check` 已成功，本机有匹配 Developer ID 证书的 all-device Production profile；旧交接的签名前提缺失已不适用，不报告 Apple 登录或协议缺失。

## 仍需责任仓接续的三项（owner: chapter）

当前 `/Applications/Clip.app` 实际为 TestFlight 1.2.1 (1)，`ClipDistribution=store`，主程序 SHA256 `dd1eaaf93c8b6006a98349960e5b9afbd3b90c6a0961e310824da92c9e9d4dc7`，深验签成功。Chapter 原 `local_install_check(app)` 返回 `ok=true`、`policy=testflight`、`source=testflight`、唯一安装件；现行政策不允许下载版直装。`store/project.yml` 和 `Sources/ClipbookApp.swift` 的 APP_STORE 分支明确不提供 CLI 或自带更新器，原设计经过见 `handoffs/2026-10-12-mac-app-store.md`。

但 Chapter 当前 `acceptors/cli_entry.py`、`agent_cli.py` 仍消费下载版的 CLI 登记，`acceptance_code_environment` / `verify_build_receipt` 仍用 `perf/build-receipt.json` 的下载版 1.2.1 (138)（主程序 SHA256 `b75602045b3ed4fa8dabbea3e324d0666c341f17a7b60d2c5ba707b410f8f69c`）对照已装商店版；原只读 verifier 返回 false / 装机可执行文件/版本/图标与构建 receipt 不符，`SOP_BUILD_CURRENT=0`。因此其余三项不能在本轮靠修路径消除，也不能给已签名商店包补链、把未证明功能改为 human/通过、伪造来源回执或替换安装渠道。

需 Chapter 责任仓按真实 TestFlight 渠道区分下载版 CLI/自带更新器契约与商店版能力，并接通该渠道真实构建/Apple 回执来源及基础功能验收，不跳过真实产品检查、不擅改安装政策；需要 Clip 补商店专用实现时另派明确范围。固定失败的上述原件和本交接为转交证据。本轮未修改 Chapter 或另发任务。

用户 cd 进本仓后的具体 CLI 接续（由 Chapter 按 owner 自动转交时无需人工重复派单）：

```sh
chapter agent-send --app chapter --message '接续 Clip 的三项固定失败：cli_entry、agent_cli、product_basics。先读 /Users/tianli/Apps/clip/mac/handoffs/chapter-fixed-failures-20261018.md；已装件经原 local_install_check 确认为唯一 TestFlight 1.2.1(1)，不能要求其提供下载版 CLI，也不能用下载版(138)回执冒充商店来源。只修 Chapter 真实渠道的验收适配、回执接线与必要测试；保留真实功能校验，不伪造通过、不改授权、不直装、不发布部署，pytest -n auto 后本地提交，由原 jobs 复验 Clip；如需 Clip 商店专用实现，另交明确范围。'
```

本轮没有用户待决事项；正式四项状态仍以原 jobs 自动复验为准。原 Chapter claims 保留给派出者释放。
