import AppKit
import Carbon.HIToolbox

@MainActor
private final class TestKeyRegistration: ClipKeyRegistration {
    var onPress: ((UInt32) -> Void)?
    var calls = 0
    var active: Set<UInt32> = []
    var failNext = false
    func register(_ chord: ClipKey, id: UInt32) -> OSStatus {
        calls += 1
        if failNext { failNext = false; return -9878 }
        active.insert(id); return noErr
    }
    func unregister(_ id: UInt32) { active.remove(id) }
}

@MainActor
private final class CopyProbeTextView: NSTextView {
    var copyCalls = 0
    override func copy(_ sender: Any?) { copyCalls += 1 }
}

@MainActor
enum ShortcutSelfTest {
    /// Opt-in native backend test. Sends an application Carbon event, not a physical
    /// keyboard event; never presses a user's macro combination.
    static func runtime() -> Int32 {
        _ = NSApplication.shared
        let suite = "Clip-carbon-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var seen: [ClipAction] = []
        let center = ClipShortcuts(defaults: defaults, monitorsEnabled: false) { seen.append($0) }
        defer { center.suspend() }
        let key = ClipKey(code: UInt32(kVK_F20), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), key: "F20")
        guard center.set(.toggleWindow, to: .init(chord: key, scope: .global)) else {
            print("FAIL Carbon registration: \(center.status(.toggleWindow))"); return 1
        }
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), GetCurrentEventTime(), 0, &event)
        guard created == noErr, let event else { print("FAIL CreateEvent: \(created)"); return 1 }
        defer { ReleaseEvent(event) }
        var id = EventHotKeyID(signature: 0x434C_4950, id: 1)
        let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
        guard parameter == noErr else { print("FAIL SetEventParameter: \(parameter)"); return 1 }
        let sent = SendEventToEventTarget(event, GetApplicationEventTarget())
        guard sent == noErr, seen == [.toggleWindow] else { print("FAIL Carbon dispatch: \(sent), \(seen)"); return 1 }
        center.clearAll()
        // Verify the identical combination is immediately available after clearing.
        let backend = CarbonClipKeys()
        let rc = backend.register(key, id: 100)
        backend.unregister(100)
        guard rc == noErr else { print("FAIL unregister/re-register: \(rc)"); return 1 }
        print("PASS native Carbon registration → event handler → production action → unregister/re-register; no physical key sent")
        return 0
    }

    static func run() -> [(Bool, String)] {
        var results: [(Bool, String)] = []
        func check(_ value: Bool, _ message: String) { results.append((value, message)) }
        let suite = "Clip-shortcut-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = TestKeyRegistration()
        var performed: [ClipAction] = []
        let center = ClipShortcuts(defaults: defaults, backend: backend, monitorsEnabled: false) { performed.append($0) }
        let comma = ClipKey(code: 43, modifiers: UInt32(cmdKey), key: ",")
        check(center.bindings.isEmpty && backend.calls == 0 && !center.handleLocal(comma), "首次启动无绑定、无全局注册，⌘, 不被默认截获")
        let cmdC = ClipKey(code: 8, modifiers: UInt32(cmdKey), key: "C")
        check(center.set(.copy, to: .init(chord: cmdC, scope: .application)) && backend.calls == 0,
              "允许复制动作录制⌘C，仅应用内且零全局注册")
        check(center.handleLocal(cmdC) && performed == [.copy], "录制⌘C后分发至复制动作")
        center.set(.copy, to: nil); performed = []
        check(!center.set(.delete, to: .init(chord: cmdC, scope: .application)), "⌘C不能改成删除等其他动作")
        let editor = CopyProbeTextView()
        editor.string = "alpha beta"; editor.setSelectedRange(NSRange(location: 6, length: 4))
        var recordCopies = 0
        check(ClipCopy.perform(firstResponder: editor, recordAvailable: true) { recordCopies += 1 }
              && editor.copyCalls == 1 && recordCopies == 0,
              "有选中文字时转交原生文本拷贝，不复制整条记录")
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        check(ClipCopy.perform(firstResponder: editor, recordAvailable: true) { recordCopies += 1 }
              && recordCopies == 1, "没有文本选区时复制所选记录，即使搜索框仍有焦点")
        check(!ClipCopy.perform(firstResponder: editor, recordAvailable: false) { recordCopies += 1 }
              && recordCopies == 1, "设置窗口或没有记录时不误复制后台记录")
        check(center.set(.settings, to: .init(chord: comma, scope: .application)) && backend.calls == 0, "录制仅应用内的⌘,无需全局注册")
        check(center.handleLocal(comma) && performed == [.settings], "真实动作分发：配置后的⌘,进入设置动作")
        check(!center.handleLocal(comma, isRepeat: true) && performed.count == 1, "按住不重复触发")
        check(!center.set(.search, to: .init(chord: comma, scope: .application)) && center.binding(.search) == nil, "重复组合被拒绝，不覆盖既有动作")
        center.beginRecording()
        check(!center.handleLocal(comma), "录制期间应用快捷键暂停，防止误操作")
        center.endRecording()
        let restored = ClipShortcuts(defaults: defaults, backend: TestKeyRegistration(), monitorsEnabled: false) { performed.append($0) }
        check(restored.binding(.settings)?.chord == comma && restored.handleLocal(comma), "从独立UserDefaults重建后绑定与动作恢复")
        restored.suspend()
        let global = ClipKey(code: 90, modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey), key: "F20")
        var allScopes = true
        for action in ClipAction.allCases {
            center.clearAll()
            allScopes = center.set(action, to: .init(chord: global, scope: .global)) && backend.active.count == 1 && allScopes
            allScopes = center.set(action, to: .init(chord: global, scope: .application)) && backend.active.isEmpty && allScopes
        }
        center.clearAll()
        check(allScopes, "全部12个动作均可在全局与应用内切换，并实际注册/注销")
        check(center.set(.toggleWindow, to: .init(chord: global, scope: .global)) && backend.active.count == 1, "只有显式选择全局才调用注册器")
        let oldID = backend.active.first!
        backend.onPress?(oldID)
        check(performed.last == .toggleWindow, "全局注册回调进入同一生产动作分发")
        backend.failNext = true
        let alternative = ClipKey(code: 79, modifiers: global.modifiers, key: "F18")
        check(!center.set(.toggleWindow, to: .init(chord: alternative, scope: .global)) && backend.active == [oldID]
              && center.binding(.toggleWindow)?.chord == global, "更换失败保留旧绑定，错误可见且不自动尝试别的键")
        let callCount = backend.calls
        check(center.set(.toggleWindow, to: .init(chord: global, scope: .global)) && backend.calls == callCount
              && center.errors[ClipAction.toggleWindow.rawValue] == nil, "重新确认仍生效的原绑定不重复注册，可清除上次失败提示")
        center.beginRecording()
        check(backend.active.isEmpty, "录制时真注销已有全局键")
        center.endRecording()
        check(backend.active.count == 1, "取消录制恢复已有用户绑定")
        check(center.set(.toggleWindow, to: .init(chord: global, scope: .application)) && backend.active.isEmpty, "切回仅应用内立即解绑全局键")
        let reserved = ClipKey(code: 9, modifiers: UInt32(cmdKey | shiftKey), key: "V")
        check(!center.set(.paste, to: .init(chord: reserved, scope: .application)), "拒绝覆盖用户KM的⌘⇧V（仅验证数据，不发送按键）")
        check(!center.set(.settings, to: .init(chord: ClipKey(code: 43, modifiers: 0, key: ","), scope: .application)), "普通输入字符不能被设为动作快捷键")
        center.clearAll()
        check(backend.active.isEmpty && center.bindings.isEmpty && defaults.object(forKey: ClipShortcuts.storageKey) == nil
              && !center.handleLocal(comma), "清除所有立即解绑并移除持久化配置")
        defaults.set(Data("invalid".utf8), forKey: ClipShortcuts.storageKey)
        let brokenBackend = TestKeyRegistration()
        let broken = ClipShortcuts(defaults: defaults, backend: brokenBackend, monitorsEnabled: false) { _ in }
        check(broken.bindings.isEmpty && brokenBackend.calls == 0 && broken.errors["load"] != nil, "损坏配置不注册且错误显形")

        let settings = AppSettings(defaults: defaults)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Clip-settings-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let model = try AppModel(home: directory, settings: settings)
            let board = NSPasteboard(name: .init("Clip-multicopy-\(UUID().uuidString)"))
            defer { board.releaseGlobally() }
            let first = try model.store.ingest(Capture(kind: .text, text: "first", appName: "QA", appBundle: "test.app"), at: Date(timeIntervalSinceNow: -2))
            let second = try model.store.ingest(Capture(kind: .text, text: "second", appName: "QA", appBundle: "test.app"))
            model.reload(); model.selection = [first.id, second.id]
            model.copySelection(pasteboard: board)
            check(board.string(forType: .string) == "second\n\nfirst" && model.selection.count == 2,
                  "真实多选复制：按显示顺序写入两条正文，保留选择")
            model.selection = [first.id]; model.copySelection(pasteboard: board)
            check(board.string(forType: .string) == "first", "单选复制仍只写入所选一条")
            model.selection = []; let change = board.changeCount; model.copySelection(pasteboard: board)
            check(board.changeCount == change, "空选择不清空剪贴板")
            let fileA = try model.store.ingest(Capture(kind: .file, text: "/tmp/clip-qa-a.txt", appName: "QA", appBundle: "test.app"))
            let fileB = try model.store.ingest(Capture(kind: .file, text: "/tmp/clip-qa-b.txt", appName: "QA", appBundle: "test.app"))
            Paster.write([fileA, fileB], store: model.store, pasteboard: board)
            check(board.pasteboardItems?.count == 2 && board.pasteboardItems?.allSatisfy { $0.string(forType: .fileURL) != nil } == true,
                  "多文件复制保留两个原生文件URL载荷")
            settings.paused = true; settings.plainTextOnly = true
            settings.ignoredBundles = ["test.app"]; settings.maxItems = 700; settings.retentionDays = 30
            check(model.watcher.paused && model.watcher.plainTextOnly && model.watcher.ignoredBundles == ["test.app"]
                  && model.store.maxItems == 700 && model.store.retentionDays == 30, "未创建设置窗口也能把偏好同步到实际Watcher与Store")
            let restoredSettings = AppSettings(defaults: defaults)
            check(restoredSettings.paused && restoredSettings.plainTextOnly && restoredSettings.ignoredBundles == ["test.app"]
                  && restoredSettings.maxItems == 700 && restoredSettings.retentionDays == 30, "记录偏好重建后完整恢复")
        } catch { check(false, "设置测试异常：\(error)") }
        return results
    }
}
