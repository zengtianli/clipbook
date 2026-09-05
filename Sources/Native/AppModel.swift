import AppKit
import SwiftUI
import os

let clipLog = Logger(subsystem: "cyou.tianli.clipbook", category: "model")

/// 面板与菜单共用的状态。所有落盘走 ClipStore；这里只做「查出来给界面」与「按键→动作」。
@MainActor
final class AppModel: ObservableObject {
    static var shared: AppModel!

    let store: ClipStore
    private(set) var watcher: PasteboardWatcher!

    @Published private(set) var items: [ClipItem] = []
    @Published var query = "" { didSet { if query != oldValue { reload(keepSelection: false) } } }
    @Published var selectedID: Int64?
    @Published var paused = false { didSet { watcher.paused = paused; UserDefaults.standard.set(paused, forKey: "paused") } }
    @Published var notice: String?
    @Published var deckRunning = false
    @Published var total = 0

    private let thumbs = NSCache<NSNumber, NSImage>()
    private var iconCache: [String: NSImage] = [:]

    init(home: URL = ClipStore.defaultHome()) throws {
        store = try ClipStore(home: home)
        watcher = PasteboardWatcher { [weak self] cap in self?.ingest(cap) }
        paused = UserDefaults.standard.bool(forKey: "paused")
        watcher.paused = paused
        reload(keepSelection: false)
    }

    func startWatching() { watcher.start() }

    var selected: ClipItem? { items.first { $0.id == selectedID } }

    // MARK: - 数据

    private func ingest(_ cap: Capture) {
        do {
            _ = try store.ingest(cap)
            reload(keepSelection: true)
        } catch {
            notice = "记录失败：\(error)"
        }
    }

    func reload(keepSelection: Bool) {
        do {
            items = try store.list(query: query)
            total = try store.count()
            clipLog.debug("reload query=\(self.query, privacy: .public) items=\(self.items.count) total=\(self.total)")
        } catch {
            notice = "读取失败：\(error)"
            items = []
        }
        if !keepSelection || !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
    }

    /// 面板每次唤出：清搜索、选第一条、看一眼 Deck 在不在跑
    func prepareForShow() {
        query = ""
        reload(keepSelection: false)
        deckRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.yuzeguitar.Deck").isEmpty
        notice = nil
    }

    // MARK: - 动作

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let idx = items.firstIndex { $0.id == selectedID } ?? 0
        let next = min(max(idx + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    /// 返回 true = 已替用户按下 ⌘V；false = 只进了剪贴板（没辅助功能授权）
    @discardableResult
    func paste(_ item: ClipItem) -> Bool {
        watcher.suppressedChangeCount = Paster.write(item, store: store)
        try? store.touch(item.id)
        reload(keepSelection: false)
        return Paster.accessibilityTrusted
    }

    func togglePin(_ item: ClipItem) {
        try? store.setPinned(item.id, !item.pinned)
        reload(keepSelection: true)
    }

    func delete(_ item: ClipItem) {
        let idx = items.firstIndex { $0.id == item.id } ?? 0
        try? store.delete(item.id)
        thumbs.removeObject(forKey: NSNumber(value: item.id))
        reload(keepSelection: false)
        if !items.isEmpty { selectedID = items[min(idx, items.count - 1)].id }
    }

    func clearHistory() {
        try? store.clear(keepPinned: true)
        thumbs.removeAllObjects()
        reload(keepSelection: false)
    }

    // MARK: - 图

    func thumbnail(_ item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        let key = NSNumber(value: item.id)
        if let hit = thumbs.object(forKey: key) { return hit }
        guard let url = store.blobURL(item), let img = NSImage(contentsOf: url) else { return nil }
        thumbs.setObject(img, forKey: key)
        return img
    }

    func appIcon(_ item: ClipItem) -> NSImage {
        if let hit = iconCache[item.appBundle] { return hit }
        let img: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.appBundle) {
            img = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            img = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[item.appBundle] = img
        return img
    }
}
