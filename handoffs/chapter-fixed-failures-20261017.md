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

## 六项固定失败再次核验 · task 151efe7b

本轮复用 Chapter 精确身份 `--pid 5417 --session chapter-task:151efe7b0d494aacb3e3c896298eb937`，写入前对本文件执行原 `claims.py check`，退出 0；不另建、不释放声明。

排查范围固定为本次六条原日志对应的 `scripts/accept/{_build.sh,functionality.sh,recovery.sh,privacy.sh,native_ui.sh,product_basics.py}`、`build-cloud.sh`、`scripts/developer-id-profile.py` 及其输入绑定；媒体只读核 `scripts/build-site.py`、已发布主教程对应的本地原文件和 Chapter 原探针。实际写入只有本交接的本节，没有发现尚未修复且可在本轮授权内解决的本仓实现缺陷。现有修复已在 `c24a56c`（证书匹配、精确签名和共享 BuildSlot）与 `a353d86`（生产来源绑定）中，不重复改写或回退它们。

共享资源仅作只读查询及单个主教程解码；不构建，不占构建/模拟器/安静测量槽，不运行本人 App，不改账号、描述文件、安装包、数据、偏好或剪贴板，不操作已有后台。本轮完成条件是核清六项当前失败与授权边界、保留真实未通过状态、本地提交交接；固定复验仍交原 jobs 队列，不创建平行作业或手写通过证据。

本次原件：

| 项 | 原 run / 实际原因 |
| --- | --- |
| functionality | `run-unvdy0xd/functionality.log`：`signing_profile_unavailable`，退出 4，未编译/运行自检 |
| recovery | `run-9ek2e4cy/recovery.log`：同一签名前提，退出 4 |
| privacy | `run-_4mns5gf/privacy.log`：同一签名前提，退出 4 |
| native_ui | `run-cjghz8du/native_ui.log`：同一签名前提，退出 4，未运行 UI 断言 |
| product_basics | `run-9o6w8nte/product_basics.detail.json` 及 `product-basics-3fa59af6c14f4e8ca4c3f0e46d319250/raw.json`：实际包匹配 true，当前生产来源匹配 false，夹具未执行 |
| media_playback | `run-v3hjar5m/media_playback.detail.json`：17 个已列本地视频解码通过，搜索/编辑/收藏三段页面视频播放通过，主教程 readyState/currentTime 均为 0、duration/error/play_error 为空 |

本轮实际核验：

- `scripts/developer-id-profile.py --check` 仍退出 4；再直接调用生产 `fetch(...)`，只经 ASC GET 查询，返回 `compatible_profile=false`。本机有效签名指纹仍为 `72F835AA663461521834BFF102A4C16A52892F9C`。没有创建、重发、缓存或删除任何账号/profile 内容；API 查询成功，不能报告 Apple 账号未登录或协议未接受。
- Chapter 原 `acceptance_code_environment` 仍返回 `SOP_CODE_BINDING_SHA256=bb262c20f7d6303330d08648053c75c720b5efc34bcdfe8364942d32f3fd7f92`、`SOP_BUILD_CURRENT=0`；原 verifier 普通分支返回“当前构建输入与装机来源不同”，`code_only=True` 返回“构建 receipt 未完整覆盖 Chapter 的生产源码集合”。当前生产差异不能按验收脚本/文档变化忽略，原已装来源回执也不能补写。
- `docs/demo/ai-sample/sample.mp4` SHA256 为 `0a6f43d83fa967b04ba7738fa1bf31db2066bbca2223570e693dfbbd91246744`，对应页面主教程文件名；ffprobe 确认为 H.264、1920×1080、38.6 秒，moov 位于字节 32、mdat 位于 14531，`ffmpeg -v error -i <原文件> -f null -` 实际退出 0。原媒体验收未列入这份嵌套目录文件，本次补核它，未改素材。
- HTTP 首次无 User-Agent 的主教程 Range 请求得到 403，不能视为通过；随后有界诊断用显式 User-Agent，主教程与 `search.mp4` 都返回 206、`video/mp4`、1024 字节，主教程 Content-Range 为 `bytes 0-1023/4510037`。不据此声称浏览器播放通过，也不将真实 HTTP 403 改判环境 75。
- Chapter 当前 `media_playback.py` 仍未处理探针返回的 `timed_out`；`_common.py` 会把它作为正常 facts 返回，而 media acceptor 把未取得元数据的视频一律列为失败。原详情未保存 timed_out 和请求状态，因此不能仅凭 readyState 0 断言这一次必定是环境超时；责任仓修复时必须保留真实 HTTP/媒体错误失败，并覆盖“探针明确超时且无业务错误”的 75 分支。

本轮没有实现或测试源码改动，沿用上述提交已记录的针对性回归，不重复输入未变的测试、同因必败的构建或正式验收。未运行 app_sop accept/run，未改任何 perf 证据、project.yaml 或其他会话改动/暂存。提交前 `git diff --check` 核对本交接；本轮仅本地提交，不推送、发版、装机、部署或改授权。

接续仍为三项依赖，均非本轮代码可绕过：

1. 四项签名构建需另一个明确授权的任务补齐包含本机证书的 all-device Production MAC_APP_DIRECT profile；在本仓先执行 `/Users/tianli/Dev/.venv/bin/python scripts/developer-id-profile.py --check` 回读，再交原 jobs 复验，不把退出 4 改为 75。
2. 基础功能需当前完整生产输入的真实构建与装机，当前任务禁止装机；在本仓可另交既有入口 `chapter agent-send --app clipbook --task install --message '仅以当前完整生产输入生成真实构建回执并沿既有入口装机，随后由原 jobs 复验 product_basics；不推送、不发版、不部署、不改账号授权，缺签名前提如实报告。'`，本轮不执行。
3. 媒体超时合同缺口的 owner 为 `chapter`；在本仓可使用上节责任仓 CLI，增加本次 `run-v3hjar5m` 原件定位与“原详情未保存 timed_out，不能从 readyState 0 独自推断环境超时”的边界。本轮不越界改 Chapter，也不另派任务。
