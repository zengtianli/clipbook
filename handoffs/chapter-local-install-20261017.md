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

待本轮执行后记录原命令、实际退出、回读及接续。
