import AppKit
import SwiftUI

extension Notification.Name {
    static let clipbookPanelShown = Notification.Name("clipbook.panelShown")
}

/// nonactivating 的浮动面板：能成为 key window 接键盘，但**不激活本 app**，
/// 所以用户原来的 app 一直在前台，回车后的 ⌘V 直接落在它身上（Maccy / Alfred 同款机制）。
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let panel: KeyPanel
    private let model: AppModel
    private var escMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
                         styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
                         backing: .buffered, defer: false)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 620, height: 360)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: PanelView(model: model, controller: self))
        panel.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        model.prepareForShow()
        if !panel.isVisible { center(on: screenUnderMouse()) }
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .clipbookPanelShown, object: nil)
    }

    func hide() { panel.orderOut(nil) }

    /// 回车：写剪贴板 → 收面板 → 前台 app 还是用户那个 → 补一下 ⌘V
    func pasteSelected() {
        guard let item = model.selected else { return }
        let auto = model.paste(item)
        hide()
        if auto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { _ = Paster.sendCommandV() }
        } else {
            Paster.promptAccessibility()
        }
    }

    func windowDidResignKey(_ notification: Notification) { hide() }

    private func screenUnderMouse() -> NSScreen {
        let p = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func center(on screen: NSScreen) {
        let f = screen.visibleFrame
        let s = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2 + f.height * 0.08))
    }
}
