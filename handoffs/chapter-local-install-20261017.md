# Chapter 本机快装入口 · 2026-10-17

任务身份 `chapter-task:92a358e961b64b13a193a775946ff715`，claims pid `85056`；复用 Chapter 原声明，不另建或释放。

## 本轮范围与完成条件

- 只改本组件 `project.yaml` 的 sop.install、product_basics 回执入口与 source 项；新增 `scripts/install-local.py`、`tests/test_install_local.py` 和本交接。保留原有 project.yaml 的产品描述、全部他人 perf/文档/暂存与后台。
- 入口复用原 `build.sh --build-only`、`build.sh --install-local` 和 Chapter 原 build_receipt / verify_build_receipt。构建占原共享 sim_lane.BuildSlot，不加外层构建锁；不公证、发布、写更新源、改账号或共享实现。
- 完成条件：Chapter 能识别明确的 sop.install；真实构建成功后才安装，真实已装包/版本/源码匹配后才复制原始回执至默认位置；固定验收由 Chapter 生成证据；限定提交。公开仓按本次明确要求仅本地提交，不推送。
- 本轮累计预算 30 分钟；明确签名缺失不循环重试，不把无签名编译包作为可安装产品，不重放输入/原因未变的固定失败。

## 开工回读

- main 起点 `75f23d1`，领先 origin/main 6；暂存区为空。已有 project.yaml 产品摘要/特征 12 行未提交及大批 perf 改动，均属先存内容。
- 实装 `/Applications/Clip.app` 为 1.2.1 (124)，运行实例 PID 3064；正式 receipt 为 2026-10-15 的构建，当前 Chapter 只读核验为装机来源过期。
- GitHub API 回读 `zengtianli/clipbook` 为 PUBLIC，遵守本次第 4 项“公开仓只本地提交”。
- 本机有效 Developer ID 指纹 `72F835AA663461521834BFF102A4C16A52892F9C`，原 `scripts/developer-id-profile.py --check` 实际退出 4 / signing_profile_unavailable，没有包含该证书的兼容 all-device Production profile；不改为 Apple Development/adhoc，不改账号/profile。

## 执行结果

- Chapter 原 `machine_work.rebuilder(app)` 已实际返回 `("~/Dev/.venv/bin/python scripts/install-local.py", "sop.install")`，原先“找不到重建装机入口”已解除。入口先只读核现装来源，已是当前核验构建则直接复用；否则使用独立 `build/local-install` 和专用构建日志，构建成功生成 `build/accept/local-install.json`，实际安装并核验后才将原始回执字节原子复制到 `perf/build-receipt.json`。
- 基础功能登记改为读取默认正式回执，避免后续新装版本仍被旧 `build/accept/product-basics-installed.json` 拦住；完整 sop.source 与 project.yaml 都参与新构建来源，新增两个实际生产脚本也在 source 中，没有缩小判定范围。
- 先提交 `1714b4a` 后，实际执行 project.yaml 登记的原命令，2026-10-17 13:45 返回 4，原因仍为 `signing_profile_unavailable`。原构建脚本本轮经 ASC 只读 GET 也没有取得兼容候选，未进入 SDK 编译、签名、生成新回执或替换 App。原件：`build/local-install-attempt.log`、`build/local-install-attempt.json`。
- 装机前后均为 `/Applications/Clip.app` 1.2.1 (124)，PID 3064；主程序 SHA256 `8c52b4d6773b7dc2308739a488c2d79e35a27de51072b95f618e3e771580201b`，默认回执 SHA256 `badf64a724a70fcc921c1e93a270022ad25fdc48bdc3ad15bb8f16f7a48654c8` 完全相同。没有安装候选冒充已装版，没有退出或重启旧实例，没有写本人数据/偏好/剪贴板、登录项或常驻配置。
- 实际运行 `chapter sop accept --app clipbook --check product_basics --json`，退出 1，原结果 `perf/acceptance/run-4lj1yto0/product_basics.json`。raw 原件为 `perf/acceptance/product-basics-fa8b88432bab4675b161b5196136391b/raw.json`，SHA256 `c39e329df27b2f23a21c6d92ae69f70bf838a4602ac704dc8d147b0ba4dd89eb`；真实 checks 为实际包匹配 true、当前生产输入匹配 false、夹具执行 false、本人状态保留 true，input_stable=true。旧最新记录已由 Chapter 归档到 `perf/acceptance/attempts/product_basics/20261017T134559366795+0800-g9x2kydw`，未手写 perf 证据或提交其先存改动。
- 随后只读 `verify-build-receipt --app clipbook --artifact /Applications/Clip.app --json` 退出 1，仍为“当前构建输入与装机来源不同”。functionality/recovery/privacy/native_ui 共用的签名前提未变；media_playback 的页面/视频输入和 Chapter 播放分类代码也未变，按“不重复同因失败”不重放。当前版本未装好，故不运行以新装成功为前提的 installed_icon。
- 首轮 `pytest -n auto tests/test_install_local.py tests/test_build_cloud.py tests/test_developer_id_profile.py tests/test-accept-build.py -q` 为 27 passed；入口再增加“实装核验失败保留旧回执”“已是当前装机则复用”并隔离构建日志后，仅重跑受影响的 `tests/test_install_local.py`，最终 8 passed。其余原 21 项不重复运行；没有把隔离流程测试作为真实安装通过。
- 公开仓仅本地提交。已审阅起点领先的六条提交（均属于本组件）；`chapter xcode-cloud status --app clipbook --json` 与 `--repo . --json` 都返回 state=ok、push_allowed=true、workflow 全部手动，没有该共享前提缺失。远端 main 回读仍为 `de098c4f84b1a7a2ca67e65025fb522760ef144e`；本次不推送符合本任务“公开仓只本地提交”的具体边界，也未宣称已满足通用的远端同步完成谓词。

## 尚未完成与 CLI 接续

本轮入口登记与定向测试已完成；重建装机及其后的完整固定复验未完成，不能报告整个任务成功。缺失的是本组件签名描述文件，不是 ASC 登录失效、协议未接受或 Xcode Cloud 禁止推送，不报告这些共享前提 unmet。保留 Chapter 原 claims，由原队列收尾。

1. Clip 签名前提：需要包含本机 Developer ID 指纹 `72F835AA663461521834BFF102A4C16A52892F9C` 的 MAC_APP_DIRECT / Production / all-device 描述文件；当前原入口只读取回兼容文件，不创建/撤销账号 profile。本轮不扩大为修改开发者账号的签名前提维护，也不远程找另一台机器绕过原入口。可在本仓通过 `chapter agent-send --app clipbook --message '维护 Clip 签名前提：先只读复用兼容描述文件；确无兼容文件时，授权为 cyou.tianli.clipbook 创建包含本机有效 Developer ID 证书的 MAC_APP_DIRECT Production all-device 描述文件并接回本组件既有入口，保持 Team/iCloud 容器、不撤销旧证书或 profile、不改账号权限；用 scripts/developer-id-profile.py --check 回读，不装机、不公证、不推送或发布。定位见 handoffs/chapter-local-install-20261017.md。'` 单独接续。
2. 上项满足后，本仓执行 `~/Dev/.venv/bin/python scripts/install-local.py`，真实安装成功后运行 `chapter sop accept --app clipbook --check product_basics --check functionality --check recovery --check privacy --check native_ui --check installed_icon --json`；回读 `chapter sop verify-build-receipt --app clipbook --artifact /Applications/Clip.app --json` 和实际运行实例。不重启原队列、不另造手写通过记录。
3. 原 media_playback 未通过，owner=chapter；当前 `engine/acceptors/media_playback.py` 仍无 timed_out 分类，原探针 readyState=0 的原因不能从旧原件独自确定。仅在 Chapter 责任仓修复并保留真实 HTTP/媒体错误失败后，由原队列复验；本仓未改页面或素材。CLI 接续：`chapter agent-send --app chapter --message '接续 Clip media_playback 固定验收：先读原 run-v3hjar5m 与 chapter-fixed-failures-20261017.md，核实探针明确 timed_out 且无 HTTP/媒体错误时的环境分类缺口；在 Chapter 原 acceptor 修复并补回归，保留真实业务错误失败，由原队列复验，不改其他产品或部署。'`。
