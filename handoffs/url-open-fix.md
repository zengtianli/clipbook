# Clips 冷启动 URL 修复

2026-09-07，Folio 同类入口排查发现：已运行时 `clipbook://show?q=...` 搜索与 settings 正常；正常退出后用 show 链接启动，进程已运行但无目标窗口，CUA 两次无窗口超时；再发一次 show 才出现搜索词。

旧实现直到 applicationDidFinishLaunching 才注册 kAEGetURL。改用 NSApplicationDelegate.application(_:open:)，窗口就绪前收进 pendingURLs，didFinishLaunching 创建窗口后依次执行原 handleURL。未改快捷键、界面布局和数据目录。

修复构建通过已有全部 selftest。实际打包版冷启动第一次 show 即显示 CLIPS_FIXED_COLD_20260907；运行中 show 切为 CLIPS_FIXED_WARM_20260907，hide 后 toggle 恢复同一搜索窗口。CUA 回读确认。共享 fleet_audit --entrypoints 增加旧版晚注册失败样本，test_fleet_entrypoints.py 同时验证正常的早注册、delegate 和 SwiftUI 路由。

构建仍复用总部 Xcode 选择器与 CodingKey 门。静态检查不能证明 UI 动作成功，应用事件变更需重复以上打包版验收。
