import AppKit
import SwiftUI

/// 卡片点选用 AppKit 收鼠标事件：拿得到修饰键与连击数，且 acceptsFirstMouse —— 窗口不在前台时第一下点击也算选中，
/// 不像 SwiftUI TapGesture 那样第一下只激活窗口。右键放行给 SwiftUI 的 contextMenu。
struct ClickCatcher: NSViewRepresentable {
    let onClick: (NSEvent.ModifierFlags, Int) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onClick = onClick
        return v
    }

    func updateNSView(_ v: CatcherView, context: Context) { v.onClick = onClick }

    final class CatcherView: NSView {
        var onClick: ((NSEvent.ModifierFlags, Int) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            // 右键按下时让开，SwiftUI 的 .contextMenu 才收得到
            if NSEvent.pressedMouseButtons & 0b10 != 0 { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            onClick?(event.modifierFlags.intersection([.command, .shift, .option, .control]), event.clickCount)
        }
    }
}
