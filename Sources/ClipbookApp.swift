import AppKit
import SwiftUI
import ServiceManagement

/// Clipbook —— 自用剪贴板历史。菜单栏常驻（无 Dock 图标），⌘⇧V 唤出面板，回车粘贴。
///
/// 全 Swift 原生，无后端进程、无网络。数据落 ~/Library/Application Support/Clipbook/。
/// 只做 Deck 里真在用的 20%：记录（文本/链接/图片/文件）· 搜索 · 置顶 · 回车粘贴。
/// 不做：AI、跨设备同步、SmartRules、标签。
@main
enum Boot {
    static func main() {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
        ClipbookApp.main()
    }
}

struct ClipbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "doc.on.clipboard")
        }
    }
}

struct MenuContent: View {
    @ObservedObject private var model = AppModel.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Button("打开面板　\(HotKeyCenter.shared.label)") { AppDelegate.shared.panel.show() }
        Toggle("暂停记录", isOn: $model.paused)
        Divider()
        Text("\(model.total) 条记录").foregroundStyle(.secondary)
        Text(HotKeyCenter.shared.status).foregroundStyle(.secondary)
        if !Paster.accessibilityTrusted {
            Button("授权辅助功能（回车自动粘贴）…") { Paster.promptAccessibility() }
        }
        Divider()
        Toggle("开机自启", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
            }
        Button("清空历史（保留置顶）…") { AppDelegate.shared.confirmClear() }
        Button("打开数据目录") { NSWorkspace.shared.open(model.store.home) }
        Divider()
        Button("退出 Clipbook") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var panel: PanelController!

    override init() {
        super.init()
        AppDelegate.shared = self
        // 数据库开不了就直说并退出 —— 一个默默不记录的剪贴板工具比没有更糟。
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

    func applicationDidFinishLaunching(_ note: Notification) {
        MainActor.assumeIsolated {
            panel = PanelController(model: AppModel.shared)
            AppModel.shared.startWatching()
            HotKeyCenter.shared.register()
        }
        NotificationCenter.default.addObserver(forName: HotKeyCenter.summonNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared.panel.toggle() }
        }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:_:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    /// clipbook://show · clipbook://hide · clipbook://toggle —— 给 Hammerspoon / Raycast / 自动化用
    @objc func handleURL(_ event: NSAppleEventDescriptor, _ reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s) else { return }
        MainActor.assumeIsolated {
            switch url.host {
            case "show":   panel.show()
            case "hide":   panel.hide()
            case "toggle": panel.toggle()
            default: break
            }
        }
    }

    func confirmClear() {
        let a = NSAlert()
        a.messageText = "清空剪贴板历史？"
        a.informativeText = "置顶的条目会保留，其余全部删除，不可恢复。"
        a.addButton(withTitle: "清空")
        a.addButton(withTitle: "取消")
        a.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            MainActor.assumeIsolated { AppModel.shared.clearHistory() }
        }
    }
}
