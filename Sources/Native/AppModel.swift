import AppKit
import SwiftUI
import os
import Combine
import ImageIO

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
    let settings: AppSettings
    lazy var cloud = MacClipSync(model: self)
    private var settingsSubscriptions: Set<AnyCancellable> = []
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
    @Published var keyboardID: Int64?
    var gridColumns = 3
    private(set) var interfaceActive = true
    struct Draft { var id: Int64; var text: String; var title: String; var rich: Bool }
    var savedDraft: Draft?
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
    /// 最近一个在前台的**别的** app —— 用 workspace 通知持续跟踪，不依赖打开窗口那一刻的前台是谁
    /// （用户若先用 AppleScript 激活本 app 再开窗口，那一刻前台已是本 app，会丢）。
    private(set) var previousApp: NSRunningApplication?
    private var promptedAccessibility: Bool {
        get { UserDefaults.standard.bool(forKey: "promptedAccessibility") }
        set { UserDefaults.standard.set(newValue, forKey: "promptedAccessibility") }
    }

    private let thumbs = NSCache<NSString, NSImage>()
    private var iconCache: [String: NSImage] = [:]

    init(home: URL = ClipStore.defaultHome(), settings suppliedSettings: AppSettings? = nil) throws {
        let settings = suppliedSettings ?? AppSettings.shared
        self.settings = settings
        thumbs.totalCostLimit = 12 * 1024 * 1024
        thumbs.countLimit = 48
        store = try ClipStore(home: home)
        watcher = PasteboardWatcher(pasteboard: ProductIdentity.pasteboard, onCopy: { [weak self] count in
            guard let self else { return }
            CopyFeedback.completed(success: true, enabled: self.settings.copySound, changeCount: count)
        }) { [weak self] cap in self?.ingest(cap) }
        applySettings()
        Publishers.CombineLatest4(settings.$paused, settings.$ignoredBundles, settings.$plainTextOnly, settings.$maxItems)
            .sink { [weak self] paused, ignored, plain, maximum in
                self?.watcher.paused = paused
                self?.watcher.ignoredBundles = Set(ignored)
                self?.watcher.plainTextOnly = plain
                self?.store.maxItems = min(100000, max(100, maximum))
            }.store(in: &settingsSubscriptions)
        settings.$retentionDays.sink { [weak self] days in self?.store.retentionDays = max(0, days) }
            .store(in: &settingsSubscriptions)
        reload()
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.previousApp = app }
        }
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
            if ProductIdentity.cloudSupported && AppPreferences.defaults.bool(forKey: "cloudEnabled") { cloud.captured(it) }
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
        guard interfaceActive else { return }
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
        keyboardID = id
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

    /// Only called by the grid's native responder, never by text editors or the sidebar.
    @discardableResult
    func navigate(code: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard modifiers.intersection([.command, .control, .option]).isEmpty else { return false }
        guard [123, 124, 125, 126, 115, 119, 116, 121, 36, 76, 53].contains(code) else { return false }
        if code == 53 { selection = []; keyboardID = nil; return true }
        if code == 36 || code == 76 { copySelection(); return true }
        guard !items.isEmpty else { return true }
        let current = items.firstIndex { $0.id == keyboardID } ?? items.firstIndex { selection.contains($0.id) }
        let cols = max(1, gridColumns)
        let delta: Int
        switch code {
        case 123: delta = -1
        case 124: delta = 1
        case 125: delta = cols
        case 126: delta = -cols
        case 116: delta = -cols * 3
        case 121: delta = cols * 3
        default: delta = 0
        }
        let index = code == 115 ? 0 : code == 119 ? items.count - 1 : min(items.count - 1, max(0, (current ?? -delta) + delta))
        if modifiers.contains(.shift), anchorID == nil { anchorID = current.map { items[$0].id } ?? items[index].id }
        click(items[index].id, modifiers: modifiers.contains(.shift) ? [.shift] : [])
        return true
    }

    func suspendInterface() {
        interfaceActive = false
        // Keep selected records for explicitly configured global copy, and keep draft state.
        items = selectedItems
        thumbs.removeAllObjects()
        iconCache.removeAll()
    }

    func resumeInterface() { interfaceActive = true; reload() }

    // MARK: - 动作

    var selectedItems: [ClipItem] { items.filter { selection.contains($0.id) } }

    func copySelection(pasteboard: NSPasteboard = ProductIdentity.pasteboard) {
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        let change = Paster.write(selected, store: store, pasteboard: pasteboard)
        guard change >= 0 else { notice = "复制失败：无法写入剪贴板或原文件不可读"; return }
        if pasteboard === NSPasteboard.general { watcher.suppressedChangeCount = change }
        CopyFeedback.completed(success: pasteboard === NSPasteboard.general, enabled: settings.copySound, changeCount: change)
        notice = "已复制 \(selected.count) 条记录"
    }

    @discardableResult
    func copy(_ item: ClipItem) -> Bool {
        let pasteboard = ProductIdentity.pasteboard
        let change = Paster.write(item, store: store, pasteboard: pasteboard)
        guard change >= 0 else { notice = "复制失败：无法写入剪贴板或原文件不可读"; return false }
        watcher.suppressedChangeCount = change
        CopyFeedback.completed(success: pasteboard === NSPasteboard.general, enabled: settings.copySound, changeCount: change)
        try? store.touch(item.id)
        reload()
        notice = "已复制到剪贴板"
        return true
    }

    /// 粘贴到打开窗口前的那个 app。返回 false = 只复制了（没辅助功能授权）
    @discardableResult
    func paste(_ item: ClipItem, hideWindow: () -> Void) -> Bool {
        guard copy(item) else { return false }
        if ProductIdentity.backgroundPreview {
            notice = "隔离演示：仅写入演示剪贴板"
            return false
        }
        hideWindow()
        if let app = previousApp {
            // macOS 14+ 协作式激活：必须用 activate(from:)「把激活权交出去」，裸 activate() 拉不动别的 app（2026-09-05 实测）
            NSApp.yieldActivation(to: app)
            app.activate(from: .current, options: [])
        }
        guard Paster.accessibilityTrusted else {
            // 没授权：内容已在剪贴板、原 app 已拉回前台，用户按一下 ⌘V 即可；系统授权提示一辈子只弹一次，之后去设置里点
            if !promptedAccessibility { promptedAccessibility = true; Paster.promptAccessibility() }
            notice = "已复制并切回 \(previousApp?.localizedName ?? "原 app")；授权「辅助功能」后才会自动粘贴"
            return false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { _ = Paster.sendCommandV() }
        return true
    }

    func delete(_ ids: Set<Int64>) {
        do { try store.delete(Array(ids)) } catch { notice = "删除失败：\(error)" }
        thumbs.removeAllObjects()
        selection = []
        reload()
    }

    func togglePin(_ item: ClipItem) {
        mutate { try store.setPinned(item.id, !item.pinned) }
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
        mutate { try store.setTitle(item.id, title) }
    }

    func apply(_ t: Transform, to item: ClipItem) {
        let out = t.apply(item.text)
        do {
            let it = try store.updateText(item.id, text: out)
            let change = Paster.write(it, store: store)
            guard change >= 0 else { reload(); notice = "已保存，但复制失败"; return }
            watcher.suppressedChangeCount = change
            CopyFeedback.completed(success: true, enabled: settings.copySound, changeCount: change)
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
        mutate {
            try store.clear(keepPinned: true)
            thumbs.removeAllObjects(); selection = []
        }
    }

    // MARK: - 收藏夹

    func createCollection(name: String, color: String, icon: String) -> Collection? {
        do { let c = try store.createCollection(name: name, color: color, icon: icon); reload(); return c }
        catch { notice = "创建收藏夹失败：\(error)"; return nil }
    }

    func updateCollection(_ c: Collection) { mutate { try store.updateCollection(c) } }

    func deleteCollection(_ id: Int64) {
        mutate {
            try store.deleteCollection(id)
            if case .collection(let cur) = sidebar, cur == id { sidebar = .all }
        }
    }

    func moveCollection(_ id: Int64, by delta: Int) {
        var ids = collections.map(\.id)
        guard let i = ids.firstIndex(of: id) else { return }
        let j = i + delta
        guard ids.indices.contains(j) else { return }
        ids.swapAt(i, j)
        mutate { try store.reorderCollections(ids) }
    }

    func add(_ ids: Set<Int64>, to collection: Int64) { mutate { try store.add(Array(ids), to: collection) } }
    func remove(_ id: Int64, from collection: Int64) { mutate { try store.remove(id, from: collection) } }

    private func mutate(_ operation: () throws -> Void) {
        do { try operation(); reload() }
        catch { notice = "操作失败：\(error)" }
    }

    // MARK: - 导入

    func importDeck() {
        guard !importing else { return }
        importing = true
        importReport = nil
        let store = self.store
        Task { [weak self] in
            let text = await Task.detached {
                do { return try DeckImporter.run(into: store).description } catch { return "导入失败：\(error)" }
            }.value
                self?.importing = false
                self?.importReport = text
                self?.reload()
        }
    }

    var deckImportedAt: String? { try? store.meta("deck_imported") }

    // MARK: - 图

    func thumbnail(_ item: ClipItem, maxPixels: Int = 512) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = "\(item.id)-\(maxPixels)" as NSString
        if let hit = thumbs.object(forKey: key) { return hit }
        guard let url = store.blobURL(item), let img = Self.downsample(url, maxPixels: maxPixels) else { return nil }
        thumbs.setObject(img, forKey: key, cost: Int(img.size.width * img.size.height) * 4)
        return img
    }

    static func downsample(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
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
