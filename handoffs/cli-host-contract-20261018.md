# 2026-10-18 商店宿主 CLI 修复候选：待 TestFlight 交付

## 任务与边界

- Chapter task：`28c0533e28bf47d8ac366bfd0379714b`，接续同族 iOS 的 `handoffs/cli-dependency-20261018.md`；仅处理商店宿主缺失 CLI 及该 CLI 所需的同步归档，不展开 Mac 其他 SOP 欠项。
- 沿派出者 `--pid 88210 --session chapter-task:28c0533e28bf47d8ac366bfd0379714b` 写前核对 claims，不另开、不释放声明。
- 实际源码范围：`Sources/ClipbookApp.swift`、`Sources/Native/{ClipCLI,Settings,StoreConfiguration}.swift`、`store/{project.yml,check.sh}`；新增 `tests/test_store_cli.py` 和本交接。生成物限原商店工程忽略文件与 `build/cli-host-20261018/`。
- 共享资源：商店 SDK build 沿原 `sim_lane.BuildSlot`；测试只用 `test.tianli.clipbook.store` 沙盒身份、隔离 home/偏好及原命名剪贴板，不启动/退出本人的 Clip，不占模拟器或性能采样。
- 原任务最终条件是已装宿主可用、原 jobs 只复验 `clip-ios` 的 `cli_entry`、`agent_cli` 后真实通过；**当前尚未达到装机条件，不能把候选测试当作已装修复**。

## 实际根因与现行渠道

只读回读 `/Applications/Clip.app/Contents/Info.plist`：1.2.1 (1)、`ClipDistribution=store`、有 MAS receipt；主程序 SHA256 `dd1eaaf93c8b6006a98349960e5b9afbd3b90c6a0961e310824da92c9e9d4dc7`，深验签退出 0。`~/.local/bin/clip` 仍指向 `/Applications/Clip.app/Contents/Resources/bin/clip`，目标缺失。

原商店工程排除了 `ClipCLI.swift`，Boot 不分流 CLI、不连接命令通知、也不创建包内链接；`ProductIdentity.cloudSupported` 在商店条件下恒为 false，商店 entitlement 没有家族 CloudKit 容器。因此仅补链接或让验收读下载版候选都不能恢复 iOS 已登记能力。

`chapter local-install check --app clipbook --direct --json` 实际退出 1：`policy=testflight`、`source=testflight`、`error.code=testflight_only`，信息为“本机唯一安装件与更新源是 TestFlight，禁止 Developer ID 直装”，返回下一步 `chapter store testflight --app clipbook --platform macos --json`。本轮沿此渠道边界，不覆盖商店安装件。

## 修复

1. 商店 target 编译原 `ClipCLI` 与原 `RuntimeSelfTest`，签名前创建与下载版一致的 `Resources/bin/clip -> ../../MacOS/Clipbook`；Boot 在创建 NSApplication 前处理命令，并让商店 App 接入原 `connectCommandLine()`。
2. 商店复用原 `MacClipSync`、同族 `PocketLibrary.swift -> iOS Shared/ClipLibrary.swift`、只读归档读取器、通知及改写请求；启用既有可选归档设置，默认开关仍由原偏好决定，不主动开启同步。商店仍使用自己的沙盒主库，没有读取下载版生产库或把两份库冒称同一份。
3. 商店工程声明既有 `iCloud.cyou.tianli.clip` 的 Production CloudKit 与推送能力；配置 KVS 保持独立。正式 Apple profile/云端传输须在正式签名包上核验，本轮沙盒副本不证明这些。
4. 商店仍排除共享下载更新器/更新界面/更新 CLI。原 `ClipCLI` 的商店分支拒绝 `update` 和 `import-deck`，帮助不宣称提供这些操作；配置状态直接读原 `AppConfiguration.statusRecord`，不引入更新器。运行实例查询跟随实际包身份，正式 bundle ID 不变，隔离测试不误认本人的 App。
5. `store/check.sh` 守住 CLI 编译、签名前链接、独立更新器排除与家族容器；新增真实包内命令的沙盒回归。未改 iOS 登记、固定验收器或旧失败证据。

## 验证与证据

- `bash store/check.sh`：退出 0，8 项 entitlement、10 张原图标。
- XcodeGen + Release SDK build：退出 0，原共享 BuildSlot 准入；未要求正式签名、归档、上传。日志 `build/cli-host-20261018/build.log`。
- 下载版本源集 `swiftc -typecheck -D CLIP_LOCAL_DISTRIBUTION`：退出 0，日志 `build/cli-host-20261018/download-typecheck.log`。
- 真实沙盒测试副本：仅副本改 bundle ID 为 `test.tianli.clipbook.store`，保留 App Sandbox/用户选文件/出站网络三项权限，移除不能 ad-hoc 验证的受限云权限后本地签名；生产工程的 8 项权限保持。副本位于 `build/cli-host-20261018/test/Clip.app`，不是发行包，不可安装作正式产品。
- `CLIP_STORE_TEST_APP=.../test/Clip.app ~/Dev/.venv/bin/python -m pytest -n auto tests/test_store_cli.py -q`：**6 passed**，最终日志 `build/cli-host-20261018/pytest.log`；覆盖签名/包内链接/帮助、只读不建库、独立进程增删改查、下载专用操作拒绝、开归档必须确认。
- 原 `--store-self-test`：退出 0，真实沙盒主库、命名剪贴板和配置导入/导出往返通过；其 `cloud_archive=true` 只表示该构建支持归档，不能解读成真实跨设备同步通过。
- 原 `tests/test-runtime.sh`：接续中，最终结果另补；首次使用临时 bundle ID 时暴露实例查询硬编码，经修复后重建，旧中断日志单独保留，不记通过。
- 源码/候选/已装哈希读数在 `build/cli-host-20261018/evidence.json`；这是本轮观察记录，不是 Chapter 正式构建/装机回执，不覆盖 `perf/build-receipt.json` 或正式 acceptance。

## 接续与授权

已装件仍是上述 TestFlight 1.2.1 (1)，包内 CLI 仍缺失；没有把 SDK 候选或 ad-hoc 副本称作已装版。本轮没有推送、上传、商店送审、发公开更新源、装机或改签名账号授权，保留其他会话的 `project.yaml`、perf、文档、暂存和后台。

本轮仅本地提交。当前任务明确“自动转交不新增外发或公开授权”，因此新的 TestFlight 上传需本人明确授权；不要为了绕过 TestFlight 规则走 `build.sh --install-local`。用户在本仓 `cd /Users/tianli/Apps/clip/mac` 后的具体接手命令（取得上传授权后）：

```sh
chapter store testflight --app clipbook --platform macos --json
```

该原入口会取本仓 `store/`，正式归档/签名、上传、等待 ASC build VALID 并加入内部测试组，不提交商店审核。上传后回读实际 ASC build、来源提交与处理状态；TestFlight 安装由 Chapter 原流程接续，再回读 `/Applications/Clip.app` 的版本、来源、深验签和包内 CLI。原已登记外部链接目标届时即可恢复，若需重建链接沿 `python3 scripts/install-cli.py /Applications/Clip.app`。

**仅在实际装机完成后**交原 jobs 队列复验 iOS 两项；同因未变不要反复执行旧装机验收。手动等价入口是 `chapter sop accept --app clip-ios --check cli_entry --check agent_cli --json`。真实 CloudKit 正式签名/账户/跨设备传输另据实际结果报告，不用本轮去掉云权限的沙盒副本冒充。
