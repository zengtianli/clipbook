import AppKit
import SwiftUI
import os

let clipLog = Logger(subsystem: "cyou.tianli.clipbook", category: "model")

enum SidebarSelection: Hashable {
    case all, pinned
    case kind(ClipItem.Kind)
    case app(String)
    case collection(Int64)
}

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
}

/// 窗口与菜单共用的状态。所有落盘走 ClipStore；这里只做「查出来给界面」与「按钮→动作」。
@MainActor
final class AppModel: ObservableObject {
    static var shared: AppModel!

    let store: ClipStore
    let settings = AppSettings.shared
    private(set) var watcher: PasteboardWatcher!

    @Published var sidebar: SidebarSelection = .all { didSet { if sidebar != oldValue { page = 0; selection = []; reload() } } }
    @Published var search = "" { didSet { if search != oldValue { page = 0; reload() } } }
    @Published private(set) var page = 0
    let pageSize = 120

    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var total = 0
    @Published private(set) var totalAll = 0
    @Published var selection: Set<Int64> = [] { didSet { refreshDetail() } }
    private var anchorID: Int64?
    /// 单选时的详情条目（独立查一次，编辑保存后立即刷新）
    @Published private(set) var detail: ClipItem?
    @Published private(set) var detailCollections: Set<Int64> = []

    @Published private(set) var kindCounts: [ClipItem.Kind: Int] = [:]
    @Published private(set) var appCounts: [ClipStore.AppCount] = []
    @Published private(set) var collections: [Collection] = []
    @Published private(set) var collectionCounts: [Int64: Int] = [:]
    @Published private(set) var collectionMap: [Int64: [Int64]] = [:]

    @Published var notice: String?
    @Published var importReport: String?
    @Published var importing = false

    /// 打开窗口前的前台 app —— 「粘贴」要把它拉回来
    var previousApp: NSRunningApplication?
    private var promptedAccessibility = false

    private let thumbs = NSCache<NSNumber, NSImage>()
    private var iconCache: [String: NSImage] = [:]

    init(home: URL = ClipStore.defaultHome()) throws {
        store = try ClipStore(home: home)
        watcher = PasteboardWatcher { [weak self] cap in self?.ingest(cap) }
        applySettings()
        reload()
    }

    func applySettings() {
        watcher.paused = settings.paused
        watcher.ignoredBundles = Set(settings.ignoredBundles)
        watcher.plainTextOnly = settings.plainTextOnly
        store.maxItems = max(settings.maxItems, 50)
        store.retentionDays = settings.retentionDays
    }

    func startWatching() { watcher.start() }

    var filter: ClipStore.Filter {
        var f = ClipStore.Filter(text: search)
        switch sidebar {
        case .all: break
        case .pinned: f.pinnedOnly = true
        case .kind(let k): f.kind = k
        case .app(let b): f.appBundle = b
        case .collection(let c): f.collection = c
        }
        return f
    }

    var pageCount: Int { max(1, (total + pageSize - 1) / pageSize) }

    // MARK: - 数据

    private func ingest(_ cap: Capture) {
        do {
            let it = try store.ingest(cap)
            reload()
            if it.kind == .link, it.extra.isEmpty, settings.fetchLinkTitles {
                Task { [weak self] in
                    guard let title = await LinkTitle.fetch(it.text) else { return }
                    try? self?.store.setExtra(it.id, title)
                    self?.reload()
                }
            }
        } catch {
            notice = "记录失败：\(error)"
        }
    }

    func reload() {
        do {
            let f = filter
            items = try store.list(f, page: page, pageSize: pageSize)
            total = try store.count(f)
            totalAll = try store.count()
            kindCounts = try store.kindCounts()
            appCounts = try store.appCounts()
            collections = try store.collections()
            collectionCounts = try store.collectionCounts()
            collectionMap = try store.collectionMap(for: items.map(\.id))
        } catch {
            notice = "读取失败：\(error)"
            items = []
        }
        selection = selection.filter { id in items.contains { $0.id == id } }
        refreshDetail()
    }

    private func refreshDetail() {
        guard selection.count == 1, let id = selection.first else { detail = nil; detailCollections = []; return }
        detail = try? store.item(id: id)
        detailCollections = (try? store.collectionIDs(of: id)) ?? []
    }

    func setPage(_ p: Int) {
        page = min(max(p, 0), pageCount - 1)
        selection = []
        reload()
    }

    // MARK: - 选择

    func click(_ id: Int64, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchorID = id
        } else if modifiers.contains(.shift), let a = anchorID,
                  let i = items.firstIndex(where: { $0.id == a }), let j = items.firstIndex(where: { $0.id == id }) {
            selection = Set(items[min(i, j)...max(i, j)].map(\.id))
        } else {
            selection = [id]
            anchorID = id
        }
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    // MARK: - 动作

    func copy(_ item: ClipItem) {
        watcher.suppressedChangeCount = Paster.write(item, store: store)
        try? store.touch(item.id)
        reload()
        notice = "已复制到剪贴板"
    }

    /// 粘贴到打开窗口前的那个 app。返回 false = 只复制了（没辅助功能授权）
    @discardableResult
    func paste(_ item: ClipItem, hideWindow: () -> Void) -> Bool {
        copy(item)
        hideWindow()
        previousApp?.activate()
        guard Paster.accessibilityTrusted else {
            // 没授权：内容已在剪贴板、原 app 已拉回前台，用户按一下 ⌘V 即可；系统授权提示只弹一次
            if !promptedAccessibility { promptedAccessibility = true; Paster.promptAccessibility() }
            notice = "已复制并切回 \(previousApp?.localizedName ?? "原 app")；授权「辅助功能」后才会自动粘贴"
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = Paster.sendCommandV() }
        return true
    }

    func delete(_ ids: Set<Int64>) {
        do { try store.delete(Array(ids)) } catch { notice = "删除失败：\(error)" }
        ids.forEach { thumbs.removeObject(forKey: NSNumber(value: $0)) }
        selection = []
        reload()
    }

    func togglePin(_ item: ClipItem) {
        try? store.setPinned(item.id, !item.pinned)
        reload()
    }

    func saveText(_ item: ClipItem, text: String) {
        do {
            _ = try store.updateText(item.id, text: text)
            reload()
            notice = "已保存"
        } catch { notice = "保存失败：\(error)" }
    }

    func saveAsNew(from item: ClipItem, text: String) {
        do {
            let it = try store.ingest(Capture(kind: Classifier.kind(of: text), text: text,
                                              appName: item.appName, appBundle: item.appBundle, title: item.title))
            reload()
            selection = [it.id]
            notice = "已另存为新条目"
        } catch { notice = "另存失败：\(error)" }
    }

    func setTitle(_ item: ClipItem, _ title: String) {
        try? store.setTitle(item.id, title)
        reload()
    }

    func apply(_ t: Transform, to item: ClipItem) {
        let out = t.apply(item.text)
        do {
            let it = try store.updateText(item.id, text: out)
            watcher.suppressedChangeCount = Paster.write(it, store: store)
            reload()
            notice = "\(t.label)：已保存并进剪贴板"
        } catch { notice = "转换失败：\(error)" }
    }

    func merge(_ ids: [Int64]) {
        do {
            let it = try store.merge(ids)
            reload()
            selection = [it.id]
            notice = "已合并成一条"
        } catch { notice = "合并失败：\(error)" }
    }

    func clearHistory() {
        try? store.clear(keepPinned: true)
        thumbs.removeAllObjects()
        selection = []
        reload()
    }

    // MARK: - 收藏夹

    func createCollection(name: String, color: String, icon: String) -> Collection? {
        let c = try? store.createCollection(name: name, color: color, icon: icon)
        reload()
        return c
    }

    func updateCollection(_ c: Collection) { try? store.updateCollection(c); reload() }

    func deleteCollection(_ id: Int64) {
        try? store.deleteCollection(id)
        if case .collection(let cur) = sidebar, cur == id { sidebar = .all }
        reload()
    }

    func moveCollection(_ id: Int64, by delta: Int) {
        var ids = collections.map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = i + delta
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        try? store.reorderCollections(ids)
        reload()
    }

    func add(_ ids: Set<Int64>, to collection: Int64) { try? store.add(Array(ids), to: collection); reload() }
    func remove(_ id: Int64, from collection: Int64) { try? store.remove(id, from: collection); reload() }

    // MARK: - 导入

    func importDeck() {
        guard !importing else { return }
        importing = true
        importReport = nil
        let store = self.store
        Task.detached { [weak self] in
            let text: String
            do { text = try DeckImporter.run(into: store).description } catch { text = "导入失败：\(error)" }
            await MainActor.run {
                self?.importing = false
                self?.importReport = text
                self?.reload()
            }
        }
    }

    var deckImportedAt: String? { try? store.meta("deck_imported") }

    // MARK: - 图

    func thumbnail(_ item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let hit = thumbs.object(forKey: key) { return hit }
        guard let url = store.blobURL(item), let img = NSImage(contentsOf: url) else { return nil }
        thumbs.setObject(img, forKey: key)
        return img
    }

    func richText(_ item: ClipItem) -> NSAttributedString? {
        guard let url = store.rtfURL(item), let data = try? Data(contentsOf: url) else { return nil }
        return NSAttributedString(rtf: data, documentAttributes: nil)
    }

    func appIcon(bundle: String) -> NSImage {
        if let hit = iconCache[bundle] { return hit }
        let img: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[bundle] = img
        return img
    }

    func exportImage(_ item: ClipItem) {
        guard let url = store.blobURL(item) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (item.title.isEmpty ? "clipbook-\(item.id)" : item.title) + ".png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.removeItem(at: dest)
            do { try FileManager.default.copyItem(at: url, to: dest); notice = "已导出" } catch { notice = "导出失败：\(error)" }
        }
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard let v = UInt64(s, radix: 16) else { self = .gray; return }
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xff) / 255; g = Double((v >> 16) & 0xff) / 255; b = Double((v >> 8) & 0xff) / 255; a = Double(v & 0xff) / 255
        } else {
            r = Double((v >> 16) & 0xff) / 255; g = Double((v >> 8) & 0xff) / 255; b = Double(v & 0xff) / 255; a = 1
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static func fromColorString(_ s: String) -> Color? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("#") { return Color(hex: t) }
        if t.lowercased().hasPrefix("rgb") {
            let nums = t.split(whereSeparator: { !"0123456789.".contains($0) }).compactMap { Double($0) }
            guard nums.count >= 3 else { return nil }
            return Color(.sRGB, red: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255, opacity: nums.count > 3 ? nums[3] : 1)
        }
        return nil
    }
}
