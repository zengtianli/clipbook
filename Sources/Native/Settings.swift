import Foundation
import ServiceManagement

/// 设置（UserDefaults）。没有快捷键项 —— 用户明确说先不设。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var ignoredBundles: [String] { didSet { d.set(ignoredBundles, forKey: "ignoredBundles") } }
    @Published var maxItems: Int { didSet { d.set(maxItems, forKey: "maxItems") } }
    @Published var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    @Published var plainTextOnly: Bool { didSet { d.set(plainTextOnly, forKey: "plainTextOnly") } }
    @Published var fetchLinkTitles: Bool { didSet { d.set(fetchLinkTitles, forKey: "fetchLinkTitles") } }
    @Published var launchAtLogin: Bool {
        didSet {
            do { if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { launchAtLogin = SMAppService.mainApp.status == .enabled }
        }
    }

    private init() {
        paused = d.bool(forKey: "paused")
        ignoredBundles = d.stringArray(forKey: "ignoredBundles") ?? []
        maxItems = d.object(forKey: "maxItems") as? Int ?? 5000
        retentionDays = d.object(forKey: "retentionDays") as? Int ?? 0
        plainTextOnly = d.bool(forKey: "plainTextOnly")
        fetchLinkTitles = d.object(forKey: "fetchLinkTitles") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
