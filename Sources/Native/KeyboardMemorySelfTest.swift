import AppKit

@MainActor
enum KeyboardMemorySelfTest {
    /// Opt-in isolated window test. Sends AppKit events only to this test process.
    static func windowRuntime() -> Int32 {
        guard ProcessInfo.processInfo.environment["CLIPBOOK_HOME"] != nil,
              ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"] != nil else { return 2 }
        var failed = false
        func check(_ ok: Bool, _ name: String) { print("\(ok ? "PASS" : "FAIL") \(name)"); failed = failed || !ok }
        func settle() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35)) }
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            AppSettings.shared.paused = true; AppSettings.shared.copySound = false; AppSettings.shared.fetchLinkTitles = false
            let store = try ClipStore(home: ClipStore.defaultHome())
            for i in 0..<20 { _ = try store.ingest(Capture(kind: .text, text: "Keyboard window fixture \(i)", appName: "Test", appBundle: "test")) }
            let delegate = AppDelegate(); app.delegate = delegate
            delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
            delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
            AppModel.shared.watcher.stop(); settle()
            guard let window = app.windows.first(where: { $0.title == ProductIdentity.name }),
                  let grid = GridKeyboard.Responder.find(in: window.contentView) else { return 1 }
            let model = AppModel.shared!
            check(window.firstResponder === grid, "主窗口打开即聚焦稳定的网格 responder")
            let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
            window.sendEvent(tab); settle()
            check(window.firstResponder !== grid, "Tab 可以离开网格进入下一控件")
            window.makeFirstResponder(grid)
            let ids = model.items.map(\.id)
            func key(_ code: UInt16) {
                let chars = [UInt16(123): "\u{F702}", 124: "\u{F703}", 125: "\u{F701}", 126: "\u{F700}"][code] ?? ""
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                window.sendEvent(event); settle()
            }
            key(125); key(124)
            check(model.selection == [ids[1]], "实际 NSWindow 事件分发：下、右选择第二条")
            func editor(in view: NSView?) -> NSTextView? {
                guard let view else { return nil }
                if let text = view as? NSTextView, text.isEditable, !text.isFieldEditor { return text }
                return view.subviews.lazy.compactMap { editor(in: $0) }.first
            }
            if let text = editor(in: window.contentView) {
                window.makeFirstResponder(text)
                text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
                text.insertText("Unsaved keyboard draft", replacementRange: text.selectedRange()); settle()
                let selected = model.selection
                key(123)
                check(model.selection == selected && text.selectedRange().location == 21, "正文左键只移动光标，网格选择不变")
                delegate.hideWindow(); settle(); delegate.showWindow(); settle()
                check(editor(in: window.contentView)?.string == "Unsaved keyboard draft", "卸载并重建主界面后未保存正文仍在")
            } else { check(false, "实际正文编辑器可访问") }
            delegate.showSettings(); settle()
            if let settings = app.windows.first(where: { $0.title == "\(ProductIdentity.name) 设置" }) { _ = delegate.windowShouldClose(settings) }
            delegate.hideWindow(); settle()
            check(window.contentView == nil && !model.interfaceActive, "关主窗后 HostingView 确实释放且查询暂停")
            delegate.showWindow(); settle()
            check(model.selection == [ids[1]] && model.interfaceActive, "重新打开保留选择并恢复查询")
            delegate.shortcuts.suspend()
        } catch { check(false, String(describing: error)) }
        return failed ? 1 : 0
    }

    static func run() -> [(Bool, String)] {
        var results: [(Bool, String)] = []
        func check(_ value: Bool, _ name: String) { results.append((value, name)) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clip-navigation-\(UUID().uuidString)")
        let suite = "clip-navigation-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: root); defaults.removePersistentDomain(forName: suite) }
        do {
            let model = try AppModel(home: root, settings: AppSettings(defaults: defaults))
            for i in 0..<8 { _ = try model.store.ingest(Capture(kind: .text, text: "navigation \(i)", appName: "Test", appBundle: "test")) }
            model.reload(); model.gridColumns = 3
            let ids = model.items.map(\.id)
            let responder = GridKeyboard.Responder()
            responder.onKey = { model.navigate(code: $0.keyCode, modifiers: $0.modifierFlags) }
            func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
                responder.keyDown(with: event)
            }
            key(125); check(model.selection == [ids[0]], "网格原生 responder：首次方向键选中第一条")
            key(124); key(125); check(model.selection == [ids[4]], "右移一格、下移一行遵循三列布局")
            key(125, .shift); check(model.selection == Set(ids[4...7]), "Shift 下移扩选至不完整末行")
            key(126, .shift); check(model.selection == [ids[4]], "Shift 反向移动收缩选择")
            key(115); key(123); check(model.selection == [ids[0]], "Home 和左边界不越界")
            key(119); key(125); check(model.selection == [ids[7]], "End 和底边界不越界")
            check(!model.navigate(code: 123, modifiers: [.command]), "带命令修饰键的系统编辑动作不被网格截获")
            key(53); check(model.selection.isEmpty, "Esc 清除网格选择")
            model.click(ids[2], modifiers: [])
            model.savedDraft = .init(id: ids[2], text: "unsaved", title: "draft", rich: false)
            model.suspendInterface()
            check(model.items.map(\.id) == [ids[2]] && model.savedDraft?.text == "unsaved", "隐藏界面只保留所选记录与未保存草稿")
            _ = try model.store.ingest(Capture(kind: .text, text: "background capture", appName: "Test", appBundle: "test"))
            model.reload()
            check(model.items.count == 1, "后台数据变化不重建整页界面数据")
            model.resumeInterface()
            check(model.items.count == 9 && model.selection == [ids[2]], "恢复界面读取新记录并保留选择")
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2400, pixelsHigh: 1200,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let url = root.appendingPathComponent("large.png")
            try rep.representation(using: .png, properties: [:])!.write(to: url)
            let thumb = AppModel.downsample(url, maxPixels: 512)
            check(thumb?.size == NSSize(width: 512, height: 256), "2400×1200 原图按 512×256 解码，保留比例")
            check(NSBitmapImageRep(data: try Data(contentsOf: url))?.pixelsWide == 2400, "预览缩小不改变原图")
        } catch { check(false, "键盘/内存回归失败：\(error)") }
        return results
    }
}
