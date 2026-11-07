import AppKit
import SwiftUI

/// The release channel behind the 「配置与更新」 window and `clip update check`: one definition for both.
/// Public local packages follow the existing public repository release channel.
#if !APP_STORE
enum ClipUpdates {
    #if CLIP_LOCAL_DISTRIBUTION
    static let source: AppUpdateSource = .github(repository: "zengtianli/clipbook")
    #else
    static var source: AppUpdateSource { .privateCloud(channel: ProductIdentity.cloudSupported ? "cloud" : "local") }
    #endif
}
#endif

/// Uses the production view without taking focus during an isolated capture.
private final class ClipPreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

extension ProductIdentity {
    /// An isolated instance started in the background (`clip start` from an isolated run: a test, a sandbox) is an
    /// agent's, not the user's. It stays out of the Dock and the menu bar and nothing of it comes on screen; the
    /// user's own Clip is never started this way (it has no isolated data dir).
    static var unattended: Bool { backgroundPreview && CommandLine.arguments.contains("--background") }
}

/// Clipbook —— 自用剪贴板库（PastePal 形态）。菜单栏常驻，点图标开主窗口；左筛、中挑、右改。
///
/// 全 Swift 原生。除「抓链接标题」外无网络。数据落 ~/Library/Application Support/Clipbook/。
/// 快捷键可自定义，默认不绑定、不注册。
@main
enum Boot {
    static func main() {
        #if APP_STORE
        if CommandLine.arguments.contains("--store-self-test") {
            exit(MainActor.assumeIsolated { StoreSelfTest.run() })
        }
        #endif
        // `clip …` (Contents/Resources/bin/clip) and CLI verbs: the agent-facing command line. No NSApplication.
        if ClipCLI.requested(CommandLine.arguments) { exit(ClipCLI.main(CommandLine.arguments)) }
        if CommandLine.arguments.contains("--keyboard-window-test") {
            exit(MainActor.assumeIsolated { KeyboardMemorySelfTest.windowRuntime() })
        }
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
            #if APP_STORE
            MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.prohibited) }
            #endif
            exit(MainActor.assumeIsolated { ShortcutSelfTest.runtime() })
        }
        // Isolated acceptance entries: no Dock icon, no status item, no AppDelegate, nothing ordered on screen.
        let args = CommandLine.arguments
        #if !APP_STORE
        if let i = args.firstIndex(of: "--product-basics-self-test"), args.indices.contains(i + 1) {
            exit(MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.prohibited)
                return ProductBasicsSelfTest.run(out: URL(fileURLWithPath: args[i + 1]))
            })
        }
        #endif
        if let i = args.firstIndex(of: "--ui-self-test") {
            exit(MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.prohibited)
                return UISelfTest.run(outdir: args.indices.contains(i + 1) ? args[i + 1] : nil)
            })
        }
        if let i = args.firstIndex(of: "--l10n-self-test") {
            exit(MainActor.assumeIsolated {
                NSApplication.shared.setActivationPolicy(.prohibited)
                return L10nShots.run(outdir: args.indices.contains(i + 1) ? args[i + 1] : nil)
            })
        }
        if args.contains("--recovery-test") {
            exit(MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.prohibited); return RecoverySelfTest.run() })
        }
        if args.contains("--privacy-test") {
            exit(MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.prohibited); return PrivacySelfTest.run() })
        }
        // This process stands in for the running Clip (production wiring, nothing on screen) while the real `clip`
        // command runs beside it as separate processes. Opt-in (tests/test-runtime.sh): it registers two test hot keys.
        if args.contains("--runtime-self-test") {
            exit(MainActor.assumeIsolated { NSApplication.shared.setActivationPolicy(.prohibited); return RuntimeSelfTest.run() })
        }
        if CommandLine.arguments.contains("--selftest") {
            #if !APP_STORE
            #if CLIP_LOCAL_DISTRIBUTION
            guard case .github(let repository) = ClipUpdates.source,
                  repository == "zengtianli/clipbook" else {
                print("FAIL public local update source")
                exit(1)
            }
            print("PASS public local update source: GitHub zengtianli/clipbook")
            #endif
            #endif
            exit(SelfTest.run())
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(ProductIdentity.unattended ? .accessory : .regular)
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
    private var runtimeState: ClipRuntimePublisher?
    private(set) var configuration: AppConfiguration?

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
                a.messageText = String(localized: "\(ProductIdentity.name) 启动失败")
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
    /// 窗口与隐藏的系统标配（⌘W 关闭、⌘M 最小化、⌘H 隐藏、⌥⌘H 隐藏其他）同理。本 app 自己不绑任何快捷键。
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "关于 \(ProductIdentity.name)"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: String(localized: "设置…"), action: #selector(menuSettings), keyEquivalent: "")
        settingsItem.target = self
        #if !APP_STORE
        for item in AppLifecycleUI.menuItems() { appMenu.addItem(item) }
        #endif
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "隐藏 \(ProductIdentity.name)"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: String(localized: "隐藏其他"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: String(localized: "全部显示"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        // ⌘Q 不绑在这里：常驻菜单栏（MenuBarResident）把 ⌘Q 改成关窗，真退出走菜单栏下拉的「退出」。
        appMenu.addItem(withTitle: String(localized: "退出 \(ProductIdentity.name)"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: String(localized: "编辑"))
        edit.addItem(withTitle: String(localized: "撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "重做"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = edit.addItem(withTitle: String(localized: "拷贝"), action: #selector(menuCopy), keyEquivalent: "c")
        copy.target = self
        edit.addItem(withTitle: String(localized: "粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let actionsItem = NSMenuItem(); main.addItem(actionsItem)
        let actions = NSMenu(title: String(localized: "记录"))
        for action in ClipAction.allCases where action != .quit && action != .settings {
            let item = actions.addItem(withTitle: L10n.display(action.title), action: #selector(menuAction(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = action.rawValue
        }
        actions.delegate = self
        actionsItem.submenu = actions

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: String(localized: "窗口"))
        window.addItem(withTitle: String(localized: "最小化"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: String(localized: "缩放"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(.separator())
        window.addItem(withTitle: String(localized: "关闭"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        MainActor.assumeIsolated {
            if !ProductIdentity.backgroundPreview {
                installLifecycle()
                #if !APP_STORE
                // 菜单栏下拉快捷键 = 左键点图标（Clip 左键开主窗口，本人 2026-10-20 认可）；常驻菜单栏，关窗只隐藏、真退出在菜单里。
                // 只在用户的 Clip 里装：隔离预览、自测和 `clip` 命令行都不经过这里。
                MenuBarHotKey.install(default: "⌃⌥V")
                MenuBarResident.install()
                #endif
            }
            AppModel.shared.startWatching()
            if ProductIdentity.cloudSupported && AppPreferences.defaults.bool(forKey: "cloudEnabled") { AppModel.shared.cloud.start() }
            if !ProductIdentity.unattended { buildStatusItem() }
            buildWindow()
            connectCommandLine()
            if CommandLine.arguments.contains("--background") {
                AppModel.shared.suspendInterface()
            } else {
                showWindow()
            }
            // 首次启动且本机有 Deck → 自动把它的历史导进来（用户 2026-09-05 拍板；只读 Deck 的库）
            #if !APP_STORE
            if ProcessInfo.processInfo.environment["CLIPBOOK_HOME"] == nil,
               AppModel.shared.deckImportedAt == nil, DeckImporter.available() { AppModel.shared.importDeck() }
            #endif
        }
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach { handleURL($0) }
        let actions = pendingActions; pendingActions = []
        actions.forEach { perform($0) }
    }

    /// The 「配置与更新」 window and the portable configuration behind it. Also called by `--runtime-self-test`
    /// (on isolated directories), so the test exercises this wiring and not a copy of it.
    func installLifecycle() {
        let config = ClipPortableConfiguration.make(defaults: AppPreferences.defaults)
        config.onChange = { [weak self] in AppSettings.shared.reload(); AppModel.shared.applySettings(); self?.shortcuts.reload() }
        configuration = config
        #if APP_STORE
        config.start()
        #else
        AppLifecycleUI.install(name: "Clip", configuration: config, updateSource: ClipUpdates.source)
        #endif
    }

    /// Builds the production window without showing it, only for isolated process-internal acceptance.
    func prepareBasicsWindow() -> NSWindow { buildWindow(); return window }

    /// The main menu and the menu bar menu as the user gets them, written out as titles (`--l10n-self-test`).
    func menuTitlesForCapture() -> [String] {
        installMainMenu()
        rebuildMenu()
        var titles: [String] = []
        for item in NSApp.mainMenu?.items ?? [] {
            guard let submenu = item.submenu else { continue }
            titles.append("▸ " + (submenu.title.isEmpty ? ProductIdentity.name : submenu.title))
            titles += submenu.items.filter { !$0.isSeparatorItem }.map { "    " + $0.title }
        }
        titles.append("▸ " + ProductIdentity.name + " (menu bar)")
        titles += menu.items.filter { !$0.isSeparatorItem }.map { "    " + $0.title }
        return titles
    }

    /// Everything `clip` asks of this running app and reads from it. Also called by `--runtime-self-test`.
    func connectCommandLine() {
        // `clip` changed the library or the preferences from another process: re-read what this app owns,
        // and archive new records as a capture would be when iCloud is on.
        let home = AppModel.shared.store.home.path
        let cloudOn = { ProductIdentity.cloudSupported && AppPreferences.defaults.bool(forKey: "cloudEnabled") }
        ClipSignal.observe(ClipSignal.storeChanged, scope: home) {
            AppModel.shared.reload()
            if cloudOn() { AppModel.shared.cloud.storeChangedExternally() }
        }
        ClipSignal.observe(ClipSignal.preferencesChanged, scope: AppPreferences.domain) {
            AppSettings.shared.reload(); AppModel.shared.applySettings()
            AppDelegate.shared.shortcuts.reload()   // `clip shortcut scope|clear`, `clip config import`
        }
        // `clip config sync on|off`: the 配置与更新 window's 「使用 iCloud 记住配置」 checkbox, run by this app.
        ClipSignal.observe(ClipSignal.configSyncEnableRequested, scope: AppPreferences.domain) { AppDelegate.shared.configuration?.setEnabled(true) }
        ClipSignal.observe(ClipSignal.configSyncDisableRequested, scope: AppPreferences.domain) { AppDelegate.shared.configuration?.setEnabled(false) }
        // `clip cloud push|on|off`: the Settings → iCloud button and toggle, run by this app.
        if ProductIdentity.cloudSupported {
            ClipSignal.observe(ClipSignal.cloudPushRequested, scope: home) { Task { await AppModel.shared.cloud.pushRequested() } }
            ClipSignal.observe(ClipSignal.cloudEnableRequested, scope: home) { Task { await AppModel.shared.cloud.enable(true) } }
            ClipSignal.observe(ClipSignal.cloudDisableRequested, scope: home) { Task { await AppModel.shared.cloud.enable(false) } }
            // `clip cloud favorite|unfavorite|delete`: the phone's 收藏 / 取消收藏 / 删除 on the synced history, run by this app.
            ClipSignal.observe(ClipSignal.cloudChangeRequested, scope: home) { Task { await AppModel.shared.cloud.changesRequested() } }
        }
        // What only this process knows (Accessibility grant, global-key registration, live iCloud status) for `clip` to read.
        let runtime = ClipRuntimePublisher(home: AppModel.shared.store.home, shortcuts: shortcuts, cloud: { AppModel.shared.cloudIfLoaded })
        AppModel.shared.onCloudLoaded = { [weak runtime] in DispatchQueue.main.async { MainActor.assumeIsolated { runtime?.publish() } } }
        runtimeState = runtime
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
        menu.addItem(withTitle: String(localized: "打开 \(ProductIdentity.name)"), action: #selector(menuOpen), keyEquivalent: "")
        let pause = menu.addItem(withTitle: String(localized: "暂停记录"), action: #selector(menuTogglePause), keyEquivalent: "")
        pause.state = s.paused ? .on : .off
        menu.addItem(.separator())
        let count = (try? AppModel.shared.store.count()) ?? AppModel.shared.totalAll
        menu.addItem(withTitle: String(localized: "\(count) 条记录"), action: nil, keyEquivalent: "")
        menu.addItem(withTitle: String(localized: "设置…"), action: #selector(menuSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "退出 \(ProductIdentity.name)"), action: #selector(menuQuit), keyEquivalent: "")
        for it in menu.items { it.target = self }
        #if !APP_STORE
        for item in AppLifecycleUI.menuItems() { menu.insertItem(item, at: menu.numberOfItems - 1) }
        #endif
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
            case .paste: if let item = model.detail { model.paste(item, hideWindow: { self.hideWindow() }) }
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

    /// 常驻菜单栏：关掉最后一个窗口不退出，真退出只走菜单栏菜单里的「退出 Clip」。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: 主窗口

    private func buildWindow() {
        window = ProductIdentity.backgroundPreview
            ? ClipPreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 760),
                               styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                               backing: .buffered, defer: false)
            : NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1380, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = ProductIdentity.name
        window.titlebarAppearsTransparent = false
        window.minSize = NSSize(width: 960, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        // An unattended instance never shows this window, and AppKit keeps window frames in the app's own standard
        // domain whatever preferences suite the instance was given: saving one here would move the user's window.
        if !ProductIdentity.unattended { window.setFrameAutosaveName("ClipbookMain") }
        window.contentView = nil
        window.center()
    }

    func showWindow() {
        if window.contentView == nil {
            AppModel.shared.resumeInterface()
            window.contentView = NSHostingView(rootView: MainView(model: AppModel.shared, hideWindow: { [weak self] in self?.hideWindow() }))
        }
        if ProductIdentity.backgroundPreview {
            window.orderBack(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window, window.isKeyWindow,
                  !(window.firstResponder is NSTextView),
                  let grid = GridKeyboard.Responder.find(in: window.contentView) else { return }
            window.makeFirstResponder(grid)
        }
    }

    func hideWindow() {
        guard window.attachedSheet == nil else { return }
        window.orderOut(nil)
        window.contentView = nil
        AppModel.shared.suspendInterface()
    }

    func toggleWindow() {
        if window.isVisible && window.isKeyWindow { hideWindow() } else { showWindow() }
    }

    func showSettings() {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 650),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = String(localized: "\(ProductIdentity.name) 设置")
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.minSize = NSSize(width: 580, height: 450)
            w.contentView = NSHostingView(rootView: SettingsView(model: AppModel.shared, settings: AppSettings.shared, shortcuts: shortcuts))
            w.center()
            settingsWindow = w
        }
        if ProductIdentity.backgroundPreview {
            settingsWindow?.orderBack(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    /// 关窗口 = 隐藏，不退出（菜单栏常驻）
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow {
            shortcuts.endRecording()
            sender.orderOut(nil)
            sender.contentView = nil
            settingsWindow = nil
        } else if sender === window { hideWindow() }
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
            case "hide":     hideWindow()
            case "toggle":   toggleWindow()
            case "settings": showSettings()
            default: break
            }
        }
    }

    func confirmClear() {
        let a = NSAlert()
        a.messageText = String(localized: "清空剪贴板历史？")
        a.informativeText = String(localized: "置顶的和收藏夹里的会保留，其余全部删除，不可恢复。")
        a.addButton(withTitle: String(localized: "取消"))
        a.addButton(withTitle: String(localized: "清空"))
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
        alert.messageText = String(localized: "删除所选 \(ids.count) 条记录？")
        alert.informativeText = String(localized: "记录与附带图片将从本地库删除，无法撤销。")
        alert.addButton(withTitle: String(localized: "取消")); alert.addButton(withTitle: String(localized: "删除"))
        alert.buttons.forEach { $0.keyEquivalent = "" }
        alert.alertStyle = .warning
        if alert.runModal() == .alertSecondButtonReturn { AppModel.shared.delete(ids) }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let raw = item.representedObject as? String, let action = ClipAction(rawValue: raw) else { continue }
            if let binding = shortcuts.binding(action) { item.title = "\(L10n.display(action.title))  ·  \(binding.chord.label)" }
            else { item.title = L10n.display(action.title) }
        }
    }
}
