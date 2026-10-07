import AppKit
import Foundation

/// UI-free rules shared by the window (AppModel / views), the `clip` command and the self-tests.
/// Whatever a button validates or computes before it calls ClipStore lives here once, so the GUI
/// and the CLI cannot drift apart. No SwiftUI, no window state.

/// 「转换」菜单。纯函数；编辑器与 `clip transform` 共用。
enum Transform: String, CaseIterable, Identifiable {
    case plain, trim, upper, lower, capitalize, oneLine, json
    var id: String { rawValue }
    var label: String {
        switch self {
        case .plain:      return "转纯文本"
        case .trim:       return "去首尾空白"
        case .upper:      return "全大写"
        case .lower:      return "全小写"
        case .capitalize: return "首字母大写"
        case .oneLine:    return "去换行"
        case .json:       return "JSON 格式化"
        }
    }
    /// Name used on the command line (`clip transform <id> one-line`).
    var cliName: String { self == .oneLine ? "one-line" : rawValue }
    init?(cliName: String) {
        guard let t = Transform.allCases.first(where: { $0.cliName == cliName.lowercased() }) else { return nil }
        self = t
    }
    func apply(_ s: String) -> String {
        switch self {
        case .plain:      return s
        case .trim:       return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .upper:      return s.uppercased()
        case .lower:      return s.lowercased()
        case .capitalize: return s.capitalized
        case .oneLine:    return s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        case .json:
            guard let d = s.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d),
                  let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                  let str = String(data: out, encoding: .utf8) else { return s }
            return str
        }
    }
    /// What the editor offers for a record: editable kinds only, and 转纯文本 only for rich text.
    static func options(for kind: ClipItem.Kind) -> [Transform] {
        guard kind.editable else { return [] }
        return allCases.filter { $0 != .plain || kind == .richText }
    }
}

/// 收藏夹编辑器可选的图标与颜色（界面和 CLI 用同一份白名单）。
enum CollectionStyle {
    static let icons = ["folder", "star", "tag", "bookmark", "heart", "flag", "bolt", "briefcase", "book", "terminal", "doc.text", "link", "photo", "person", "cart", "globe"]
    static let colors = ["#2563eb", "#dc2626", "#ea580c", "#ca8a04", "#16a34a", "#0d9488", "#7c3aed", "#db2777", "#6b7280"]
    static let defaultIcon = "folder"
    static let defaultColor = "#2563eb"
}

enum ClipRules {
    /// Source recorded for records added by `clip add` (filterable with `--app`).
    static let cliAppName = "Clip CLI"
    static let cliBundle = "cyou.tianli.clipbook.cli"
    /// 合并成一条：至少两条，且只收文本家族（图片、文件不能合并）。nil = 可以合并。
    static func mergeRefusal(_ items: [ClipItem]) -> String? {
        if items.count < 2 { return "至少需要两条记录才能合并" }
        if items.contains(where: { $0.kind == .image || $0.kind == .file }) { return "图片和文件不能合并成一条文本" }
        return nil
    }

    /// 收藏夹上移 / 下移：相邻交换后的新顺序；越界或不存在返回 nil。
    static func reorder(_ ids: [Int64], moving id: Int64, by delta: Int) -> [Int64]? {
        var ids = ids
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { return nil }
        ids.swapAt(i, i + delta)
        return ids
    }

    /// 另存：保留原条目的来源与标题，把新正文作为一条新记录。
    static func saveAsNew(from item: ClipItem, text: String) -> Capture {
        Capture(kind: Classifier.kind(of: text), text: text, appName: item.appName, appBundle: item.appBundle, title: item.title)
    }

    /// 导出图片原图（PNG）。界面在保存面板确认覆盖后传 overwrite: true。
    static func exportImage(_ item: ClipItem, store: ClipStore, to dest: URL, overwrite: Bool) throws {
        guard item.kind == .image, let src = store.blobURL(item) else { throw ActionError.invalid("只有图片记录可以导出 PNG") }
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { throw ActionError.invalid("原图文件已不在数据目录里") }
        if fm.fileExists(atPath: dest.path) {
            guard overwrite else { throw ActionError.invalid("目标文件已存在：\(dest.path)") }
            try fm.removeItem(at: dest)
        }
        try fm.copyItem(at: src, to: dest)
    }

    /// 一张图片（任意 NSImage 可读格式）→ 入库用的 Capture；PNG 原样保留，其余转 PNG。
    static func imageCapture(_ data: Data, appName: String, appBundle: String, title: String = "") -> Capture? {
        guard let rep = NSBitmapImageRep(data: data) else { return nil }
        let png = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? data : rep.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return Capture(kind: .image, text: "图片 \(rep.pixelsWide)×\(rep.pixelsHigh)", imagePNG: png,
                       width: rep.pixelsWide, height: rep.pixelsHigh, appName: appName, appBundle: appBundle, title: title)
    }

    enum ActionError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String { if case .invalid(let m) = self { return m }; return "" }
    }
}

/// The preferences the 「配置与更新」 window exports, imports and optionally keeps in iCloud.
/// One definition for the window (AppDelegate) and `clip config`.
enum ClipPortableConfiguration {
    static let productID = "cyou.tianli.clipbook"
    static let keys = ["ignoredBundles", "maxItems", "retentionDays", "plainTextOnly", "fetchLinkTitles",
                       "copySound", "copySoundName", "copySoundVolume", "shortcuts.v1"]
    static func make(defaults: UserDefaults) -> AppConfiguration {
        AppConfiguration(productID: productID, defaultsKeys: keys, defaults: defaults)
    }
}

/// Cross-process requests from `clip` to a running Clip. They carry no data: they ask the app to re-read state it
/// already owns (the store / its preferences) or to run one of its own iCloud actions (the same code the Settings
/// buttons call). The CLI itself never opens a sync container. The one request that needs data — which record of the
/// synced history to change — leaves it in a file first (`ClipCloudChange`).
enum ClipSignal {
    /// `clip cloud favorite|unfavorite|delete`: changes waiting in the data dir (`ClipCloudChange.pending`).
    static let cloudChangeRequested = Notification.Name("cyou.tianli.clipbook.cloudChangeRequested")
    static let storeChanged = Notification.Name("cyou.tianli.clipbook.storeChanged")
    static let preferencesChanged = Notification.Name("cyou.tianli.clipbook.preferencesChanged")
    /// 设置 → iCloud 「补充最近历史」.
    static let cloudPushRequested = Notification.Name("cyou.tianli.clipbook.cloudPushRequested")
    /// 设置 → iCloud 「iCloud 历史归档」开关 (the app runs its account checks as for the toggle).
    static let cloudEnableRequested = Notification.Name("cyou.tianli.clipbook.cloudEnableRequested")
    static let cloudDisableRequested = Notification.Name("cyou.tianli.clipbook.cloudDisableRequested")
    /// 配置与更新 → 「使用 iCloud 记住配置」开关 (scope = the preferences domain; the app owns the sync).
    static let configSyncEnableRequested = Notification.Name("cyou.tianli.clipbook.configSyncEnableRequested")
    static let configSyncDisableRequested = Notification.Name("cyou.tianli.clipbook.configSyncDisableRequested")

    static func post(_ name: Notification.Name, scope: String) {
        DistributedNotificationCenter.default().postNotificationName(name, object: scope, userInfo: nil, deliverImmediately: true)
    }

    /// `scope` is the store home path (storeChanged) or the preferences domain (preferencesChanged):
    /// an isolated CLI run never makes the user's app reload.
    @discardableResult
    static func observe(_ name: Notification.Name, scope: String, _ handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: scope, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }
}

/// One change to a record of the synced history — the phone's 收藏 / 取消收藏 / 删除 — asked by `clip` and carried out by
/// the running app, which owns the archive (the command line never opens a second sync container). A distributed
/// notification carries no data, so the request and the app's answer are two small files in the data dir:
/// `cloud-requests/<id>.request.json`, then `<id>.answer.json`. Each side removes what it has read.
struct ClipCloudChange: Codable, Equatable {
    enum Action: String, Codable, CaseIterable { case favorite, unfavorite, delete }
    struct Answer: Codable, Equatable {
        var ok: Bool
        /// "not_found" (the record is gone, e.g. deleted on another device meanwhile) or "store".
        var code: String?
        var message: String?
    }
    var id: String
    var action: Action
    var key: String
    var at: Date

    /// A request nobody answered in this long is dropped unread: the command that left it has stopped waiting.
    static let lifetime: TimeInterval = 60
    static func directory(home: URL) -> URL { home.appendingPathComponent("cloud-requests", isDirectory: true) }
    private func url(_ kind: String, home: URL) -> URL { Self.directory(home: home).appendingPathComponent("\(id).\(kind).json") }
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }
    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }

    /// The command's side: leave the request for the app.
    func leave(home: URL) throws {
        try FileManager.default.createDirectory(at: Self.directory(home: home), withIntermediateDirectories: true)
        try Self.encoder.encode(self).write(to: url("request", home: home), options: .atomic)
    }
    /// The command's side: the app's answer, once it is there.
    func takeAnswer(home: URL) -> Answer? {
        let file = url("answer", home: home)
        guard let data = try? Data(contentsOf: file), let answer = try? Self.decoder.decode(Answer.self, from: data) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return answer
    }
    /// The command's side, when it stops waiting: nothing of this request stays behind.
    func withdraw(home: URL) {
        for kind in ["request", "answer"] { try? FileManager.default.removeItem(at: url(kind, home: home)) }
    }
    /// The app's side: every request waiting, oldest first, each taken (removed) as it is read. Expired ones are dropped.
    static func pending(home: URL, now: Date = Date()) -> [ClipCloudChange] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory(home: home), includingPropertiesForKeys: nil)) ?? []
        var changes: [ClipCloudChange] = []
        for file in files where file.lastPathComponent.hasSuffix(".request.json") {
            defer { try? FileManager.default.removeItem(at: file) }
            guard let data = try? Data(contentsOf: file), let change = try? decoder.decode(ClipCloudChange.self, from: data),
                  file.lastPathComponent == "\(change.id).request.json", now.timeIntervalSince(change.at) < lifetime else { continue }
            changes.append(change)
        }
        return changes.sorted { $0.at < $1.at }
    }
    /// The app's side: what became of it.
    func answer(_ answer: Answer, home: URL) {
        try? FileManager.default.createDirectory(at: Self.directory(home: home), withIntermediateDirectories: true)
        try? Self.encoder.encode(answer).write(to: url("answer", home: home), options: .atomic)
    }
}
