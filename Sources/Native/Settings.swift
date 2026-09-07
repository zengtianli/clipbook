import Foundation
import ServiceManagement

enum AppPreferences {
    static var defaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"], let defaults = UserDefaults(suiteName: suite) { return defaults }
        return .standard
    }
}

/// 记录偏好自动保存。快捷键由 ClipShortcuts 管理，默认空。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d: UserDefaults

    @Published var paused: Bool { didSet { d.set(paused, forKey: "paused") } }
    @Published var ignoredBundles: [String] { didSet { d.set(ignoredBundles, forKey: "ignoredBundles") } }
    @Published var maxItems: Int { didSet { d.set(maxItems, forKey: "maxItems") } }
    @Published var retentionDays: Int { didSet { d.set(retentionDays, forKey: "retentionDays") } }
    @Published var plainTextOnly: Bool { didSet { d.set(plainTextOnly, forKey: "plainTextOnly") } }
    @Published var fetchLinkTitles: Bool { didSet { d.set(fetchLinkTitles, forKey: "fetchLinkTitles") } }
    @Published var copySound: Bool { didSet { d.set(copySound, forKey: "copySound") } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchStatus = ""
    @Published private(set) var launchError: String?

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchError = nil
        } catch { launchError = "无法更新开机自启：\(error.localizedDescription)" }
        refreshLoginStatus()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled || status == .requiresApproval
        switch status {
        case .enabled: launchStatus = "已开启"
        case .requiresApproval: launchStatus = "等待系统批准：请在系统设置 → 通用 → 登录项中允许。"
        case .notRegistered: launchStatus = "已关闭"
        default: launchStatus = "系统尚未找到登录项，请从已安装的应用重试。"
        }
    }

    init(defaults: UserDefaults = AppPreferences.defaults) {
        d = defaults
        paused = d.bool(forKey: "paused")
        ignoredBundles = d.stringArray(forKey: "ignoredBundles") ?? []
        maxItems = min(100000, max(100, d.object(forKey: "maxItems") as? Int ?? 5000))
        retentionDays = max(0, d.object(forKey: "retentionDays") as? Int ?? 0)
        plainTextOnly = d.bool(forKey: "plainTextOnly")
        fetchLinkTitles = d.object(forKey: "fetchLinkTitles") as? Bool ?? true
        copySound = d.object(forKey: "copySound") as? Bool ?? true
        refreshLoginStatus()
    }
}

/// User-facing name comes from catalog.yaml through the built Info.plist.
enum ProductIdentity {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName }
}
