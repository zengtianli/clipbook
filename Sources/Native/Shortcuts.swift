import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ClipAction: String, CaseIterable, Identifiable, Codable {
    case toggleWindow, settings, pause, search, save, copy, paste, pin, delete, selectAll, closeWindow, quit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .toggleWindow: return "显示 / 隐藏主窗口"
        case .settings: return "打开设置"
        case .pause: return "暂停 / 恢复记录"
        case .search: return "聚焦搜索"
        case .save: return "保存当前编辑"
        case .copy: return "复制所选记录"
        case .paste: return "粘贴所选记录"
        case .pin: return "置顶 / 取消置顶"
        case .delete: return "删除所选记录…"
        case .selectAll: return "全选当前页"
        case .closeWindow: return "关闭当前窗口"
        case .quit: return "退出应用"
        }
    }
    var allowsGlobal: Bool { [.toggleWindow, .settings, .pause].contains(self) }
    static let requested = Notification.Name("Clip.actionRequested")
}

struct ClipKey: Codable, Equatable {
    let code: UInt32
    let modifiers: UInt32
    let key: String
    static let allowedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
    init(code: UInt32, modifiers: UInt32, key: String) {
        self.code = code; self.modifiers = modifiers & Self.allowedModifiers; self.key = key
    }
    init(_ event: NSEvent) {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        self.init(code: UInt32(event.keyCode), modifiers: mods,
                  key: special[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased())
    }
    var label: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + key
    }
    func matches(_ other: ClipKey) -> Bool { code == other.code && modifiers == other.modifiers }
    var validationError: String? {
        guard code < 128, !key.isEmpty, modifiers & ~Self.allowedModifiers == 0 else { return "无法识别这个组合，请重新录制。" }
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else { return "请至少包含 ⌘、⌃ 或 ⌥，避免影响正常输入。" }
        if code == 9 && modifiers == UInt32(cmdKey | shiftKey) { return "⌘⇧V 已用于你的 Keyboard Maestro 操作，请换一个组合。" }
        if modifiers == UInt32(cmdKey), [0, 6, 7, 8, 9].contains(code) { return "请保留系统的全选、撤销、剪切、复制与粘贴组合。" }
        return nil
    }
}

struct ClipBinding: Codable, Equatable {
    enum Scope: String, Codable, CaseIterable { case application, global }
    let chord: ClipKey
    let scope: Scope
}

@MainActor
protocol ClipKeyRegistration: AnyObject {
    var onPress: ((UInt32) -> Void)? { get set }
    func register(_ chord: ClipKey, id: UInt32) -> OSStatus
    func unregister(_ id: UInt32)
}

@MainActor
final class CarbonClipKeys: ClipKeyRegistration {
    var onPress: ((UInt32) -> Void)?
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private static let signature: OSType = 0x434C_4950

    func register(_ chord: ClipKey, id: UInt32) -> OSStatus {
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            let rc = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var key = EventHotKeyID()
                let rc = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &key)
                guard rc == noErr, key.signature == 0x434C_4950 else { return OSStatus(eventNotHandledErr) }
                let center = Unmanaged<CarbonClipKeys>.fromOpaque(context).takeUnretainedValue()
                let id = key.id
                MainActor.assumeIsolated { center.onPress?(id) }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard rc == noErr else { return rc }
        }
        var ref: EventHotKeyRef?
        let rc = RegisterEventHotKey(chord.code, chord.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                                    GetApplicationEventTarget(), 0, &ref)
        if rc == noErr, let ref { refs[id] = ref }
        return rc
    }
    func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        if refs.isEmpty, let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}

@MainActor
final class ClipShortcuts: ObservableObject {
    static let defaultBindings: [String: ClipBinding] = [:]
    static let storageKey = "shortcuts.v1"
    @Published private(set) var bindings: [String: ClipBinding]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var recording = false
    @Published private(set) var recordingAction: ClipAction?
    private let defaults: UserDefaults
    private let backend: ClipKeyRegistration
    private let perform: (ClipAction) -> Void
    private var live: [String: UInt32] = [:]
    private var serial: UInt32 = 0
    private var monitor: Any?
    private let monitorsEnabled: Bool

    init(defaults: UserDefaults = AppPreferences.defaults, backend: ClipKeyRegistration? = nil,
         monitorsEnabled: Bool = true, perform: @escaping (ClipAction) -> Void) {
        self.defaults = defaults; self.backend = backend ?? CarbonClipKeys(); self.perform = perform; self.monitorsEnabled = monitorsEnabled
        if let data = defaults.data(forKey: Self.storageKey) {
            do { bindings = try JSONDecoder().decode([String: ClipBinding].self, from: data) }
            catch { bindings = Self.defaultBindings; errors["load"] = "快捷键配置无法读取，未注册任何快捷键。请重新设置。" }
        } else { bindings = Self.defaultBindings }
        self.backend.onPress = { [weak self] id in
            guard let self, !self.recording, let raw = self.live.first(where: { $0.value == id })?.key,
                  let action = ClipAction(rawValue: raw) else { return }
            self.perform(action)
        }
        resume()
    }

    func binding(_ action: ClipAction) -> ClipBinding? { bindings[action.rawValue] }
    func status(_ action: ClipAction) -> String {
        if let error = errors[action.rawValue] { return error }
        guard let b = binding(action) else { return "未设置" }
        return b.scope == .global ? "已启用 · 全局" : "已启用 · 仅 Clip 内"
    }
    private func invalid(_ action: ClipAction, _ binding: ClipBinding) -> String? {
        if let error = binding.chord.validationError { return error }
        if binding.scope == .global && !action.allowsGlobal { return "此操作只能在 Clip 窗口内使用。" }
        if let duplicate = bindings.first(where: { $0.key != action.rawValue && $0.value.chord.matches(binding.chord) }) {
            return "已用于「\(ClipAction(rawValue: duplicate.key)?.title ?? duplicate.key)」，请先清除原绑定。"
        }
        return nil
    }
    @discardableResult
    func set(_ action: ClipAction, to binding: ClipBinding?) -> Bool {
        if let binding, let error = invalid(action, binding) { errors[action.rawValue] = error; return false }
        if bindings[action.rawValue] == binding,
           binding?.scope != .global || live[action.rawValue] != nil {
            errors[action.rawValue] = nil
            return true
        }
        var newID: UInt32?
        if let binding, binding.scope == .global, !recording {
            serial += 1
            let rc = backend.register(binding.chord, id: serial)
            guard rc == noErr else { errors[action.rawValue] = "未启用：系统拒绝注册（\(rc)）；原绑定保留。"; return false }
            newID = serial
        }
        if let old = live.removeValue(forKey: action.rawValue) { backend.unregister(old) }
        if let newID { live[action.rawValue] = newID }
        bindings[action.rawValue] = binding
        errors[action.rawValue] = nil
        // All fields are primitive Codable values; persistence never invents a default binding.
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: Self.storageKey) }
        refreshMonitor()
        return true
    }
    func clearAll() {
        suspend(); recording = false; recordingAction = nil; bindings = Self.defaultBindings; errors = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }
    func beginRecording(action: ClipAction? = nil) { recording = true; recordingAction = action; suspend() }
    func endRecording() { guard recording else { return }; recording = false; recordingAction = nil; resume() }
    func suspend() {
        for id in live.values { backend.unregister(id) }; live = [:]
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    private func resume() {
        guard !recording else { return }
        for action in ClipAction.allCases {
            guard let binding = binding(action) else { continue }
            if let error = invalid(action, binding) { errors[action.rawValue] = error; continue }
            if binding.scope == .global {
                serial += 1
                let rc = backend.register(binding.chord, id: serial)
                if rc == noErr { live[action.rawValue] = serial; errors[action.rawValue] = nil }
                else { errors[action.rawValue] = "未启用：系统拒绝注册（\(rc)）。可重新录制或清除。" }
            }
        }
        refreshMonitor()
    }
    @discardableResult
    func handleLocal(_ chord: ClipKey, isRepeat: Bool = false) -> Bool {
        guard !recording, !isRepeat, let action = ClipAction.allCases.first(where: {
            guard let b = binding($0), b.scope == .application, invalid($0, b) == nil else { return false }
            return b.chord.matches(chord)
        }) else { return false }
        perform(action); return true
    }
    private func refreshMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard monitorsEnabled, !recording, bindings.values.contains(where: { $0.scope == .application }) else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard NSApp.isActive, NSApp.keyWindow != nil else { return false }
                return self?.handleLocal(ClipKey(event), isRepeat: event.isARepeat) == true
            }
            return handled ? nil : event
        }
    }
}

private struct KeyCapture: NSViewRepresentable {
    let active: Bool
    let captured: (ClipKey?) -> Void
    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.captured = captured; view.active = active
        if active, view.window?.firstResponder !== view {
            DispatchQueue.main.async { if view.active { view.window?.makeFirstResponder(view) } }
        }
    }
    final class CaptureView: NSView {
        var active = false
        var captured: ((ClipKey?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            guard active else { super.keyDown(with: event); return }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            captured?(event.keyCode == 53 && flags.isEmpty ? nil : ClipKey(event))
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard active else { return false }; keyDown(with: event); return true
        }
        override func resignFirstResponder() -> Bool {
            if active { captured?(nil) }
            return super.resignFirstResponder()
        }
    }
}

struct ShortcutSettingsPane: View {
    @ObservedObject var center: ClipShortcuts
    var body: some View {
        Form {
            Section {
                Text("快捷键由你选择，默认全部未设置。").font(.headline)
                Text("点击录制后按下组合键；Esc 取消。全局键仅在你选择「全局」并录制后注册，清除立即解绑。系统和其他应用也可能使用同一组合，注册成功不代表全机无冲突。")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = center.errors["load"] { Text(error).foregroundStyle(.red) }
            }
            Section("应用操作") {
                ForEach(ClipAction.allCases) { action in ShortcutRow(center: center, action: action) }
            }
            Section {
                Button("清除所有快捷键") { center.clearAll() }.disabled(center.bindings.isEmpty)
                Text("文本框沿用 macOS 的复制、粘贴等编辑操作；这里不会替你注册任何全局默认键。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear { center.endRecording() }
    }
}

private struct ShortcutRow: View {
    @ObservedObject var center: ClipShortcuts
    let action: ClipAction
    private var capturing: Bool { center.recordingAction == action }
    @State private var scope: ClipBinding.Scope = .application
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(action.title)
                Spacer()
                if action.allowsGlobal {
                    Picker("作用范围", selection: $scope) {
                        Text("仅 Clip 内").tag(ClipBinding.Scope.application)
                        Text("全局").tag(ClipBinding.Scope.global)
                    }.labelsHidden().frame(width: 105)
                    .onChange(of: scope) { _, value in
                        if let binding = center.binding(action), binding.scope != value {
                            if !center.set(action, to: ClipBinding(chord: binding.chord, scope: value)) { scope = binding.scope }
                        }
                    }
                }
                Button(capturing ? "按下组合键…" : center.binding(action)?.chord.label ?? "点击录制") {
                    if capturing { stop(nil) } else { center.beginRecording(action: action) }
                }.frame(width: 130).accessibilityIdentifier("shortcut.\(action.rawValue)")
                    .background(KeyCapture(active: capturing, captured: stop).frame(width: 1, height: 1))
                Button { _ = center.set(action, to: nil); if capturing { stop(nil) } } label: { Image(systemName: "xmark.circle") }
                    .buttonStyle(.plain).help("清除绑定").disabled(center.binding(action) == nil)
            }
            Text(center.status(action)).font(.caption)
                .foregroundStyle(center.errors[action.rawValue] == nil ? Color.secondary : .red)
        }
        .onAppear { scope = center.binding(action)?.scope ?? .application }
        .onDisappear { if capturing { stop(nil) } }
    }
    private func stop(_ chord: ClipKey?) {
        guard center.recordingAction == action else { return }
        center.endRecording()
        if let chord { _ = center.set(action, to: ClipBinding(chord: chord, scope: scope)) }
    }
}
