# 2026-10-18 宿主 CLI 接续核验：候选通过，已装件仍缺入口

## 本轮范围与责任

- Chapter task：`14ef959ea4be416fab9d18f43d2ef55f`；接续 iOS 的 `handoffs/cli-dependency-20261018.md` 与本仓 [原修复交接](cli-host-contract-20261018.md)，仅核对同一宿主 CLI 故障及必要依赖。
- 本轮实际写入只有本文件；写前使用派出者 `--pid 77729 --session chapter-task:14ef959ea4be416fab9d18f43d2ef55f check <本文件绝对路径>`，返回 0；未新建或释放声明。
- 共享资源：只读 `/Applications/Clip.app`、`~/.local/bin/clip` 与已有候选；命令回读仅使用既有 `test.tianli.clipbook.store` 沙盒副本和独立 home/偏好，不读写生产剪贴板或数据库，不启动/退出本人的 Clip，不占构建、模拟器或性能车道。
- 完成条件：实际已装宿主提供可执行包内 `clip`，其帮助与 `cloud status --json` 可运行，再由原队列只复验 clip-ios 的 `cli_entry`、`agent_cli`；**当前未达到，不能报装机故障已修复**。
- 原候选源码、RuntimeSelfTest、测试、原交接、project.yaml、perf 和其他未提交内容均保持原样；本轮仅提交本文件，不吸收其他会话改动，不推送、上传、装机或改变授权。

## 2026-10-18 本机实物回读

`chapter local-install check --app clipbook --direct --json` 返回退出码 1：

```json
{"ok":false,"app_id":"clipbook","policy":"testflight","update_source":"TestFlight","installed":[{"path":"/Applications/Clip.app","short":"1.2.1","build":"1","source":"testflight"}],"count":1,"error":{"code":"testflight_only","message":"本机唯一安装件与更新源是 TestFlight，禁止 Developer ID 直装"},"next":"chapter store testflight --app clipbook --platform macos --json"}
```

Info.plist 实读仍为 `cyou.tianli.clipbook`、`1.2.1 (1)`、`ClipDistribution=store`；主程序 SHA256 为 `dd1eaaf93c8b6006a98349960e5b9afbd3b90c6a0961e310824da92c9e9d4dc7`。`~/.local/bin/clip` 仍指向不存在的 `/Applications/Clip.app/Contents/Resources/bin/clip`，可执行检查为 false；运行中的本人实例 PID 6721 未动。

根因及源码修复已经由原任务落实为候选：商店编译 CLI、Boot 分流、命令通知、签名前包内软链，以及同族归档能力；不需要再写第二套 CLI 或改 iOS 验收登记。候选尚未通过正式渠道替换已装件，安装件故障没有变化，所以没有重跑必然同因失败的正式两项验收。

## 可复用验证与本轮定向回读

已有日志均在 `build/cli-host-20261018/`，本轮复用、不重跑通过的构建或测试：

- `pytest.log`：6 passed；`store-self-test.log`：`ok=true`。
- 原交接中“运行态自检接续中”已有最终结果：`runtime.log` 末尾为“clip 运行态自检：40 项通过”，其中运行进程 34 项、退出后独立命令 6 项通过。
- 当前测试副本主程序 SHA256 为 `cb0e6b1955fe6ee6873fbb80d2bd6d58628dc9ad7672bef997a61d9870cfcfa4`，与最终 runtime 日志行首记录一致。
- 原 `evidence.json` 所列 7 项源码/测试输入 SHA256 与当前文件逐一一致；RuntimeSelfTest 当前 SHA256 为 `d9678e5e2fd8b586225ad6eafebe27662f94f7ccae70b9c75ad05c93e830d4b4`。
- 原 `evidence.json` 的候选/测试副本可执行哈希在最后一次重建前生成，不能用于指代最终包；当前 SDK 候选哈希为 `eebb2940e78442fca4a4ff9a649286db32aec1528bd6f4685b8c21d5a9cfae0e`，测试副本哈希如上。本轮不覆盖原观察记录。

本轮额外只执行受影响的最小只读核验：

1. 对上述测试副本 `codesign --verify --deep --strict`，退出 0。
2. 通过真实包内软链执行 `clip --help`，退出 0；JSON/退出码说明与 iOS 所需 add、copy、cloud status/list/show/favorite/unfavorite/delete 均存在。
3. 同一包内命令 `clip cloud status --json` 退出 0，返回 `ok=true`、`supported=true`、`environment=Production`、`enabled=false`、`live=null`；隔离数据目录没有被创建。

这些证据只证明已有沙盒候选可用，不能证明正式 Apple 云权限、真实跨设备传输、TestFlight 分发或已装修复。测试副本仍是本地 ad-hoc 沙盒身份，不可安装作正式产品。

## 唯一未完成阶段与接续

本轮明确要求“本轮只本地提交”和“自动转交不新增外发或公开授权”，故止于本地核验与交接，不根据一次自动转交上传新的 TestFlight 包，也不改变 `testflight` 安装政策。Chapter 只读回执仍保存本人长期 install/release/push/deploy 授权；本轮具体边界优先，没有修改该长期授权。

如本人选择授权本次 TestFlight 分发，在本仓接续原候选与原声明，先审阅并只提交宿主修复的实际文件（不带入 project.yaml、perf 或其他改动），再走唯一原入口：

```sh
cd /Users/tianli/Apps/clip/mac
chapter store testflight --app clipbook --platform macos --json
```

这会正式归档/签名、上传 Apple 并分发内部 TestFlight，不提交商店审核；构建准入沿共享 BuildSlot/原队列，繁忙返回 75 后交原队列。发生非零退出先读 ASC 原 build 与已发生动作，不能盲重传。安装/常驻实例接续交 Chapter 原流程，不另造装机按钮或绕过运行保护。

接续必须回读实际 ASC build 的版本、VALID、来源提交，以及实际 `/Applications/Clip.app` 的版本/来源、签名和包内 CLI；只在实际装机通过后交原 jobs 复验 iOS 两项，等价命令为：

```sh
chapter sop accept --app clip-ios --check cli_entry --check agent_cli --json
```

未发新包前，两项继续保持原失败证据；本轮未将失败改为通过，也未将候选冒充已装版。
