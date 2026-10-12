# Clip Mac App Store 商店版 · 2026-10-12

## 进度

- 已完成：store 工程、10 张正式图标、版本检查、APP_STORE 差异块及配置迁移界面；两条非商店编译条件和商店 typecheck；SDK build；下载版与商店版原 --selftest；沙盒容器、配置迁移、私有剪贴板监听；26 项离屏 UI 断言；Carbon 快捷键真实注册/分发/注销；包内容、沙盒日志与 LaunchServices 核验。源码已本地提交 `dcb2256965e7dc95c1551af9ac0201af15553859`（24 个文件），未 push。
- 正在做：无，源码、验证和报告已完成，按限定路径提交收尾。
- 下一步：主会话沿原脚本做正式签名、归档及上传，本轮没有执行。
- 卡点：没有编译或容器核心读写阻挡。系统授权 UI、容器外文件面板、真实 KVS 同步与登录项注册未测，详见文末。

开始时间 20:47:46（上海），截至 21:07:13 已完成源码提交和全部本轮测试，耗时 19 分 27 秒；本轮截止 21:17:46。其他会话的 project.yaml、perf、docs 差异、暂存与后台保留。不归档、不上传、不装机、不上屏，未改 /Applications、真实用户配置或登录项。

报告收尾于 21:10:35（上海），本轮含报告总耗时约 22 分 49 秒，在 30 分钟预算内。

## 范围与完成条件

可写范围限本仓自有 Sources、store/、本报告与 /private/tmp/mas-store/。共享 Sources/Shared、../ios、Tests、build.sh、project.yaml、README、官网不改。沿 Chapter `--pid 54469 --session chapter-task:d8e24fcd951d4ac8af1a837d765107ee`，每次写入先 check；不另开或释放声明。

完成条件：APP_STORE 商店版无 CLI/自带更新器；下载版行为保持；xcodegen/xcodebuild build、spec_lint、原有离屏自测和双版本 typecheck；测试副本沙盒权限、容器内数据/配置与日志核验；构建副本注销 LaunchServices；仅本轮文件本地提交。禁止归档、上传、装机、上屏、真实配置和登录项写入。

## 实施与证据

采用本地历史 + KVS 配置同步。CloudKit 历史归档需要当前无法验证的正式自动签名/描述文件；本轮按任务书允许的本地版分支，设置页隐藏历史 iCloud 页。KVS 使用现有共享 AppConfiguration，未修改共享副本。旧版配置可在旧版导出、商店版经系统文件面板导入；业务历史不随配置迁移。

写入源码：ClipbookApp.swift（移除商店 CLI 入口、生命周期更新菜单/窗口和 Deck 自动导入）、Native/Paster.swift（商店授权预检兼容）、Settings.swift（商店本地历史）、SettingsView.swift（隐藏 Deck，加入配置迁移）、AppModel.swift（未授权复制提示）、SelfTest.swift（商店不测已移除 CLI）、新增 StoreConfiguration.swift 与 StoreSelfTest.swift（测试副本限定的离屏容器验证）。store target 排除 CLI 与三个更新器共享文件，所有共享原文件保留且不改。

20:52 已过：下载版全源集 `swiftc -typecheck -D CLIP_LOCAL_DISTRIBUTION` 退出 0；商店 target 的 32 份源文件 `swiftc -typecheck -D APP_STORE -D APP_LIFECYCLE_KVS` 退出 0；`store/check.sh: ok (version 1.2.1, 4 entitlements, 10 icon PNGs)`；`xcodegen` 生成 Clip.xcodeproj；`spec_lint: 1 个 target 规格干净`。日志位于 `/private/tmp/mas-store/clipbook-evidence/typecheck-{download,store}.log`，均为空无诊断。

20:55 沙盒 `--store-self-test` 退出 0，home 与数据库均在 `~/Library/Containers/test.tianli.clipbook.store/Data/`，configuration_round_trip=true、cloud_archive=false。测试副本去掉正式 KVS 的受限 entitlement（ad-hoc 不能使用）；正式工程保留四项权限，真实 KVS 另待正式签名测。下载版第一次 --selftest 仅配置备份断言失败：本轮多设 APP_LIFECYCLE_SUPPORT_DIR，抢占了原 CLI 测试自己按隔离 home 推导的备份路径；已去掉此冗余变量按原入口重跑，未改生产/测试代码绕断言。

## 工程与功能差异

`store/project.yml` 的工程名与唯一 application target 都是 Clip；app 名 Clip.app、主程序沿用 Clipbook、包名 `cyou.tianli.clipbook`，macOS 14.0、arm64、Swift 5、自动签名、团队 B9LJH93LA4、加固运行时、版本 1.2.1、初始 build 1。上传脚本会从 ASC 获取正式构建号。AppKit、SwiftUI、Carbon、ApplicationServices、ServiceManagement、CoreData、CloudKit、CryptoKit、ImageIO、UniformTypeIdentifiers 和 sqlite3 均来自原源码/系统库；没有额外第三方二进制。

工程直接消费原 Sources 与只读的 PocketLibrary.swift 家族软链（实际源在 ../ios，不改）。商店只编译共享 AppConfiguration.swift；更新器/更新窗口/共享 CLI 三份文件在 target 中排除，原共享文件完全未改，`vendor-lifecycle.py --check` 返回 match。所有自有行为差异仅在 APP_STORE / !APP_STORE 条件里；非商店路径仍保留原逻辑。

`store/check.sh` 在每次 Xcode build 前运行，把版本同 cloud-project.yml（现版本唯一维护源）和已有公开 release.json 核对，并检查原 Cloud Info 键、沙盒、禁用例外权限、源码冲突副本和 10 张图标尺寸。生成的 Info.plist、Clip.entitlements 和 *.xcodeproj 被 store/.gitignore 忽略，均未进 Git。ExportOptions.plist 逐字复制 Initials 样板，plutil lint 通过。图标从最终 `icon/AppIcon.png` 生成，保留原 alpha，16 到 512@2x 共 10 张 PNG；最大 1024 像素，已 `git add -f` 并提交。

商店版对用户的变化：

- 仍是独立正常 Mac App，菜单栏附加入口、Dock/主窗口、原搜索/编辑/收藏/复制功能保留。
- 无 clip 命令及包内 CLI 软链；不连接下载版的 CLI 请求通知。不含自带更新器，也没有更新菜单或“配置与更新”窗口，更新由商店负责。
- 首版剪贴板历史仅本机，不显示 iCloud 历史归档页；配置同步另走 KVS，默认关闭。
- 不自动探测/导入真实 Deck 库，设置页不显示该入口。原 Deck 导入生产函数保留，下载版与夹具自测不变。
- 新的“配置迁移与同步”区提供导出、导入和可选 KVS。调用原 ClipPortableConfiguration 白名单和 AppConfiguration 的格式、验证、备份，不重写配置 schema。文件面板选择后的 URL 在访问期间 start/stopAccessingSecurityScopedResource；权限仅在本次读写期间需要，没有持久目录授权。
- 未授权自动粘贴时，先复制到剪贴板，窗口保留并提示“请切回目标应用按 ⌘V”；不自动弹授权框。授权后才沿原切换/合成粘贴路径。商店预检为 `AXIsProcessTrusted() || CGPreflightPostEventAccess()`，显式“去授权”仍由本人点击。
- 数据与偏好在沙盒容器中，不能直接读取下载版真实 Application Support。迁移步骤：旧下载版“配置与更新”导出配置文件，商店版设置页导入。只迁移白名单配置（含用户明确配置的快捷键）；不迁移历史、系统权限、登录项或凭据。

## 最终权限与配置同步选择

| Entitlement | 理由 |
| --- | --- |
| com.apple.security.app-sandbox = true | Mac App Store 沙盒要求，业务数据库和配置位于自身容器。 |
| com.apple.security.files.user-selected.read-write = true | 用户通过系统面板选择配置文件导出/导入，以及原图片导出。 |
| com.apple.security.network.client = true | 可选的复制链接网页标题获取；设置中可关闭，无监听服务。 |
| com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)$(CFBundleIdentifier) | 用户主动开启时同步可迁移配置，使用共享层 APP_LIFECYCLE_KVS。 |

没有 temporary-exception、Apple Events、全盘/Downloads 访问、后台 helper 或 App Group 权限。辅助功能、全局快捷键、登录项不是以上额外沙盒 entitlement。

选择 KVS 的原因：共享配置层已有该分支，沙盒无需拼接真实 iCloud Drive 路径；只增加既有编译条件和正式 KVS 权限。AppDelegate 用 config.start() 启动同一对象，设置区通过该对象拨开关、读状态和导入/导出。CloudKit 历史归档未带入首版：本机按任务约束不做身份/描述文件/自动签名修改，无法核实其正式签名可行性，所以明确采用任务书允许的本地历史版本。KVS 测试不冒充真实云同步。

## 验证命令与真实结果

本机工具链：`xcodebuild -version` → `Xcode 27.0 / Build version 27A266a`。仅证明本机 SDK build，未证明 App Store 上传兼容性；主会话原上传脚本自带 asc_toolchain 预检。

### 非商店源码和原有测试

在仓库根目录执行，两个 typecheck 都退出 0，日志无诊断：

```sh
xcrun swiftc -typecheck -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -module-cache-path /private/tmp/mas-store/clipbook-evidence/module-cache \
  -D CLIP_LOCAL_DISTRIBUTION Sources/Native/*.swift Sources/ClipbookApp.swift Sources/Shared/*.swift
xcrun swiftc -typecheck -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  -module-cache-path /private/tmp/mas-store/clipbook-evidence/module-cache \
  Sources/Native/*.swift Sources/ClipbookApp.swift Sources/Shared/*.swift
```

前者是公开本地版，后者是 build.sh/cloud-project.yml 不带 APP_STORE 的源码条件。没有跑会签名/公证/装机的 build.sh 或会打发行 ZIP 的 release-local.sh。

同原入口的纯编译和生产 --selftest，仅输出到指定临时目录：

```sh
xcrun swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  -module-cache-path /private/tmp/mas-store/clipbook-evidence/module-cache \
  -D CLIP_LOCAL_DISTRIBUTION Sources/Native/*.swift Sources/ClipbookApp.swift Sources/Shared/*.swift \
  -o /private/tmp/mas-store/clipbook-evidence/Clipbook-download
env -u APP_LIFECYCLE_SUPPORT_DIR \
  CLIPBOOK_PREFERENCES_SUITE=cyou.tianli.clipbook.mas-download-selftest \
  CLIPBOOK_HOME=/private/tmp/mas-store/clipbook-evidence/download-home \
  /private/tmp/mas-store/clipbook-evidence/Clipbook-download --selftest
```

最终退出 0，输出 `PASS public local update source: GitHub zengtianli/clipbook` 和 `✅ selftest 全部通过`，包含原 CLISelfTest。第一次多余的支持目录环境变量导致一项备份路径断言失败，纠正命令后全部通过，原失败日志保留。测试均不读写本人业务库或通用剪贴板。

### 商店类型检查与工程

商店 typecheck 的文件集按正式 target 还原，32 个文件，退出 0；执行方法：

```python
# 在仓库根目录，用 ~/Dev/.venv/bin/python -B 执行
from pathlib import Path
import subprocess, yaml, sys
sys.path.insert(0, '/Users/tianli/Dev/tools/dev/lib/tools/macapp/ios')
from spec_lint import target_swift_files
spec = yaml.safe_load(Path('store/project.yml').read_text())
files = target_swift_files(str(Path('store').resolve()), spec['targets']['Clip'])
subprocess.run(['xcrun', 'swiftc', '-typecheck', '-swift-version', '5', '-parse-as-library',
    '-target', 'arm64-apple-macos14.0', '-module-cache-path',
    '/private/tmp/mas-store/clipbook-evidence/module-cache-store',
    '-D', 'APP_STORE', '-D', 'APP_LIFECYCLE_KVS'] + files, check=True)
```

```sh
cd /Users/tianli/Apps/clip/mac/store
./check.sh
xcodegen generate
/Users/tianli/Dev/.venv/bin/python -B /Users/tianli/Dev/tools/dev/lib/tools/macapp/ios/spec_lint.py /Users/tianli/Apps/clip/mac/store
xcodebuild -project Clip.xcodeproj -scheme Clip -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath /private/tmp/mas-store/clipbook-dd \
  -jobs 4 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

真实输出：`store/check.sh: ok (version 1.2.1, 4 entitlements, 10 icon PNGs)`；`Created project at …/store/Clip.xcodeproj`；`✅ spec_lint: 1 个 target 规格干净`；`** BUILD SUCCEEDED **`、rc=0。首个完整 build 21.773 秒，之后修正离屏测试/图标透明度与补充配置落盘证据的两次增量 build 为 11.742 和 14.811 秒。最后包对应已提交源码。构建继承环境限 PATH/HOME/USER/LOGNAME/DEVELOPER_DIR/TMPDIR/语言；无证书操作、无 provisioning updates。每次 build 的 finally 都立即注销所有本轮 DD 下 .app。

只调用 asc_release 的纯函数 project_identity，返回 `{'scheme': 'Clip', 'bundle_id': 'cyou.tianli.clipbook', 'marketing_version': '1.2.1'}`；没有运行其联网 main 或上传脚本。共享验证：`~/Dev/.venv/bin/python -B ~/Dev/tools/dev/lib/tools/macapp/swift-shared/vendor-lifecycle.py --platform mac --target-source-dir Sources/Shared --check` → `Lifecycle sources match: Sources/Shared`。

### 产物与 ad-hoc 测试副本

构建产物 `/private/tmp/mas-store/clipbook-dd/Build/Products/Release/Clip.app`；复制到 `/private/tmp/mas-store/clipbook-test/Clip.app`，只将测试副本 CFBundleIdentifier 改为 `test.tianli.clipbook.store`。测试 entitlement 文件从生成的四项权限去掉 KVS，保留沙盒、用户选文件、出站网络三项；受限云权限不能用 ad-hoc 身份验证，正式 project.yml 未删。

```sh
codesign --force --sign - --options runtime \
  --entitlements /private/tmp/mas-store/clipbook-evidence/test.entitlements \
  /private/tmp/mas-store/clipbook-test/Clip.app
codesign --verify --deep --strict /private/tmp/mas-store/clipbook-test/Clip.app
codesign -d --entitlements :- /private/tmp/mas-store/clipbook-test/Clip.app
find /private/tmp/mas-store/clipbook-test/Clip.app -type f -perm +111
```

签名/校验退出 0；读取权限显示 app-sandbox/user-selected.read-write/network.client 均 true。find 只输出 `Contents/MacOS/Clipbook`；逐文件 file 判定 Mach-O 也只有这一份，包内软链为空。生成 Info 与原本地包逐键比较 `missing_existing_info_keys []`；当前 id=cyou.tianli.clipbook、executable=Clipbook、version=1.2.1、build=1、显示名 Clip、LSUIElement=false、最低系统 14.0、category=productivity、ITSAppUsesNonExemptEncryption=false。

### 真沙盒离屏运行

以下均只运行改包名的测试副本主程序，直接 exec，无 open、无正常 App 启动、无窗口排序/激活、无系统授权请求：

```sh
/private/tmp/mas-store/clipbook-test/Clip.app/Contents/MacOS/Clipbook --store-self-test
CLIPBOOK_PREFERENCES_SUITE=test.tianli.clipbook.store.selftest \
  /private/tmp/mas-store/clipbook-test/Clip.app/Contents/MacOS/Clipbook --selftest
/private/tmp/mas-store/clipbook-test/Clip.app/Contents/MacOS/Clipbook --shortcut-runtime-test
CLIPBOOK_BACKGROUND=1 \
  CLIPBOOK_HOME=/Users/tianli/Library/Containers/test.tianli.clipbook.store/Data/tmp/ui-home \
  CLIPBOOK_PREFERENCES_SUITE=test.tianli.clipbook.store.ui \
  /private/tmp/mas-store/clipbook-test/Clip.app/Contents/MacOS/Clipbook \
  --ui-self-test /Users/tianli/Library/Containers/test.tianli.clipbook.store/Data/tmp/ui-output
```

四个入口均 rc=0。容器入口原始结果：

```json
{"ok":true,"sandbox_container":"test.tianli.clipbook.store","home":"/Users/tianli/Library/Containers/test.tianli.clipbook.store/Data","store":"/Users/tianli/Library/Containers/test.tianli.clipbook.store/Data/Library/Application Support/Clipbook","configuration_directory":"/Users/tianli/Library/Containers/test.tianli.clipbook.store/Data/Library/Application Support/TianliApps/Configuration/cyou.tianli.clipbook","configuration_round_trip":true,"clipboard_poll":true,"cloud_archive":false,"accessibility_preflight":true}
```

实际创建容器；用默认 ClipStore 路径入库/读回/删除，配置同生产导出/导入函数恢复 maxItems 700（中间改为 900），容器内 pending-import.json 与 Backups 存在，恢复测试前的 maxItems。私有 pasteboard 的生产 Watcher.poll 读到新记录，未使用通用剪贴板。

原商店 --selftest 输出 `✅ selftest 全部通过`，只排除了该产品版已不编译的 CLI 自检。Carbon 输出 `PASS native Carbon registration → event handler → production action → unregister/re-register; no physical key sent`，临时注册四修饰键 F20，使用应用 Carbon 事件触发生产回调，随后注销；不发送真实键、不用 ⌘⇧V。该入口在 APP_STORE 下先设置 .prohibited，未进 Dock/上屏。

UI 输出 `ok:true`，26/26 checks，包含默认无键注册、搜索/筛选、选择/复制多条、编辑/合并/删除 blob、收藏、隐藏/恢复、窗口不上屏、不抢焦点、通用剪贴板不变、设置截图非空等。只离屏渲染 main.png/settings.png。已查看设置截图：新的配置区可见、Deck 与历史 iCloud 页已隐藏；此自测不创建正式 AppDelegate，状态显示“配置尚未初始化”，不将该图当作正常启动/KVS 验收。

### 沙盒日志与 LaunchServices

按要求执行 `/usr/bin/log show --last 5m --style compact --predicate 'eventMessage CONTAINS "Sandbox:"'`，没有匹配 Clipbook 的行；又按 process/name/secinitd/sandbox/deny 扩查同一 10 分钟窗口。`secinitd` 对本轮 PID 69113、78193、78201、78202、78203 均记录 `AppSandbox request successful`，和入口返回的容器证据一致。

已观察到的拒绝/扩展失败全部列出，不称日志零拒绝：

- 下载版临时裸二进制两次自测（PID 69112、70095）各有 `System Policy: Clipbook-download … deny(1) forbidden-extension-process-mismatch`。按测试时刻和代码推断，涉及原自测发行文件 URL 的系统权限扩展检查；未取得调用栈。原自测最终通过，但不将它当作外部文件授权可用的证据。
- 商店原 --selftest（PID 78201）有 CFPasteboard `Failed sandbox check for path`、`Sandbox extension creation failed`、public.file-url 扩展立即取得失败（-20）、缓存无权限扩展/Failed to get a sandbox extension（-9）。原 SelfTest 明确向私有剪贴板写 `/tmp` URL 来检查“文件类型优先”；沙盒未获真实 /tmp 文件夹授权，这个夹具不能签发读权限扩展。类型判定断言仍通过，但不代表可授权给另一个 App 读取该目录。保持原夹具与权限边界，无例外权限绕过。
- 没有观察到本轮容器数据库/配置访问的 deny；生产容器入口、UI、Carbon 入口成功。日志可能漏报，不以没看到 deny 替代上面的实际读写证据。

每次 build/测试均注销本轮包，最后再次执行 `lsregister -u` 与 `lsregister -dump`。重复注销 DD 包返回 -10814（已不在扫描/登记中），测试副本注销 rc=0；最终 dump 中所有含 `/mas-store/clipbook-` 的记录 **0**，本轮测试进程 **0**。没有注销、退出或重启 /Applications 的现装实例。

## 未测范围与原因

- 正式签名、自动描述文件、归档、上传、审核：本轮明确禁止，且本机按任务约束不创建身份。SDK build 及 ad-hoc 沙盒测试不冒充发行签名。
- 真实 KVS 跨设备配置同步/账户状态：需要正式带权限的签名与 iCloud；ad-hoc 副本去掉 KVS，只有共享格式与容器读写通过。
- 用户点击辅助功能/事件发送授权、正常 App 的真实自动粘贴及前台切换：会弹系统对话框/上屏，不测。preflight=true 可能继承启动终端授权，不是商店身份授权流程通过。未授权分支保留窗口与手动 ⌘V 提示已编译，真实未授权 GUI 情况未触发。
- 真实系统文件面板导入/导出容器外文件：需要本人点面板；同生产 transfer 函数的容器内往返已通过。未验证 Finder 文件复制的跨 App 授权、历史文件路径跨重启重复制（上面的 /tmp 夹具不能证明）。
- 登录项 SMAppService：读状态代码保留，编译通过；未 register/unregister，避免改变本人登录项。
- 通用剪贴板的日常跨 App 轮询、复制声音与正常 Dock/窗口流程：未在正常身份启动商店版；私有剪贴板 poll、自测与无通用剪贴板副作用通过。未播放提示音。
- 完整像素效果：离屏 cacheDisplay 存在原测试记录的选中材质/文字黑块限制，仅证明布局和内容；未上屏复核。

## Review notes (English)

1. Launch Clip. Copy a short non-sensitive sentence in TextEdit, then return to Clip; the text appears in the clipboard library.
2. Enter a word in the search field, select the matching item, edit it in the right pane, and click Save.
3. Add an item to a collection or pin it. Select one or more items and press Command-C to copy the selected content.
4. Paste in TextEdit with Command-V. Clip works without Accessibility permission; direct automatic pasting is optional and only available after the user grants permission in Settings.
5. Open Settings → General to export/import settings or optionally enable iCloud settings sync. Clipboard history stays local. Updates are delivered by the Mac App Store; this build includes no command-line tool or self-updater.

## 截图与主会话接续

仓库现成的真实产品截图（原本地版，商店描述应按本报告差异调整）：`docs/demo/overview.png`、`docs/demo/search.png`、`docs/demo/edit.png`、`docs/demo/organize.png`；教程 poster 为 `docs/demo/ai-sample/poster.jpg`。本轮沙盒离屏截图在 `~/Library/Containers/test.tianli.clipbook.store/Data/tmp/ui-output/{main,settings}.png`，有上述渲染限制，不直接作为正式商店截图。

主会话在本轮写入范围外接续的确定动作：

1. 在 ASC 配置此包名的 Mac App 记录、免费定价及商店元数据；确认 App ID 的 KVS 能力和自动签名身份。使用原 `push-testflight.sh --platform macos /Users/tianli/Apps/clip/mac/store`，由该脚本做发布工具链/版本/构建号预检、归档、上传和构建挂接，本轮未执行。
2. 正式 TestFlight/签名版由本人核辅助功能未授权/授权后粘贴、真实打开/保存面板、Finder 文件路径跨重启、KVS 两台设备、登录项与正常窗口；这些不以本轮替身测试冒充。
3. 在 project.yaml/CLAUDE/README/官网登记两种发行面和本报告功能差别；可把 store/check.sh 接进原发版维护步骤。这些文件本轮按任务书不改。

本轮临时目录保留构建产物、测试副本与日志：`/private/tmp/mas-store/clipbook-{dd,test,evidence}`。测试容器 `~/Library/Containers/test.tianli.clipbook.store` 由系统/测试副本创建，包含测试数据库、配置备份和离屏图；不从外部 shell 删除容器，避免额外系统提示。所有本轮产物已注销，无残留测试进程。源工程可接续，**未归档、未上传、未安装、未发布**。
