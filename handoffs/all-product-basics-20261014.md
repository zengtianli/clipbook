# Clip · product_basics

## 进度

- 2026-10-15 02:19 接续：Chapter 新回读报正式装机回执不符；实读磁盘 124 与 build/accept 的原真实回执逐项匹配，但默认 perf/build-receipt.json 仍记旧 108。上一轮遗漏默认回执同步，不是当前包或图标错误。
- 本轮仅保存旧默认回执、逐字节同步既有真实构建回执至默认入口、执行固定 product_basics 验收并更新原报告；不重新编译/替换已匹配包，不改变源码、项目登记、用户配置或常驻进程。写前复用 --pid 32528 / Chapter 原 session check，不另建或释放声明。
- 02:22 正式默认回执修复完成：Chapter 原 verify_build_receipt 返回 true；必须执行的 accept 退出 0，22/22，basics 回读 all_passed=true；原 PID 689 保留。

- 2026-10-15 01:45（上海）接续：用户明确授权本机一次免公证快装；进入安装阶段，不发布更新源、不部署、不推送。
- 本阶段只改原 build-cloud.sh 的分离编译/签名检查与明确快装入口、固定验收的已装登记/文字、本交接和 build/accept 产物；共享生产引擎、真实数据/偏好/账号/登录项保留。
- Mini 只持 Apple Development，Air 只读实查持 B9LJH93LA4 Developer ID；复用 macmini 原 login_run.py 登录会话签名，保持既有 CloudKit 身份与无设备清单描述文件。写前复用 Chapter --pid 84476 / 原 session check，声明不另建或释放。
- 01:54 安装前检查真实拒绝退出 4，已装 115 没被替换：新增团队检查的 grep -q 提前关闭管道，pipefail 误判；实读签名正确，改为读取完整输出，重建回执并保留第一次候选。没有减标准或改签法。
- 01:55 原入口一次成功快装 1.2.1 (124)，保留旧包；01:56–01:57 默认已装原件的 Chapter 固定验收退出 0 / passed，22/22。01:59 完成源码/已装 SHA、设置、登录项及原进程回读；候选阶段结论由下文安装接续覆盖。

## 默认装机回执修复完成（2026-10-15 02:22）

Chapter 回读的真实错误为“装机可执行文件/版本/图标与构建 receipt 不符”。根因是默认 `perf/build-receipt.json` 还登记 1.2.1 (108)，而上一轮实际构建/安装/固定验收使用 `build/accept/product-basics-installed.json` 的 124。上一轮未同步正式默认入口，属于交付遗漏；图标本身 SHA 相同，没有重新生成图标或换包。

已先核 124 的 bundle/version/build/主程序/icon 和 47 个来源文件，全部与实际构建时由 Chapter 生成的原回执一致，再原样复制该回执至 `perf/build-receipt.json`。没有补造 built_at、来源 commit、输入摘要或构建命令；两个位置逐字节一致，SHA256 均为 `badf64a724a70fcc921c1e93a270022ad25fdc48bdc3ad15bb8f16f7a48654c8`，仍记录真实构建时间 01:55:30、提交 73a58be。旧未提交默认回执原字节保留在 `build/accept/default-build-receipt-before-20261015-0219.json`，SHA256 `c4d333f512de88e72cfc89a6db5e6e5796a445205a7efbba1be4a793cb14953f`，其他会话的源码/登记/暂存差异没有撤销。

本轮实际 `chapter sop accept --app clipbook --check product_basics --json` 退出 0 / passed，当前正式记录 `perf/acceptance/run-wg4inlai/product_basics.json`；新原件 `perf/acceptance/product-basics-da29425f75054b8e85856a5445282087/raw.json`，SHA256 `f02af80248b980fbad471f6f3b5ccf05fb70063ab4a727e99e8151ed814c913d`，phase=installed，22 项严格布尔全部 true，完整含政策固定 14 项。delivery-evidence 由 Chapter 写入，未手写。

只读调用 Chapter 原 `verify_build_receipt` 的默认入口回读 `(True, '装机可执行文件、图标与当前构建输入均匹配 receipt')`；`chapter basics --app clipbook --json` 返回 passed=1 / all_passed=true。生产源码与原构建输入未改，本轮没有第二次编译或安装，没有公证、发布、推送、部署或写更新源。原 PID 689 仍运行，常驻实例切换与苹果跨设备传输的边界继续按下文报告；本轮回执不符无剩余受阻。

## 安装接续完成（2026-10-15 01:59）

用户本轮新增授权为本机一次免公证迭代快装，取代此前“本轮不安装”限制；没有公证、公开发布、部署、推送或写更新源。原默认发行入口仍要求公证，本轮使用明确 `--install-local` 模式，未借分发开关或降低签名标准。首次安装尝试在任何替换前失败；修正原输入后只有一次实际替换。

源码提交：`85a0cf3` 增加原构建入口的显式编译/检查/本机快装模式、原登录会话签名编排、切换固定验收到已装包；`73a58be` 修复完整输出团队检查、保留旧候选。设置等生产核心为前轮 `8313b45`。只提交本轮块，project.yaml 原 12 行 public role/features 差异和其他会话 perf/docs/暂存均保留。

实际流程与原入口：

```sh
chapter sop build-receipt --app clipbook \
  --artifact /Users/tianli/Apps/clip/mac/build/accept/product-basics-signed/Build/Products/Release/Clipbook.app \
  --source-glob 'Sources/**/*.swift' --source-glob cloud-project.yml --source-glob Cloud.entitlements \
  --source-glob icon/AppIcon.icns --source-glob build.sh --source-glob build-cloud.sh \
  --source-glob scripts/build-basics-install.py --source-glob scripts/accept/product_basics.py --source-glob project.yaml \
  --receipt-out build/accept/product-basics-installed.json \
  --build-command '~/Dev/.venv/bin/python scripts/build-basics-install.py' --json
CLIP_DERIVED_DATA=/Users/tianli/Apps/clip/mac/build/accept/product-basics-signed bash build.sh --install-local
chapter sop accept --app clipbook --check product_basics --json
chapter basics --app clipbook --json
```

编排先在 Mini 对原 cloud-project.yml 的 CloudKit target 执行 `build.sh --compile-only`（不可安装中间产物）；在 Air 原 `login_run.py` 登录会话使用固定 Developer ID 签名、hardened runtime、安全时间戳。描述文件复用原已装、已验签的无设备清单 `Clip Developer ID`，不创建描述文件、不修改开发者账号。只把候选与签名材料交给签名机的独立缓存目录，校验两次传输 SHA；没在 Air 安装、改源码或跑用户 App。回到 Mini 原 `build.sh --check-only` 执行生产 selftest、共享 signed 级检查和 CloudKit 权限/bundle/version/CLI 链接检查，Chapter 围绕整个实际构建写来源回执。

实际已装原件与回执：

- `/Applications/Clip.app`：cyou.tianli.clipbook，1.2.1 (124)，CloudKit Production / iCloud.cyou.tianli.clip，LSUIElement=false；Developer ID 团队 B9LJH93LA4，深验签及 shared signed 级门禁通过，没有使用开发或 ad-hoc 签名装机。
- 主程序 SHA256：`8c52b4d6773b7dc2308739a488c2d79e35a27de51072b95f618e3e771580201b`，与构建产物/receipt 实读相同。
- 回执：`build/accept/product-basics-installed.json`，SHA256 `badf64a724a70fcc921c1e93a270022ad25fdc48bdc3ad15bb8f16f7a48654c8`。
- 47 个实际输入摘要：`448b1f82822beb10cb9b921ba7cd0dfd042ac9f1f06f2182cde6b4a8f8afaad4`，构建时提交 `73a58be99d310ad63fb25f1b4337a39ad42e2576`；收尾逐文件核仍一致。回执保留编译时真实工作树状态。
- 原件验收：`perf/acceptance/product-basics-19d85aed5d894dfd95b24aeb6fcf07b1/raw.json`，SHA256 `5d924c041282cb3bda42e2cc7f39ad91d7d1cda8075270d036d03d1c33d5e757`；phase=installed、真实复制主程序匹配 receipt，22/22（含固定 14）。其中 acceptor 的 `installed_by_this_task:false` 表示验收脚本自己不执行安装，安装已由上面的原入口独立完成，并非候选冒充已装。
- Chapter 原记录：`perf/acceptance/run-j4hu2occ/product_basics.json`，status=passed；`chapter basics` 回读 all_passed=true。delivery-evidence 只由 Chapter 生成；安装读回汇总 `build/accept/product-basics-install-readback.json` 不作为 product_basics 固定检查证据。
- 离屏渲染原件：`perf/acceptance/product-basics-19d85aed5d894dfd95b24aeb6fcf07b1/settings.png`（208,693 字节），已查看，实际原生配置/更新控件与版本 124 可见；没有上屏或让本人视觉确认。
- 安装日志：`build/accept/product-basics-install.log`；旧原件保存在 `/Users/tianli/.Trash/clip-pre-icloud-20261015-015547/Clip.app`，版本 1.2.1 (115)，主程序 SHA256 `06c71d2da3e01d3f4d4d33abc0c41c34c1373c040431cbb2cb450db622b5899c`。旧包可回溯，没有安装第二次或重建公开安装镜像。

配置与后台的实际边界：安装前后 `clip settings --json` 业务值完整相同（现有录制设置、快捷键、cloudEnabled=true、launchAtLogin=false），登录项仍 not_found，包内 CLI 软链及 `~/.local/bin/clip` 原链接保持。固定验收自身原件中的 owner_before/after 偏好 SHA 完全相同；安装前后整个真实偏好域 hash 不同，但键集合相同，检查历史 `appUpdateState` 的时间持续更新，因此不宣称所有缓存/窗口状态字节未变，也没有为恢复 hash 覆盖用户偏好。

原 PID 689 从头至尾未退出；`lsof -p 689 -a -d txt` 确认它仍映射旧包备份里的主程序。磁盘已装为 124，正在运行的常驻实例为旧 115，**没有称旧进程已运行新源码**。按本轮“现有后台保留”约束不擅自退出它；常驻实例切换由 Chapter 原重启阶段安排，不作为让本人手测的事项。辅助功能原 live 读数为 false，bundle/team 身份保持，未修改 TCC 或发授权提示。

本轮从 01:45 安装接续到 01:59 核验约 14 分钟；原候选编译/签名/来源登记约 1 分钟，修正后增量签名构建不到 1 分钟，安装与固定验收均已实际完成。四项缺口、固定验收和装机无受阻；苹果服务跨设备传输未测，本机隔离同步完整通过。剩余范围仅原常驻实例的独立重启及未来发布，本轮不处理。

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
