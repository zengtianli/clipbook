import AppKit
import Carbon.HIToolbox
import SwiftUI

/// `Clipbook --l10n-self-test <outdir>`: the interface in the language this process runs in (`-AppleLanguages`),
/// drawn offscreen for `chapter l10n shots`. Same isolation contract as `--ui-self-test` (CLIPBOOK_HOME,
/// CLIPBOOK_PREFERENCES_SUITE, CLIPBOOK_BACKGROUND=1): activation policy prohibited, nothing ordered on screen,
/// no hot key registered, the general pasteboard untouched. Fixtures are written in the interface language, so the
/// English pictures carry no Chinese user data.
@MainActor
enum L10nShots {
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class NoKeys: ClipKeyRegistration {
        var onPress: ((UInt32) -> Void)?
        var registerCalls = 0
        func register(_ chord: ClipKey, id: UInt32) -> OSStatus { registerCalls += 1; return noErr }
        func unregister(_ id: UInt32) {}
    }

    static func run(outdir: String?) -> Int32 {
        let report = AcceptanceReport()
        guard let isolated = AcceptanceReport.isolatedRoot("--l10n-self-test") else { return 2 }
        guard let outdir, !outdir.hasPrefix("-") else { report.check(false, "outdir_argument"); return report.finish() }
        let out = URL(fileURLWithPath: outdir, isDirectory: true)
        let root = isolated.appendingPathComponent("l10n-selftest-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        var panels: [NSPanel] = []
        let zh = L10n.chinese
        defer {
            for p in panels { p.contentView = nil; p.close() }
            AppModel.shared?.watcher.stop()
            try? fm.removeItem(at: root)
        }
        func shot(_ view: some View, _ name: String, _ size: NSSize) {
            let panel = Panel(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.title = ProductIdentity.name
            panels.append(panel)
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            AcceptanceReport.settle(0.9)
            let frame = host.superview ?? host
            guard let snapshot = UISelfTest.capture(frame),
                  let data = snapshot.rep.representation(using: .png, properties: [:]),
                  (try? data.write(to: out.appendingPathComponent(name + ".png"))) != nil else {
                report.check(false, "shot_\(name)"); return
            }
            report.screenshots.append(name + ".png")
            report.check(snapshot.stddev > 0.02 && !panel.isVisible && !panel.isKeyWindow, "shot_\(name)",
                         "\(snapshot.rep.pixelsWide)×\(snapshot.rep.pixelsHigh)")
        }
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            let generalBefore = NSPasteboard.general.changeCount
            let settings = AppSettings.shared
            settings.paused = false; settings.copySound = false; settings.fetchLinkTitles = false

            // Menus: the production main menu and the menu bar menu, written out as one picture of their titles.
            let titles = AppDelegate().menuTitlesForCapture()
            let stack = VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                    Text(verbatim: title).font(title.hasPrefix("▸") ? .headline : .body)
                }
            }.padding(16).frame(width: 520, alignment: .leading)
            shot(stack, "menus", NSSize(width: 540, height: CGFloat(titles.count) * 22 + 60))
            report.check(!titles.isEmpty, "menus_listed", "\(titles.count)")
            let store = try ClipStore(home: root)
            let t0 = Date().addingTimeInterval(-7200)
            var n = 0
            func add(_ c: Capture) throws -> ClipItem { n += 1; return try store.ingest(c, at: t0.addingTimeInterval(Double(n) * 300)) }
            func cap(_ text: String, app: String = "TextEdit", bundle: String = "com.apple.TextEdit") -> Capture {
                Capture(kind: Classifier.kind(of: text), text: text, appName: app, appBundle: bundle)
            }
            let texts = zh
                ? ["会议纪要：周三下午评审发布计划", "今天的待办：整理剪贴板历史", "收件地址：杭州市西湖区文三路 100 号", "多行文本\n第二行\n第三行"]
                : ["Meeting notes: release review on Wednesday", "Today: tidy up the clipboard history", "Ship to: 100 Market Street, San Francisco", "Several lines\nsecond line\nthird line"]
            for t in texts { _ = try add(cap(t)) }
            for l in ["https://www.apple.com/macos/", "https://example.com/docs?q=1"] { _ = try add(cap(l, app: "Safari", bundle: "com.apple.Safari")) }
            for c in ["#2563EB", "rgb(16, 185, 129)"] { _ = try add(cap(c, app: "Figma", bundle: "com.figma.Desktop")) }
            _ = try add(cap("func add(a: Int) -> Int {\n    return a + 1\n}", app: "Xcode", bundle: "com.apple.dt.Xcode"))
            _ = try add(Capture(kind: .image, text: zh ? "图片 96×48" : "Image 96×48", imagePNG: AcceptanceReport.png(96, 48, .systemTeal), width: 96, height: 48,
                                appName: "Preview", appBundle: "com.apple.Preview"))
            let rich = zh ? "富文本段落" : "A rich text paragraph"
            _ = try add(Capture(kind: .richText, text: rich, rtf: AcceptanceReport.rtf(rich), appName: "Notes", appBundle: "com.apple.Notes"))
            let model = try AppModel(home: root)
            AppModel.shared = model
            model.watcher.stop()
            _ = model.createCollection(name: zh ? "工作" : "Work", color: "#2563eb", icon: "briefcase")
            _ = model.createCollection(name: zh ? "常用回复" : "Replies", color: "#16a34a", icon: "text.bubble")
            model.reload()
            report.check(model.items.count == n, "fixtures_seeded", "\(model.items.count)")

            // Main window: one clip open in the editor, a status line in the toolbar.
            let main = NSSize(width: 1380, height: 760)
            if let first = model.items.first(where: { $0.kind == .text }) { model.click(first.id, modifiers: []) }
            model.notice = "已复制 2 条记录"
            shot(MainView(model: model, hideWindow: {}), "main", main)
            model.notice = nil
            // Several selected: the batch bar and the multi-selection detail.
            let ids = model.items.map(\.id)
            model.click(ids[0], modifiers: []); model.click(ids[2], modifiers: [.shift])
            shot(MainView(model: model, hideWindow: {}), "main-multiple", main)
            // Image detail with its export action.
            if let image = model.items.first(where: { $0.kind == .image }) { model.click(image.id, modifiers: []) }
            shot(MainView(model: model, hideWindow: {}), "main-image", main)
            // Empty state: a search with no match, and a merge refusal in the toolbar.
            model.selection = []
            model.search = zh ? "不存在的关键词" : "nothing-like-this"
            model.notice = "合并失败：至少需要两条记录才能合并"
            shot(MainView(model: model, hideWindow: {}), "main-empty-search", main)
            model.search = ""; model.notice = nil

            // Settings: the production view and panes with the production shortcut center (nothing registered).
            let keys = NoKeys()
            let center = ClipShortcuts(defaults: AppPreferences.defaults, backend: keys, monitorsEnabled: false) { _ in }
            defer { center.suspend() }
            settings.refreshLoginStatus()
            shot(SettingsView(model: model, settings: settings, shortcuts: center), "settings-general", NSSize(width: 620, height: 900))
            // An invalid recording and a held chord: the error lines a person sees.
            _ = center.set(.search, to: ClipBinding(chord: ClipKey(code: 0, modifiers: 0, key: "A"), scope: .application))
            _ = center.set(.pause, to: ClipBinding(chord: ClipKey(code: 35, modifiers: UInt32(controlKey | optionKey), key: "P"), scope: .global))
            shot(ShortcutSettingsPane(center: center).frame(width: 600), "settings-shortcuts", NSSize(width: 620, height: 980))
            report.check(keys.registerCalls == 0 || center.bindings.count == 1, "shortcuts_isolated", "register \(keys.registerCalls)")
            if ProductIdentity.cloudSupported {
                shot(ClipCloudSettings(sync: model.cloud), "settings-icloud", NSSize(width: 620, height: 420))
            }
            shot(CollectionEditor(model: model, collection: nil), "collection-new", NSSize(width: 460, height: 260))

            #if !APP_STORE
            // The shared Settings & Updates window, built as the menu builds it, never ordered in.
            let configuration = ClipPortableConfiguration.make(defaults: AppPreferences.defaults)
            AppLifecycleUI.install(name: ProductIdentity.name, configuration: configuration, updateSource: ClipUpdates.source, startConfiguration: false)
            let lifecycle = try AppLifecycleUI.shared.offscreenSnapshot(to: out.appendingPathComponent("lifecycle-settings.png"))
            report.screenshots.append("lifecycle-settings.png")
            report.check(!lifecycle.isEmpty && !lifecycle.values.contains(false), "shot_lifecycle-settings", "\(lifecycle)")
            NSApp.windows.forEach { $0.orderOut(nil) }
            #endif

            report.check(NSPasteboard.general.changeCount == generalBefore && !NSApp.isActive && panels.allSatisfy { !$0.isVisible },
                         "no_focus_or_general_pasteboard_side_effects")
        } catch {
            report.check(false, "l10n_self_test_error", "\(error)")
        }
        return report.finish()
    }
}
