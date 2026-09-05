import AppKit
import SwiftUI

/// Clipbook —— 自用剪贴板库（PastePal 形态）。菜单栏常驻，点图标开主窗口；左筛、中挑、右改。
///
/// 全 Swift 原生。除「抓链接标题」外无网络。数据落 ~/Library/Application Support/Clipbook/。
/// **不设任何快捷键**（用户 2026-09-05 明确要求）。
@main
enum Boot {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
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

    override init() {
        super.init()
        AppDelegate.shared = self
        MainActor.assumeIsolated {
            do {
                AppModel.shared = try AppModel()
            } catch {
                let a = NSAlert()
                a.messageText = "Clipbook 启动失败"
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
        appMenu.addItem(withTitle: "关于 Clipbook", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 Clipbook", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 Clipbook", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "关闭", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.startWatching()
            buildStatusItem()
            buildWindow()
            if ProcessInfo.processInfo.environment["CLIPBOOK_SHOW_ON_LAUNCH"] == "1" { showWindow() }
            // 首次启动且本机有 Deck → 自动把它的历史导进来（用户 2026-09-05 拍板；只读 Deck 的库）
            if AppModel.shared.deckImportedAt == nil, DeckImporter.available() { AppModel.shared.importDeck() }
        }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:_:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    // MARK: 菜单栏：左键开窗口，右键出菜单

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipbook")
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
        menu.addItem(withTitle: "打开 Clipbook", action: #selector(menuOpen), keyEquivalent: "")
        let pause = menu.addItem(withTitle: "暂停记录", action: #selector(menuTogglePause), keyEquivalent: "")
        pause.state = s.paused ? .on : .off
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(AppModel.shared.totalAll) 条记录", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(menuSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Clipbook", action: #selector(menuQuit), keyEquivalent: "")
        for it in menu.items { it.target = self }
    }

    @objc private func menuOpen() { showWindow() }
    @objc private func menuTogglePause() { AppSettings.shared.paused.toggle(); AppModel.shared.applySettings() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: 主窗口

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Clipbook"
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 960, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setFrameAutosaveName("ClipbookMain")
        window.contentView = NSHostingView(rootView: MainView(model: AppModel.shared, hideWindow: { [weak self] in self?.window.orderOut(nil) }))
        window.center()
    }

    func showWindow() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.bundleIdentifier != Bundle.main.bundleIdentifier { AppModel.shared.previousApp = front }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func toggleWindow() {
        if window.isVisible && window.isKeyWindow { window.orderOut(nil) } else { showWindow() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Clipbook 设置"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: AppModel.shared, settings: AppSettings.shared))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// 关窗口 = 隐藏，不退出（菜单栏常驻）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    /// clipbook://show[?q=关键词] · clipbook://hide · clipbook://toggle · clipbook://settings
    @objc func handleURL(_ event: NSAppleEventDescriptor, _ reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
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
        a.addButton(withTitle: "清空")
        a.addButton(withTitle: "取消")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            MainActor.assumeIsolated { AppModel.shared.clearHistory() }
        }
    }
}

extension AppDelegate: NSMenuDelegate {}
