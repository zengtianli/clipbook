# Chapter 固定失败项修复 · 2026-10-17

本轮身份：`chapter-task:39da3958a3ef474984125283d7b64f46` / claims pid `55582`。只处理 delivery-functionality、delivery-recovery、delivery-privacy、delivery-media_playback；只在本仓修改并本地提交，不推送、发版、装机、部署或改授权，不释放 Chapter 原声明。

## 范围与完成条件

- 实现块：`scripts/developer-id-profile.py` 的描述文件/本机证书匹配与只读取回；`build-cloud.sh` 的签名参数固定与自定义构建准入；`scripts/accept/_build.sh` 的锁忙退出。
- 验证块：`tests/test-accept-build.py`、`tests/test_developer_id_profile.py`、`tests/test_build_cloud.py`；本文件记录实际结果和未完成原因。其他会话的 project.yaml、perf 证据、文档与暂存保持原样。
- 共享资源：使用原 claims 身份；自定义构建只使用共享 sim_lane.BuildSlot，不占模拟器开机/性能安静门；验收缓存仅用本产品锁。证书、描述文件、本人 App、数据、偏好、剪贴板和后台任务不改。
- 完成条件：已定位的本仓缺陷有必要回归，真实只读预检反映实际签名前提；本地提交；固定验收证据仍由 jobs 的原脚本产出，不手写通过。外仓问题与缺失前提如实交接。

## 原始原因

- functionality / recovery / privacy 的三个原 run 日志均为 Xcode 退出 65：`Clip Developer ID` 不包含当前 Developer ID 签名证书，尚未编译或运行自检。
- 本机 `security find-identity -v -p codesigning`：Developer ID 指纹 `72F835AA663461521834BFF102A4C16A52892F9C`；本机 profile UUID `51f6ff8d-1c77-4799-a8de-40816f8f350c` 只含证书 `A0F5AE165F8F84EDC1787ACCE21E2F7551B7830A`。旧 `--check` 却返回 installed，未核证书。
- ASC 只读 GET /profiles（MAC_APP_DIRECT，枚举全部且无下一页）同一 bundle 只有上述 ACTIVE profile，没有含本机证书的兼容版本。本轮不创建、删除、重发 profile，不改账号授权。
- media 原 run `run-s6tdzj_s`：17 个本地视频均完整解码成功；四个页面视频 readyState/currentTime 为 0，error/play_error 均为空。HTTP 只读回读 search.mp4 为 200、主视频 Range 0-1023 为 206，不能据此宣称浏览器播放通过。
- 页面播放探针属于 `/Users/tianli/Apps/chapter/engine/acceptors/_common.py`、`media_playback.py`。PROBE 超时带 timed_out，media_playback.main 没有区分未取到元数据的等待超时与实际媒体错误；外仓不在本轮可写范围。

## 验证与接续

- `pytest -n auto tests/test-accept-build.py tests/test_developer_id_profile.py tests/test_build_cloud.py -q`：21 passed，覆盖错误缓存证书、同名候选选择、取回时验证内容且不写账号、本地只读预检、精确签名参数、共享槽释放、构建 4/65/75 退出码与锁忙保留原持有者。
- `bash -n build-cloud.sh scripts/accept/_build.sh` 与 `git diff --check` 通过。
- 真实本机 `scripts/developer-id-profile.py --check` 退出 4 / `signing_profile_unavailable`；不再将当前不兼容 profile 判为 installed。自动取回只使用 GET，不再自行创建账号 profile。
- 用独立 DerivedData 执行原 `build-cloud.sh --compile-only`：退出 0，日志有实际 BuildSlot admitted / BUILD SUCCEEDED，随后生产 `--selftest` 的 232 项断言与最终全通过总结均成功。日志在 `build/accept/chapter-fixed-failures-20261017/{compile-selftest,xcodebuild}.log`，该纯编译包不是可安装或分发的签名产品，不冒充固定验收通过。
- 对 Chapter 原 `media_playback.main` 做隔离内存夹具复现：HTTP 200、无 failed_requests、timed_out=true、video readyState 0 且无媒体错误，实际仍退出 1、无 deferred；只用于定位合同缺口，不是本产品真实播放证据，未写本仓 perf。
- 未运行会写固定证据的 app_sop accept/run，未启动本人 App，未改账号/证书/profile/TCC、安装包或更新源。其他会话的原 dirty、暂存与后台保留；四项最终状态仍由 jobs 固定复验。

## 受阻项和 CLI 接续

1. Clip 签名包前提缺失：账号与本机缓存都只有不含本机证书的 profile；需另一个明确授权的签名前提任务，补齐与本机 Developer ID 私钥匹配的 MAC_APP_DIRECT / Production / all-devices profile（或在持有现有匹配私钥的签名环境执行）。本轮禁止改授权，未创建或重发。补齐后，在本仓执行 `/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check`，再由 jobs 原队列复验 functionality / recovery / privacy；手工只复验可用 `~/Dev/.venv/bin/python ~/Apps/chapter/engine/app_sop.py accept --app clipbook --check functionality --check recovery --check privacy --json`，它不装机。
2. Chapter 播放环境分类（owner `chapter`）：修复其 `engine/acceptors/media_playback.py` 对探针 timed_out、未取得媒体元数据且没有实际 HTTP/媒体错误的 75 分支，保留 HTTP 4xx/5xx、媒体解码/业务错误退出 1，并补 `engine/test_acceptor_environment.py`。在本仓可用 CLI 另派责任仓：`chapter agent-send --app chapter --message '修复媒体播放验收的等待超时分类：探针 timed_out 且 readyState 为 0、没有 HTTP 4xx/5xx 或媒体错误时退出 75；真实 HTTP/媒体/业务错误仍失败；补 test_acceptor_environment.py，pytest -n auto 验证并本地提交；不动其他产品、不推送部署。Clip 定位原件见 /Users/tianli/Apps/clip/mac/handoffs/chapter-fixed-failures-20261017.md'`。本轮未执行该派单，未越界修改。
