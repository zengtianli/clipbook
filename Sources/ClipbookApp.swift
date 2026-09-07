import AppKit
import SwiftUI

/// Clipbook —— 自用剪贴板库（PastePal 形态）。菜单栏常驻，点图标开主窗口；左筛、中挑、右改。
///
/// 全 Swift 原生。除「抓链接标题」外无网络。数据落 ~/Library/Application Support/Clipbook/。
/// 快捷键可自定义，默认不绑定、不注册。
@main
enum Boot {
    static func main() {
        if CommandLine.arguments.contains("--copy-sound-test") {
            exit(MainActor.assumeIsolated {
                let board = NSPasteboard(name: .init("Clip-external-audio-runtime-\(UUID().uuidString)"))
                defer { board.releaseGlobally() }
                var played = false
                let watcher = PasteboardWatcher(pasteboard: board, onCopy: { _ in
                    played = CopyFeedback.completed(success: true, enabled: true)
                }) { _ in }
                board.clearContents(); board.setString("external audio runtime", forType: .string)
                watcher.poll()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
                print(played ? "PASS external clipboard change → production watcher → selected native sound playback" : "FAIL copy feedback sound")
                return played ? 0 : 1
            })
        }
        if CommandLine.arguments.contains("--shortcut-runtime-test") {
            exit(MainActor.assumeIsolated { ShortcutSelfTest.runtime() })
        }
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var settingsWindow: NSWindow?
    private let menu = NSMenu()
    private var pendingURLs: [URL] = []
    private var pendingActions: [ClipAction] = []
    private(set) var shortcuts: ClipShortcuts!

    override init() {
        super.init()
        AppDelegate.shared = self
        MainActor.assumeIsolated {
            do {
                AppModel.shared = try AppModel()
                shortcuts = ClipShortcuts { [weak self] action in
                    self?.perform(action, globally: self?.shortcuts?.binding(action)?.scope == .global)
                }
            } catch {
                let a = NSAlert()
                a.messageText = "\(ProductIdentity.name) 启动失败"
                a.informativeText = "\(error)"
                a.runModal()
                exit(2)
            }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { installMainMenu() }
    }

    /// 标准主菜单。没有它，文本框里的 ⌘C / ⌘V / ⌘A / ⌘Z 这类**系统编辑命令**不工作
    /// （2026-09-05 实测：收藏夹名字框粘贴不进去）。这些是 macOS 文本框的标配，不是本 app 自定义的快捷键；
    /// 本 app 自己不绑任何快捷键。
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 \(ProductIdentity.name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: "")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(ProductIdentity.name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "退出 \(ProductIdentity.name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = edit.addItem(withTitle: "拷贝", action: #selector(menuCopy), keyEquivalent: "c")
        copy.target = self
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let actionsItem = NSMenuItem(); main.addItem(actionsItem)
        let actions = NSMenu(title: "记录")
        for action in ClipAction.allCases where action != .quit && action != .settings {
            let item = actions.addItem(withTitle: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = action.rawValue
        }
        actions.delegate = self
        actionsItem.submenu = actions

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "")
        windowItem.submenu = window
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.startWatching()
            buildStatusItem()
            buildWindow()
            showWindow()
            // 首次启动且本机有 Deck → 自动把它的历史导进来（用户 2026-09-05 拍板；只读 Deck 的库）
            if ProcessInfo.processInfo.environment["CLIPBOOK_HOME"] == nil,
               AppModel.shared.deckImportedAt == nil, DeckImporter.available() { AppModel.shared.importDeck() }
        }
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach { handleURL($0) }
        let actions = pendingActions; pendingActions = []
        actions.forEach { perform($0) }
    }

    // MARK: 菜单栏：左键开窗口，右键出菜单

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: ProductIdentity.name)
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menu.delegate = self
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            rebuildMenu()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggleWindow()
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let s = AppSettings.shared
        menu.addItem(withTitle: "打开 \(ProductIdentity.name)", action: #selector(menuOpen), keyEquivalent: "")
        let pause = menu.addItem(withTitle: "暂停记录", action: #selector(menuTogglePause), keyEquivalent: "")
        pause.state = s.paused ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(AppModel.shared.totalAll) 条记录", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 \(ProductIdentity.name)", action: #selector(menuQuit), keyEquivalent: "")
        for it in menu.items { it.target = self }
    }

    @objc private func menuOpen() { showWindow() }
    @objc private func menuTogglePause() { AppSettings.shared.paused.toggle(); AppModel.shared.applySettings() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuCopy() {
        guard !shortcuts.recording else { return }
        ClipCopy.perform(firstResponder: NSApp.keyWindow?.firstResponder,
                         recordAvailable: NSApp.keyWindow === window && !AppModel.shared.selection.isEmpty) {
            AppModel.shared.copySelection()
        }
    }
    @objc private func menuAction(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let action = ClipAction(rawValue: raw) { perform(action) }
    }

    func perform(_ action: ClipAction, globally: Bool = false) {
        guard window != nil else { pendingActions.append(action); return }
        let model = AppModel.shared!
        if globally && action == .copy { model.copySelection(); return }
        if globally && ![ClipAction.toggleWindow, .settings, .pause, .quit].contains(action) { showWindow() }
        switch action {
        case .toggleWindow: toggleWindow()
        case .settings: showSettings()
        case .pause: menuTogglePause()
        case .copy: menuCopy()
        case .search: showWindow(); NotificationCenter.default.post(name: ClipAction.requested, object: action)
        case .closeWindow: NSApp.keyWindow?.performClose(nil)
        case .quit: NSApp.terminate(nil)
        default:
            guard NSApp.keyWindow === window else { return }
            switch action {
            case .paste: if let item = model.detail { model.paste(item, hideWindow: { self.window.orderOut(nil) }) }
            case .pin: if let item = model.detail { model.togglePin(item) }
            case .delete: confirmDelete(model.selection)
            case .selectAll: model.selectAll()
            case .save: NotificationCenter.default.post(name: ClipAction.requested, object: action)
            default: break
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window != nil { showWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { shortcuts.suspend() }

    // MARK: 主窗口

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = ProductIdentity.name
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 960, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ClipbookMain")
        window.contentView = NSHostingView(rootView: MainView(model: AppModel.shared, hideWindow: { [weak self] in self?.window.orderOut(nil) }))
        window.center()
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func toggleWindow() {
        if window.isVisible && window.isKeyWindow { window.orderOut(nil) } else { showWindow() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "\(ProductIdentity.name) 设置"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.minSize = NSSize(width: 580, height: 450)
            w.contentView = NSHostingView(rootView: SettingsView(model: AppModel.shared, settings: AppSettings.shared, shortcuts: shortcuts))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 关窗口 = 隐藏，不退出（菜单栏常驻）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow { shortcuts.endRecording() }
        sender.orderOut(nil)
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow { shortcuts.endRecording() }
    }

    /// clipbook://show[?q=关键词] · clipbook://hide · clipbook://toggle · clipbook://settings
    // AppKit delivers cold-launch URLs before didFinishLaunching. Queue them
    // until the window exists instead of registering an Apple-event handler late.
    func application(_ application: NSApplication, open urls: [URL]) {
        if window == nil { pendingURLs.append(contentsOf: urls) }
        else { urls.forEach { handleURL($0) } }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "clipbook" else { return }
        MainActor.assumeIsolated {
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            switch url.host {
            case "show":
                showWindow()
                if let q { AppModel.shared.search = q }
            case "hide":     window.orderOut(nil)
            case "toggle":   toggleWindow()
            case "settings": showSettings()
            default: break
            }
        }
    }

    func confirmClear() {
        let a = NSAlert()
        a.messageText = "清空剪贴板历史？"
        a.informativeText = "置顶的和收藏夹里的会保留，其余全部删除，不可恢复。"
        a.addButton(withTitle: "取消")
        a.addButton(withTitle: "清空")
        a.buttons.forEach { $0.keyEquivalent = "" }
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertSecondButtonReturn {
            MainActor.assumeIsolated { AppModel.shared.clearHistory() }
        }
    }

    func confirmDelete(_ ids: Set<Int64>) {
        guard !ids.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "删除所选 \(ids.count) 条记录？"
        alert.informativeText = "记录与附带图片将从本地库删除，无法撤销。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "删除")
        alert.buttons.forEach { $0.keyEquivalent = "" }
        alert.alertStyle = .warning
        if alert.runModal() == .alertSecondButtonReturn { AppModel.shared.delete(ids) }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let raw = item.representedObject as? String, let action = ClipAction(rawValue: raw) else { continue }
            if let binding = shortcuts.binding(action) { item.title = "\(action.title)  ·  \(binding.chord.label)" }
            else { item.title = action.title }
        }
    }
}
