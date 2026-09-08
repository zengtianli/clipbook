import AppKit
import SwiftUI

/// 卡片点选用 AppKit 收鼠标事件：拿得到修饰键与连击数，且 acceptsFirstMouse —— 窗口不在前台时第一下点击也算选中，
/// 不像 SwiftUI TapGesture 那样第一下只激活窗口。右键放行给 SwiftUI 的 contextMenu。
struct ClickCatcher: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags, Int) -> Void
    var onKey: ((NSEvent) -> Bool)? = nil

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onClick = onClick
        v.onKey = onKey
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onClick = onClick; v.onKey = onKey }

    final class CatcherView: NSView {
        var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?
        var onKey: ((NSEvent) -> Bool)?
        override func keyDown(with event: NSEvent) {
            if onKey?(event) != true { super.keyDown(with: event) }
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 右键按下时让开，SwiftUI 的 .contextMenu 才收得到
            if NSEvent.pressedMouseButtons & 0b10 != 0 { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(GridKeyboard.Responder.find(in: window?.contentView) ?? self)
            onClick?(event.modifierFlags.intersection([.command, .shift, .option, .control]), event.clickCount)
        }
    }
}

/// A stable grid responder survives lazy card recycling when keyboard navigation scrolls.
struct GridKeyboard: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool
    func makeNSView(context: Context) -> Responder {
        let view = Responder(); view.onKey = onKey
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel("剪贴板网格，方向键选择，Shift 扩选，Return 复制")
        return view
    }
    func updateNSView(_ view: Responder, context: Context) { view.onKey = onKey }
    final class Responder: NSView {
        var onKey: ((NSEvent) -> Bool)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 48, event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
                else { window?.selectNextKeyView(nil) }
                return
            }
            if onKey?(event) != true { super.keyDown(with: event) }
        }
        static func find(in view: NSView?) -> Responder? {
            guard let view else { return nil }
            if let target = view as? Responder { return target }
            return view.subviews.lazy.compactMap { find(in: $0) }.first
        }
    }
}
