import Foundation
import AppKit
import ServiceManagement

enum AppPreferences {
    static var defaults: UserDefaults {
        if let suite = ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"], let defaults = UserDefaults(suiteName: suite) { return defaults }
        return .standard
    }
    /// The preferences domain in use: the isolated suite, or the app's own domain.
    static var domain: String {
        if let suite = ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"], !suite.isEmpty { return suite }
        return Bundle.main.bundleIdentifier ?? "cyou.tianli.clipbook"
    }
}

/// Ranges the Settings window offers (最多保留 N 条 Stepper, 保留时长 Picker); `clip settings set` uses the same.
enum RecordingLimits {
    static let maxItemsRange = 100...100000
    static let retentionChoices = [0, 7, 30, 90, 365]
    static func clampMaxItems(_ n: Int) -> Int { min(maxItemsRange.upperBound, max(maxItemsRange.lowerBound, n)) }
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
    @Published var copySoundName: String { didSet { d.set(copySoundName, forKey: "copySoundName") } }
    @Published var copySoundVolume: Double { didSet { d.set(copySoundVolume, forKey: "copySoundVolume") } }
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

    /// What is stored in the preferences domain, with the same defaults and clamps the window applies.
    struct Stored: Equatable {
        var paused: Bool, ignoredBundles: [String], maxItems: Int, retentionDays: Int, plainTextOnly: Bool
        var fetchLinkTitles: Bool, copySound: Bool, copySoundName: String, copySoundVolume: Double
        init(_ d: UserDefaults) {
            paused = d.bool(forKey: "paused")
            ignoredBundles = d.stringArray(forKey: "ignoredBundles") ?? []
            maxItems = RecordingLimits.clampMaxItems(d.object(forKey: "maxItems") as? Int ?? 5000)
            retentionDays = max(0, d.object(forKey: "retentionDays") as? Int ?? 0)
            plainTextOnly = d.bool(forKey: "plainTextOnly")
            fetchLinkTitles = d.object(forKey: "fetchLinkTitles") as? Bool ?? true
            copySound = d.object(forKey: "copySound") as? Bool ?? true
            let savedSound = d.string(forKey: "copySoundName") ?? "Tink"
            copySoundName = MainActor.assumeIsolated { CopyFeedback.soundNames }.contains(savedSound) ? savedSound : "Tink"
            copySoundVolume = min(1, max(0, d.object(forKey: "copySoundVolume") as? Double ?? 0.35))
        }
    }

    init(defaults: UserDefaults = AppPreferences.defaults) {
        d = defaults
        let v = Stored(defaults)
        paused = v.paused
        ignoredBundles = v.ignoredBundles
        maxItems = v.maxItems
        retentionDays = v.retentionDays
        plainTextOnly = v.plainTextOnly
        fetchLinkTitles = v.fetchLinkTitles
        copySound = v.copySound
        copySoundName = v.copySoundName
        copySoundVolume = v.copySoundVolume
        refreshLoginStatus()
    }

    /// Re-read the domain after another process (`clip settings set …`) changed it. Only changed values are
    /// assigned, so the watcher / store subscriptions fire exactly for what changed.
    func reload() {
        _ = d.synchronize()  // pick up the other process's write before reading
        let v = Stored(d)
        if paused != v.paused { paused = v.paused }
        if ignoredBundles != v.ignoredBundles { ignoredBundles = v.ignoredBundles }
        if maxItems != v.maxItems { maxItems = v.maxItems }
        if retentionDays != v.retentionDays { retentionDays = v.retentionDays }
        if plainTextOnly != v.plainTextOnly { plainTextOnly = v.plainTextOnly }
        if fetchLinkTitles != v.fetchLinkTitles { fetchLinkTitles = v.fetchLinkTitles }
        if copySound != v.copySound { copySound = v.copySound }
        if copySoundName != v.copySoundName { copySoundName = v.copySoundName }
        if copySoundVolume != v.copySoundVolume { copySoundVolume = v.copySoundVolume }
        refreshLoginStatus()  // `clip settings set launchAtLogin` changes the system login item
    }
}

/// User-facing name comes from project.yaml through the built Info.plist.
enum ProductIdentity {
    static var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ProcessInfo.processInfo.processName }
    static var cloudSupported: Bool {
        #if CLIP_LOCAL_DISTRIBUTION
        false
        #else
        true
        #endif
    }
    /// Explicit isolated previews must never activate over the user's current app.
    static var backgroundPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["CLIPBOOK_BACKGROUND"] == "1"
            && !(env["CLIPBOOK_HOME"] ?? "").isEmpty
            && !(env["CLIPBOOK_PREFERENCES_SUITE"] ?? "").isEmpty
    }
    static var pasteboard: NSPasteboard {
        if backgroundPreview {
            let suite = ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"]!
            return NSPasteboard(name: .init(suite + ".pasteboard"))
        }
        return .general
    }
}
