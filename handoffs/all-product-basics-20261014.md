# Clip · product_basics

## 进度

- 2026-10-15 01:45（上海）接续：用户明确授权本机一次免公证快装；进入安装阶段，不发布更新源、不部署、不推送。
- 本阶段只改原 build-cloud.sh 的分离编译/签名检查与明确快装入口、固定验收的已装登记/文字、本交接和 build/accept 产物；共享生产引擎、真实数据/偏好/账号/登录项保留。
- Mini 只持 Apple Development，Air 只读实查持 B9LJH93LA4 Developer ID；复用 macmini 原 login_run.py 登录会话签名，保持既有 CloudKit 身份与无设备清单描述文件。写前复用 Chapter --pid 84476 / 原 session check，声明不另建或释放。
- 01:54 安装前检查真实拒绝退出 4，已装 115 没被替换：新增团队检查的 grep -q 提前关闭管道，pipefail 误判；实读签名正确，改为读取完整输出，重建回执并保留第一次候选。没有减标准或改签法。

- 2026-10-15 01:09（上海）开始；本轮仅四项基础功能与固定验收，不安装或发布。
- 已读固定 PRD/14 项要求、README、既有运行自检与商店版交接；现有四项已有生产实现，缺完整验收及登记。
- 总部生命周期四份原版已更新，本仓副本漂移；沿原 vendor-lifecycle.py 同步，不修改总部生产引擎。
- 已完成真实设置动作与配置同步、更新检查验收；原快构建候选及 Chapter build-receipt 已产生，正式验收与回读均通过。正在限定提交收尾。
- 保留他人 project.yaml/perf/docs 差异、暂存与后台；复用 Chapter --pid 42426 / chapter-task:692b997e73f0525ab7345aedb5568049，写前 check，不另建或释放声明。

01:25 首次正式 Chapter 验收已运行，设置/快捷键/iCloud 原始行为全部通过；更新三项失败。已读进程原件：隔离 feed 写了错误字段 archive，生产解析器只接受 filename/download_url，正确拒绝“缺少下载或校验信息”。仅定向纠正测试 feed 字段为真实协议 filename/size_bytes，标准与生产引擎不改；重建新的源码候选及 receipt 后复查，不按同因原输入循环。

## 完成结果（01:33）

`chapter sop accept --app clipbook --check product_basics --json` 实际执行两次（首次失败、纠正输入后通过），最终退出 0 / status=passed；`chapter basics --app clipbook --json` 回读 passed / all_passed=true。固定 14 项行为由实际对象/回调和进程读回覆盖，22 项严格布尔检查全部为 true，没有手写 delivery-evidence，也没有省检查或声明不适用。

实现改动：

- 四份 Shared 文件由总部原 vendor 脚本逐字节同步，`--check` 返回 match；总部代码、Chapter 标准和引擎未改。
- 更新窗口接入总部现有自动检查/下载/安装、间隔、渠道、跳过/延后选项；Clip 命令帮助补 update options，原封装直接转交共享命令层，不另造更新器。
- 配置迁移白名单加入 appUpdateOptions，更新选择可以同其他配置同步；暂停、登录项、权限和真实账号数据仍不迁移。
- 隔离偏好域复用同一个 UserDefaults 对象，修复原隔离进程中设置对象和同步对象监听不同实例的问题，真实标准偏好域保持原行为。
- 新 --product-basics-self-test 只允许隔离目录、隔离偏好和临时 test.tianli.clipbook.basics 身份；进程先 .prohibited。用真实 AppDelegate/SettingsView/AppLifecycleUI、直接控件 action、生产快捷键分发与配置/更新引擎，未合成桌面输入。
- 新固定 scripts/accept/product_basics.py 默认验 /Applications/Clip.app；显式 --app 必须给 --receipt，先核包/源码/签名，再复制真实原件、仅变更测试身份并重签隔离副本。登记命令明确选候选，没有把候选称为已装。
- project.yaml 只增加 sop.product_basics 与 sop.accept.product_basics；原先其他会话追加的 public role/features 块和 perf 旧差异保留。

## 实际候选、来源与证据

原快构建入口：`CLIP_LOCAL_RELEASE_DIR=build/accept/product-basics-candidate bash release-local.sh`。由 `chapter sop build-receipt` 真正执行构建及生产 --selftest 后写回执，未手填来源。未覆盖 build/local-release 的公开原包。候选为 CLIP_LOCAL_DISTRIBUTION 本地版，沿原源码集合与包名，不是公开源码发布或另一产品的包。

- App：`build/accept/product-basics-candidate/Clip.app`，cyou.tianli.clipbook，1.2.1 (121)，未安装。
- 主程序 SHA256：`9e8c5e76adb538f2f51354e12f97f3a6cf165c615c76e9885ae7633e92206960`。
- 回执：`build/accept/product-basics-candidate.json`，SHA256 `b022495abc2393448e97df353093b9a2d6198e691cdd02033d88510948bfe486`。
- 当前实际编译输入摘要：`c175c9efeb367b0768340c63a29bad91f6f6c9e9bf2d5475573539b4a09f66b7`；包含 Sources（含只读 iOS 家族软链实际内容）、cloud-project/entitlements、图标、原快构建/打包入口、验收脚本与 project.yaml。回执记录编译当时 HEAD 与工作树 dirty 状态，包版本取当时 git-count。
- 原件：`perf/acceptance/product-basics-343ae11d990e416e8167c4523d1bf64e/raw.json`，SHA256 `b3b82b57461ec8e9c652c4771e5d0c9a326affef1903c26e022b09353b7d21fd`；四分类均引用同一可核原件，包含包/receipt/source 身份和实际检查。
- Chapter 固定记录：`perf/acceptance/run-i1sxboqo/product_basics.json`；固定 detail：`perf/acceptance/product_basics.detail.json`。perf/delivery-evidence.json 由 Chapter 更新，未手写，也不将其中旧的他人差异纳入提交。
- 首轮失败记录 `perf/acceptance/run-t6qxd_0l/product_basics.json` 与旧 receipt 副本 `build/accept/product-basics-candidate-initial.json` 保留；原因已定位为 feed 字段错误，正式生产解析器没有放宽。

构建回执的确切入口：

```sh
chapter sop build-receipt --app clipbook \
  --artifact /Users/tianli/Apps/clip/mac/build/accept/product-basics-candidate/Clip.app \
  --source-glob 'Sources/**/*.swift' --source-glob cloud-project.yml --source-glob Cloud.entitlements \
  --source-glob icon/AppIcon.icns --source-glob release-local.sh --source-glob scripts/package-local.py \
  --source-glob scripts/accept/product_basics.py --source-glob project.yaml \
  --receipt-out build/accept/product-basics-candidate.json \
  --build-command 'CLIP_LOCAL_RELEASE_DIR=build/accept/product-basics-candidate bash release-local.sh' --json
chapter sop accept --app clipbook --check product_basics --json
chapter basics --app clipbook --json
```

## 14 项行为的真实覆盖

| 固定行为 | 本轮实际路径 |
| --- | --- |
| settings.interaction | 创建实际 SettingsView 与生命周期原生窗，实际 NSSwitch 调用原 target/action，保存更新选择。 |
| settings.persisted_readback | 新 clip 子进程读回 maxItems 700 和实际 UI 保存的选项，不用本进程缓存作判定。 |
| settings.error_preserves_data | 原 AppConfiguration 拒绝坏配置，导出原数据逐字节不变。 |
| shortcuts.action_path | 原 ClipShortcuts.handleLocal → AppDelegate.perform(.pause) → 设置与 watcher 暂停状态实际改变。 |
| shortcuts.disable_restore | 清除绑定动作不触发、恢复后触发；新进程读回持久化组合。 |
| shortcuts.conflict_or_reserved_keys | 实际重复动作与保留组合被拒，持久化绑定不变；不发送真实按键。 |
| icloud.push_pull | 实际 UI 开关启动配置同步；隔离云副本写出，NSFileCoordinator 远端写入触发原 presenter，设置对象收到 900。 |
| icloud.unavailable_local_fallback | 去掉隔离云入口后实际 reconcile 报错，配置和业务条目保留。 |
| icloud.conflict_or_corrupt_recovery | 坏远端 JSON 被拒，原本机数据不变；恢复合法云副本后同步恢复。 |
| icloud.disable_preserves_data | 关闭同步，本地导出、云副本字节与业务条目保留。 |
| updates.check_result | 原生命周期 UI 离屏检查真实测试 feed，显示新版 99.0；共享 CLI 同一检查器读回版本与获取入口。 |
| updates.failure_recovery | 坏 feed、缺 feed 真实报错；恢复合法 feed 后检查成功。 |
| updates.options_or_store_entry | clip update options 保存自动检查/间隔；新进程读回；非法间隔被拒。 |
| updates.data_preservation | 同一共享安装入口 --dry-run 出真实预演，配置与业务记录不变；原用户偏好/已装程序前后 SHA 相同。 |

## 范围与后续

iCloud 覆盖本机隔离的生产配置同步（文件协调、远端接收、坏数据恢复、本地回落、关闭保留）；没有写本人 iCloud 或宣称 Apple 服务完成两台设备传输。更新使用隔离本机 feed 和真实安装预演，没有下载安装升级、重启现装实例或发更新源。临时身份的文件 URL、设置、视图、快捷键均是本产品原件；测试不是注册 presence 或顶层 ok。

本轮只完成候选验收，未装机、公证、推送、发布或部署；独立 install 阶段由 Chapter 另排。原件路径、包 SHA 与 receipt 已给齐。固定脚本默认仍可在安装后用 `~/Dev/.venv/bin/python scripts/accept/product_basics.py` 验已装版（需由 Chapter 提供 SOP 验收环境）；本轮登记显式 --app/--receipt 选候选，后续安装阶段必须以真实已装原件重新核验，不沿用候选冒充装机。

## 范围

只改本组件必要自有 Sources、原共享副本的正式分发、scripts/accept/product_basics.py、必要候选构建参数、project.yaml 的 product_basics/accept 两块、本交接与对应构建/验收产物。14 项必须真实行为与 SHA 原件，证据由 Chapter 写 perf/delivery-evidence.json。本机隔离同步与 Apple 跨设备传输分开报告。
