import AppKit
import SwiftUI

/// Shared contract for the three isolated acceptance entries
/// (`--ui-self-test <outdir>`, `--recovery-test`, `--privacy-test`).
///
/// Every entry refuses to run unless the process is an isolated background preview
/// (CLIPBOOK_HOME + CLIPBOOK_PREFERENCES_SUITE + CLIPBOOK_BACKGROUND=1). No window is ordered
/// on screen, nothing activates, no global hotkey is registered and NSPasteboard.general is
/// never written. Output: `PASS/FAIL name` lines, then one JSON line.
@MainActor
final class AcceptanceReport {
    private(set) var checks: [(String, Bool)] = []
    var screenshots: [String] = []
    var notCovered: [String] = []

    func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        let d = detail().replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "⏎")
        print("\(ok ? "PASS" : "FAIL") \(name)\(d.isEmpty ? "" : " — \(d)")")
        checks.append((name, ok))
    }

    var ok: Bool { !checks.isEmpty && checks.allSatisfy(\.1) }

    /// Prints the single-line JSON summary last; exit code 0 iff every check passed.
    func finish() -> Int32 {
        var map: [String: Bool] = [:]
        for (name, value) in checks { map[name] = (map[name] ?? true) && value }
        let payload: [String: Any] = ["ok": ok, "checks": map, "screenshots": screenshots, "not_covered": notCovered]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"ok\":false}".utf8)
        print(String(decoding: data, as: UTF8.self))
        return ok ? 0 : 1
    }

    /// Refuse to touch user data, preferences or the general pasteboard.
    static func isolatedRoot(_ entry: String) -> URL? {
        let env = ProcessInfo.processInfo.environment
        var reasons: [String] = []
        if (env["CLIPBOOK_HOME"] ?? "").isEmpty { reasons.append("CLIPBOOK_HOME 未设置") }
        if (env["CLIPBOOK_PREFERENCES_SUITE"] ?? "").isEmpty { reasons.append("CLIPBOOK_PREFERENCES_SUITE 未设置") }
        if env["CLIPBOOK_BACKGROUND"] != "1" { reasons.append("CLIPBOOK_BACKGROUND 不是 1") }
        if reasons.isEmpty, !ProductIdentity.backgroundPreview { reasons.append("ProductIdentity.backgroundPreview 为 false") }
        if reasons.isEmpty, ProductIdentity.pasteboard === NSPasteboard.general { reasons.append("隔离 pasteboard 未生效") }
        guard reasons.isEmpty else {
            let why = "\(entry) 拒绝运行：" + reasons.joined(separator: "；") + "（只在隔离 home / 偏好 / 后台模式下运行）"
            FileHandle.standardError.write(Data((why + "\n").utf8))
            let payload: [String: Any] = ["ok": false, "checks": [String: Bool](), "screenshots": [String](), "not_covered": [String](), "error": why]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return nil
        }
        return URL(fileURLWithPath: env["CLIPBOOK_HOME"]!, isDirectory: true)
    }

    static func settle(_ seconds: TimeInterval = 0.3) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
    }

    /// Run a main-actor async operation while spinning the run loop, bounded by `timeout`.
    final class Box<T> { var value: T?; var done = false }
    static func wait<T>(_ timeout: TimeInterval, _ op: @escaping @MainActor () async -> T) -> (value: T?, elapsed: TimeInterval) {
        let box = Box<T>()
        let start = Date()
        Task { @MainActor in box.value = await op(); box.done = true }
        while !box.done, Date().timeIntervalSince(start) < timeout {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
        return (box.value, Date().timeIntervalSince(start))
    }

    static func png(_ w: Int, _ h: Int, _ color: NSColor) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        color.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w / 2, height: h / 2).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    static func rtf(_ s: String) -> Data {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        return a.rtf(from: NSRange(location: 0, length: a.length), documentAttributes: [:])!
    }
}

/// Never becomes key/main; the capture window is never ordered in.
private final class OffscreenCapturePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Records registration attempts instead of touching the system hotkey table.
@MainActor
private final class RecordingKeyBackend: ClipKeyRegistration {
    var onPress: ((UInt32) -> Void)?
    var registerCalls = 0
    func register(_ chord: ClipKey, id: UInt32) -> OSStatus { registerCalls += 1; return noErr }
    func unregister(_ id: UInt32) {}
}

@MainActor
enum UISelfTest {
    struct Snapshot { let rep: NSBitmapImageRep; let stddev: Double; let distinct: Int }

    /// Draw the production view hierarchy into a bitmap without putting it on screen.
    static func capture(_ view: NSView) -> Snapshot? {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        var sum = 0.0, sq = 0.0, n = 0.0
        var colors = Set<UInt32>()
        let step = max(2, rep.pixelsWide / 400)
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let l = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                sum += l; sq += l * l; n += 1
                colors.insert(UInt32(c.redComponent * 31) << 10 | UInt32(c.greenComponent * 31) << 5 | UInt32(c.blueComponent * 31))
            }
        }
        guard n > 0 else { return Snapshot(rep: rep, stddev: 0, distinct: 0) }
        let mean = sum / n
        return Snapshot(rep: rep, stddev: (max(0, sq / n - mean * mean)).squareRoot(), distinct: colors.count)
    }

    static func run(outdir: String?) -> Int32 {
        let report = AcceptanceReport()
        guard let isolated = AcceptanceReport.isolatedRoot("--ui-self-test") else { return 2 }
        guard let outdir, !outdir.hasPrefix("-") else {
            print("用法：Clipbook --ui-self-test <outdir>")
            report.check(false, "outdir_argument"); return report.finish()
        }
        let out = URL(fileURLWithPath: outdir, isDirectory: true)
        let root = isolated.appendingPathComponent("ui-selftest-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let board = NSPasteboard(name: .init("cyou.tianli.clipbook.ui-selftest.\(UUID().uuidString)"))
        var panels: [NSPanel] = []
        var shortcuts: ClipShortcuts?
        defer {
            shortcuts?.suspend()
            for p in panels { p.contentView = nil; p.close() }
            board.releaseGlobally()
            AppModel.shared?.watcher.stop()
            try? fm.removeItem(at: root)
        }
        report.notCovered = [
            "真实鼠标点击 / 键盘事件分发（按约束不合成事件；键盘导航由 --keyboard-window-test 与 --selftest 覆盖）",
            "窗口上屏、激活与 Dock/⌘Tab 行为（按约束不 order 上屏、不激活）",
            "粘贴到前一个应用（需要辅助功能与激活，隔离模式下生产代码只写演示 pasteboard）",
            "删除/清空确认对话框（NSAlert.runModal 为模态 UI）",
            "像素级外观：离屏 cacheDisplay 不绘制选中高亮/强调材质（侧栏选中行呈黑块、选中标签为空白），截图只验收布局与内容非空白",
        ]
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let generalBefore = NSPasteboard.general.changeCount
            let settings = AppSettings.shared
            settings.paused = false; settings.copySound = false; settings.fetchLinkTitles = false

            // 21 fixtures across every visual kind, oldest first.
            let store = try ClipStore(home: root)
            let t0 = Date().addingTimeInterval(-3600)
            var n = 0
            func add(_ c: Capture) throws -> ClipItem { n += 1; return try store.ingest(c, at: t0.addingTimeInterval(Double(n))) }
            func cap(_ kind: ClipItem.Kind, _ text: String, app: String = "TextEdit", bundle: String = "com.apple.TextEdit") -> Capture {
                Capture(kind: kind, text: text, appName: app, appBundle: bundle)
            }
            let texts = ["会议纪要：周三下午评审 needle 事项", "今天的待办：整理剪贴板历史", "Quarterly numbers look fine",
                         "收件地址：杭州市西湖区", "needle in a haystack", "短句", "多行文本\n第二行\n第三行", "The quick brown fox"]
            var fixtures: [ClipItem] = []
            for t in texts { fixtures.append(try add(cap(Classifier.kind(of: t), t))) }
            for l in ["https://www.apple.com/macos/", "https://repo.example/clip", "https://example.com/docs?q=1"] {
                fixtures.append(try add(cap(.link, l, app: "Safari", bundle: "com.apple.Safari")))
            }
            for c in ["#2563EB", "#DC2626", "rgb(16, 185, 129)"] { fixtures.append(try add(cap(.color, c, app: "Figma", bundle: "com.figma.Desktop"))) }
            for code in ["func add(a: Int) -> Int {\n    return a + 1\n}", "def f(x):\n    return x * 2\n", "SELECT id FROM items\nWHERE pinned = 1;"] {
                fixtures.append(try add(cap(Classifier.kind(of: code), code, app: "Xcode", bundle: "com.apple.dt.Xcode")))
            }
            for (i, color) in [NSColor.systemTeal, .systemOrange, .systemPurple].enumerated() {
                let data = AcceptanceReport.png(64 + i * 16, 48, color)
                fixtures.append(try add(Capture(kind: .image, text: "图片 \(64 + i * 16)×48", imagePNG: data, width: 64 + i * 16, height: 48,
                                                appName: "Preview", appBundle: "com.apple.Preview")))
            }
            fixtures.append(try add(Capture(kind: .richText, text: "富文本段落", rtf: AcceptanceReport.rtf("富文本段落"), appName: "Notes", appBundle: "com.apple.Notes")))
            let kinds = Set(fixtures.map(\.kind))
            report.check(fixtures.count == 21 && kinds.isSuperset(of: [.text, .link, .color, .code, .image, .richText]),
                         "fixtures_seeded", "\(fixtures.count) 条，类型 \(kinds.map(\.rawValue).sorted())")

            let model = try AppModel(home: root)
            AppModel.shared = model
            model.watcher.stop()
            report.check(model.items.count == fixtures.count && model.totalAll == fixtures.count && model.items.first?.id == fixtures.last?.id,
                         "model_loads_isolated_store", "items \(model.items.count) total \(model.totalAll)")

            // Real MainView in a never-ordered, non-key panel.
            let main = OffscreenCapturePanel(contentRect: NSRect(x: -20000, y: -20000, width: 1380, height: 760),
                                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            main.isReleasedWhenClosed = false
            panels.append(main)
            let host = NSHostingView(rootView: MainView(model: model, hideWindow: {}))
            main.contentView = host
            AcceptanceReport.settle(1.0)
            report.check(!main.isVisible && !main.isKeyWindow && !NSApp.isActive, "window_stays_offscreen_and_inactive")
            let mainFrame = host.superview ?? host
            if let shot = capture(mainFrame) {
                let url = out.appendingPathComponent("main.png")
                try shot.rep.representation(using: .png, properties: [:])?.write(to: url)
                report.screenshots.append("main.png")
                report.check(shot.rep.size == mainFrame.bounds.size && Int(host.bounds.width) == 1380 && host.bounds.height >= 760
                             && shot.rep.pixelsWide >= 1380, "main_screenshot_size",
                             "位图 \(shot.rep.pixelsWide)×\(shot.rep.pixelsHigh)，内容 \(host.bounds.size)")
                report.check(shot.stddev > 0.03 && shot.distinct >= 24, "main_screenshot_not_blank",
                             String(format: "亮度标准差 %.3f，量化颜色 %d", shot.stddev, shot.distinct))
            } else { report.check(false, "main_screenshot_size", "无法创建位图"); report.check(false, "main_screenshot_not_blank") }

            // Search.
            model.search = "needle"
            report.check(model.items.count == 2 && model.items.allSatisfy { $0.text.contains("needle") } && model.total == 2,
                         "search_filters_items", "命中 \(model.items.count)")
            model.search = "不存在的关键词-zz"
            report.check(model.items.isEmpty && model.total == 0, "search_no_match_empty")
            model.search = ""

            // Kind filter through the sidebar selection.
            model.sidebar = .kind(.color)
            let colorOK = model.items.count == 3 && model.items.allSatisfy { $0.kind == .color }
            model.sidebar = .kind(.image)
            report.check(colorOK && model.items.count == 3 && model.items.allSatisfy { $0.kind == .image }, "kind_filter", "color 3 / image 3")
            model.sidebar = .app("com.apple.Safari")
            report.check(model.items.count == 3 && model.items.allSatisfy { $0.appBundle == "com.apple.Safari" }, "source_app_filter")
            model.sidebar = .all
            report.check(model.items.count == fixtures.count, "filter_reset_all")

            // Selection: click, ⌘-click, ⇧-range, select all.
            let ids = model.items.map(\.id)
            model.click(ids[0], modifiers: [])
            let single = model.selection == [ids[0]] && model.detail?.id == ids[0]
            model.click(ids[3], modifiers: [.command])
            let toggled = model.selection == [ids[0], ids[3]]
            model.click(ids[6], modifiers: [.shift])
            let ranged = model.selection == Set(ids[3...6])
            report.check(single && toggled && ranged, "selection_click_command_shift")
            model.selectAll()
            report.check(model.selection == Set(ids) && model.selection.count == fixtures.count, "select_all")

            // Copy the selection to an isolated pasteboard, in display order.
            let textItems = model.items.filter { $0.kind == .text }
            let first = textItems[0], second = textItems[2]
            model.click(second.id, modifiers: []); model.click(first.id, modifiers: [.command])
            model.copySelection(pasteboard: board)
            report.check(board.string(forType: .string) == first.text + "\n\n" + second.text, "copy_selection_display_order",
                         "\(board.string(forType: .string)?.prefix(40) ?? "nil")")
            let image = model.items.first { $0.kind == .image }!
            model.click(image.id, modifiers: []); model.click(first.id, modifiers: [.command])
            model.copySelection(pasteboard: board)
            let entries = board.pasteboardItems ?? []
            report.check(entries.count == 2 && entries.contains { $0.data(forType: .png) != nil } && entries.contains { $0.string(forType: .string) == first.text },
                         "copy_selection_mixed_image_text", "\(entries.count) 项")
            report.check(NSPasteboard.general.changeCount == generalBefore, "general_pasteboard_untouched")

            // Pin / unpin.
            let oldest = model.items.last!
            model.togglePin(oldest)
            let pinnedTop = model.items.first?.id == oldest.id && model.items.first?.pinned == true
            model.togglePin(model.items.first!)
            report.check(pinnedTop && model.items.last?.id == oldest.id && model.items.last?.pinned == false, "toggle_pin")

            // Edit and save re-classifies.
            let editable = model.items.first { $0.text == "短句" }!
            model.saveText(editable, text: "https://edited.example/page")
            let edited = try model.store.item(id: editable.id)
            report.check(edited?.kind == .link && edited?.text == "https://edited.example/page", "save_text_reclassifies")

            // Merge (production AppModel.merge).
            let a = model.items.first { $0.text == "Quarterly numbers look fine" }!, b = model.items.first { $0.text == "The quick brown fox" }!
            let beforeMerge = model.totalAll
            model.merge([a.id, b.id])
            let merged = model.selection.first.flatMap { try? model.store.item(id: $0) }
            report.check(model.selection.count == 1 && merged?.text == a.text + "\n\n" + b.text && model.totalAll == beforeMerge + 1,
                         "merge_selection", "\(merged?.text.replacingOccurrences(of: "\n", with: "⏎") ?? "nil")")

            // Delete an image: row and blob gone.
            let doomed = model.items.first { $0.kind == .image }!
            let blob = model.store.blobURL(doomed)!
            let beforeDelete = model.totalAll
            model.selection = [doomed.id]
            model.delete(model.selection)
            report.check(try model.store.item(id: doomed.id) == nil && !model.items.contains { $0.id == doomed.id }
                         && model.totalAll == beforeDelete - 1 && !fm.fileExists(atPath: blob.path) && model.selection.isEmpty,
                         "delete_removes_row_and_blob")

            // Hide/show the interface the way AppDelegate.hideWindow/showWindow do, minus ordering.
            let keep = Set(model.items.prefix(2).map(\.id))
            model.selection = keep
            model.savedDraft = .init(id: keep.first!, text: "未保存的草稿", title: "", rich: false)
            main.contentView = nil
            model.suspendInterface()
            let suspended = !model.interfaceActive && Set(model.items.map(\.id)) == keep
            _ = try model.store.ingest(Capture(kind: .text, text: "隐藏期间的新复制", appName: "T", appBundle: "t"))
            model.reload()
            let frozen = model.items.count == 2
            model.resumeInterface()
            main.contentView = NSHostingView(rootView: MainView(model: model, hideWindow: {}))
            AcceptanceReport.settle(0.4)
            report.check(suspended && frozen, "suspend_interface_releases_page", "暂停后仅保留所选 \(keep.count) 条")
            report.check(model.interfaceActive && model.selection == keep && model.items.contains { $0.text == "隐藏期间的新复制" }
                         && model.savedDraft?.text == "未保存的草稿", "resume_interface_keeps_selection_and_draft")

            // Settings: production SettingsView with the production ClipShortcuts, backend recorded.
            let backend = RecordingKeyBackend()
            let center = ClipShortcuts(defaults: AppPreferences.defaults, backend: backend, monitorsEnabled: false) { _ in }
            shortcuts = center
            report.check(ClipShortcuts.defaultBindings.isEmpty && center.bindings.isEmpty && backend.registerCalls == 0,
                         "default_shortcuts_empty_none_registered", "绑定 \(center.bindings.count)，注册调用 \(backend.registerCalls)")
            let sp = OffscreenCapturePanel(contentRect: NSRect(x: -20000, y: -20000, width: 620, height: 650),
                                           styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            sp.isReleasedWhenClosed = false
            panels.append(sp)
            let sHost = NSHostingView(rootView: SettingsView(model: model, settings: settings, shortcuts: center))
            sp.contentView = sHost
            AcceptanceReport.settle(0.8)
            let settingsFrame = sHost.superview ?? sHost
            if let shot = capture(settingsFrame) {
                try shot.rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("settings.png"))
                report.screenshots.append("settings.png")
                report.check(shot.rep.size == settingsFrame.bounds.size && Int(sHost.bounds.width) == 620 && sHost.bounds.height >= 650,
                             "settings_screenshot_size", "位图 \(shot.rep.pixelsWide)×\(shot.rep.pixelsHigh)，内容 \(sHost.bounds.size)")
                report.check(shot.stddev > 0.03 && shot.distinct >= 12, "settings_screenshot_not_blank",
                             String(format: "亮度标准差 %.3f，量化颜色 %d", shot.stddev, shot.distinct))
            } else { report.check(false, "settings_screenshot_size"); report.check(false, "settings_screenshot_not_blank") }
            report.check(backend.registerCalls == 0 && center.bindings.isEmpty, "settings_render_registers_nothing")
            report.check(NSPasteboard.general.changeCount == generalBefore && !NSApp.isActive && panels.allSatisfy { !$0.isVisible },
                         "no_focus_or_general_pasteboard_side_effects")
        } catch {
            report.check(false, "ui_self_test_error", "\(error)")
        }
        return report.finish()
    }
}
