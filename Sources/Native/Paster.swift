import AppKit
import ApplicationServices

/// 把一条记录写回剪贴板，并（授权了辅助功能时）替用户按一下 ⌘V。
///
/// 面板是 nonactivating 的 NSPanel，所以从头到尾前台 app 都是用户原来那个 —— ⌘V 直接落在它身上，
/// 不需要「记住上一个 app 再切回去」那套。
enum Paster {
    enum Outcome { case pasted, copiedOnly }

    /// 写剪贴板。返回写完后的 changeCount，Watcher 用它跳过自己这次写入。
    @discardableResult
    static func write(_ item: ClipItem, store: ClipStore) -> Int {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .link:
            pb.setString(item.text, forType: .string)
        case .file:
            let urls = item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            pb.writeObjects(urls)
        case .image:
            if let url = store.blobURL(item), let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }
        }
        return pb.changeCount
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// 弹系统那个「打开辅助功能设置」提示（只在用户真按了粘贴、又没授权时才弹一次）。
    static func promptAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// 模拟 ⌘V。无授权时 CGEvent.post 静默失败，所以先判断再发，不假装成功。
    static func sendCommandV() -> Bool {
        guard accessibilityTrusted else { return false }
        let src = CGEventSource(stateID: .combinedSessionState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
