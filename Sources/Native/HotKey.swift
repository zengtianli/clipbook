import AppKit
import Carbon.HIToolbox

// 全局快捷键，Carbon RegisterEventHotKey（零 TCC 授权、当场返回 OSStatus）。
// 候选表 + 退让机制照抄舰队 metasearch-bar 的写法；候选 id 登记在总部 SSOT
// ~/Dev/tools/configs/hotkeys.yaml，build.sh 构建期机检两两零交集。
//
// ⚠ 跨进程注册同一组合时双方都返回 0（本机 macOS 27 实测，见 metasearch-bar/HotKey.swift 注释）——
// 所以 Deck 在跑时本 app 也会「注册成功」但按下去谁响应不确定。换用本 app 前要退掉 Deck，
// 面板底栏会如实提示 Deck 在跑。

struct HotKeyCombo: Identifiable, Hashable {
    let id: String
    let label: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let all: [HotKeyCombo] = [
        .init(id: "cmd-shift-v",  label: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        .init(id: "ctrl-shift-v", label: "⌃⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey)),
        .init(id: "cmd-opt-v",    label: "⌘⌥V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)),
    ]
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    static let summonNotification = Notification.Name("clipbook.summon")

    private(set) var bound: HotKeyCombo?
    private(set) var lastStatus: OSStatus = noErr
    private(set) var attempts: [(combo: HotKeyCombo, status: OSStatus)] = []

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let signature: OSType = 0x434C_5042 // 'CLPB'

    private init() {}

    var label: String { bound?.label ?? HotKeyCombo.all[0].label }

    var status: String {
        if let b = bound { return "\(b.label) 已注册" }
        let tried = attempts.map { "\($0.combo.label)=\($0.status)" }.joined(separator: " / ")
        return "全局快捷键未注册（\(tried)；最后 OSStatus \(lastStatus)）"
    }

    @discardableResult
    private func installHandlerIfNeeded() -> OSStatus {
        guard handler == nil else { return noErr }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let rc = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: HotKeyCenter.summonNotification, object: nil)
            }
            return noErr
        }, 1, &spec, nil, &handler)
        if rc != noErr { handler = nil }
        return rc
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        bound = nil
    }

    @discardableResult
    func register(_ combo: HotKeyCombo) -> Bool {
        let installed = installHandlerIfNeeded()
        guard installed == noErr else {
            lastStatus = installed
            attempts.append((combo, installed))
            return false
        }
        unregister()
        var newRef: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: signature, id: 1)
        lastStatus = RegisterEventHotKey(combo.keyCode, combo.modifiers, hkID, GetApplicationEventTarget(), 0, &newRef)
        attempts.append((combo, lastStatus))
        if lastStatus == noErr, newRef != nil {
            ref = newRef
            bound = combo
            return true
        }
        return false
    }

    @discardableResult
    func registerFirstAvailable(_ candidates: [HotKeyCombo] = HotKeyCombo.all) -> HotKeyCombo? {
        attempts.removeAll()
        for c in candidates where register(c) { return c }
        return nil
    }

    func register() {
        guard bound == nil else { return }
        registerFirstAvailable()
    }
}
