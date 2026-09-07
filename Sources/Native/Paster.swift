import AppKit
import ApplicationServices

/// 把一条记录写回剪贴板；「粘贴」按钮再把用户原来的 app 拉回前台并补一下 ⌘V（需辅助功能授权）。
enum Paster {
    /// 写剪贴板。返回写完后的 changeCount，Watcher 用它跳过自己这次写入。
    @discardableResult
    static func write(_ item: ClipItem, store: ClipStore, pasteboard pb: NSPasteboard = .general) -> Int {
        pb.clearContents()
        switch item.kind {
        case .text, .link, .code, .color:
            pb.setString(item.text, forType: .string)
        case .richText:
            if let url = store.rtfURL(item), let rtf = try? Data(contentsOf: url) {
                pb.setData(rtf, forType: .rtf)
            }
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

    /// Preserve display order. Text selections paste as one block; file/image payloads
    /// remain native pasteboard objects instead of being reduced to labels.
    @discardableResult
    static func write(_ items: [ClipItem], store: ClipStore, pasteboard pb: NSPasteboard = .general) -> Int {
        guard !items.isEmpty else { return pb.changeCount }
        if items.count == 1 { return write(items[0], store: store, pasteboard: pb) }
        let text = items.filter { $0.kind != .file && $0.kind != .image }.map(\.text).joined(separator: "\n\n")
        var objects: [NSPasteboardWriting] = []
        var wroteText = false
        for item in items {
            switch item.kind {
            case .file:
                objects += item.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
            case .image:
                if let url = store.blobURL(item), let data = try? Data(contentsOf: url) {
                    let entry = NSPasteboardItem(); entry.setData(data, forType: .png); objects.append(entry)
                }
            default:
                if !wroteText {
                    let entry = NSPasteboardItem(); entry.setString(text, forType: .string)
                    objects.append(entry); wroteText = true
                }
            }
        }
        pb.clearContents(); pb.writeObjects(objects)
        return pb.changeCount
    }

    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

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
