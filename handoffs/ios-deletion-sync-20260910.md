# iOS Clip 删除修复的 Mac 消费端同步

2026-09-10，本次只处理 iOS 首次上架所关联的共享库一致性；未安装、未发布 Mac 应用。

## 来源与范围

- 责任源：`/Users/tianli/Apps/ios/clip-ios/01-源程序/Shared/ClipLibrary.swift`。
- Mac 消费副本：`Sources/Native/PocketLibrary.swift`。修改前工作树干净；逐行核查表明，两边当前差异仅为此次删除数据清理与缩略图缓存修复，没有须保留的额外 Mac 分支。
- 使用最小补丁同步 `mutate` 中两段代码。删除后清空正文、标题、来源、收藏标志、图片与缩略图，保存成功后驱逐该条缩略图缓存；保留 key、removed 和 updatedAt 供删除标记与去重使用。
- 同步后两份文件的 SHA256 一致：`320669e2bdec4bec8654c44fb194d1ae157c685da038e6d3edf76e57d6400190`。
- 未修改 iOS 冻结源、Core Data 模型、Mac 主剪贴板库、快捷键、bundle ID、版本定义或安装路径。

## 验证

`tests/PocketLibraryRegression.swift` 直接编译并调用生产 `PocketLibrary.swift`，使用随机临时目录和独立 UserDefaults suite，显式 `localOnly: true`，结束清理测试数据。23 个断言全部通过，覆盖：删除后的持久化字段、重开数据库、Mac `revive: false` 归档不复活已删条目、用户显式重新保存、真实 PNG 生成与缓存预热、删除后通过旧 PocketClip 也不能读出原图/缓存缩略图。

```bash
cd /Users/tianli/Apps/mac/clipbook
source /Users/tianli/Dev/tools/dev/lib/tools/macapp/xcode_env.sh
xcode_env_use macosx
xcrun swiftc -parse-as-library Sources/Native/PocketLibrary.swift tests/PocketLibraryRegression.swift -o /tmp/clip-pocket-regression-20260910
/tmp/clip-pocket-regression-20260910
./build-cloud.sh --build-only
git diff --check
```

- 生产库回归：退出 0，`PASS: PocketLibrary production regression (23 checks, isolated store, iCloud disabled)`。
- Mac Release 构建：退出 0，日志 `build/cloud-build.log` 显示 `BUILD SUCCEEDED`；使用共享 xcode_env 选出的 Xcode 27.0 Beta 6 / macOS SDK 27.0。
- 构建脚本内既有 `--selftest` 全部通过；签名严格验证、CloudKit 描述文件存在检查、catalog 与 Info.plist 命名核对通过。输出包为 `.dd-cloud/Build/Products/Release/Clipbook.app`。
- `git diff --check` 退出 0。

## 实际边界

以上证明共享源码已对齐、生产函数回归和 Mac 本地包构建通过。未对该包装机，也未完成与 iOS 最终送审二进制的真实 CloudKit 往返验收。Beta 工具链的本地构建不证明 App Store 送审资格。

Mac 主库和云归档仍独立：`MacClipSync.receive` 将云端新条目导入主库，Mac 自己的留存/删除不会完整双向镜像到云端；iOS 删除同步历史也不声称立即清除 Mac 已导入的独立主库、系统缓存或历史备份。此约定已在设置页明确，本次保留。
