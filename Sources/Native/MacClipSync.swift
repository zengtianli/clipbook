import AppKit
import SwiftUI
import Combine
import ImageIO

/// Optional cloud archive. The existing fast SQLite clipboard stays the primary local store.
/// Local retention/deletion never deletes a user's cross-device archive.
@MainActor
final class MacClipSync: ObservableObject {
    private unowned let model: AppModel
    let library: ClipLibrary
    @Published var busy = false
    @Published var status = "尚未启用"
    private var subscription: AnyCancellable?
    private var importing = false
    private let markerScope: String
    /// This build's CloudKit environment (Info.plist ClipCloudEnvironment). Development and Production have
    /// independent CloudKit metadata and account identities: separate archive caches, markers and account keys.
    /// Keep the original archive intact; seed the production archive from the main history.
    nonisolated static var production: Bool { Bundle.main.object(forInfoDictionaryKey: "ClipCloudEnvironment") as? String == "Production" }
    nonisolated static var markerScope: String { production ? "v2.Production" : "v1" }
    nonisolated static var accountKey: String { production ? "cloudAccount.Production" : "cloudAccount" }
    nonisolated static func archiveHome(store home: URL) -> URL {
        home.appendingPathComponent(production ? "CloudLibrary-Production" : "CloudLibrary", isDirectory: true)
    }
    /// 「补充最近历史」 covers this many of the newest records (the grid order).
    static let recentLimit = 500

    init(model: AppModel) {
        self.model = model
        markerScope = Self.markerScope
        library = ClipLibrary(home: Self.archiveHome(store: model.store.home), preferences: AppPreferences.defaults,
                              cloudAccountKey: Self.accountKey)
    }

    /// Per-record archive marker. A capture is exported once; edits with a new content hash form a new archive item.
    static func archiveMarker(_ item: ClipItem, scope: String) -> (key: String, digest: String) {
        let fingerprint = "\(item.kind.rawValue):\(item.text):\(item.blob ?? "")"
        return ("cloudArchive.\(scope).\(item.id)", ClipLibrary.key(text: fingerprint, image: nil))
    }
    /// Whether archiving would upload this record: not a file, within the archive's size caps, not archived as is.
    static func needsArchive(_ item: ClipItem, store: ClipStore, scope: String) throws -> Bool {
        guard item.kind != .file, item.text.utf8.count <= ClipLibrary.maxTextBytes, item.bytes <= ClipLibrary.maxImageBytes else { return false }
        let marker = archiveMarker(item, scope: scope)
        return try store.meta(marker.key) != marker.digest
    }
    func start() {
        Task {
            await library.start()
            observeChanges()
            if library.cloudEnabled {
                NSApplication.shared.registerForRemoteNotifications()
                // Also catch up copies made while the archive was opening or on a previous failed start.
                await sendRecent()
            }
            receive()
        }
    }
    private func observeChanges() {
        guard subscription == nil else { return }
        subscription = library.$revision.dropFirst().debounce(for: .milliseconds(600), scheduler: RunLoop.main).sink { [weak self] _ in
            Task { @MainActor in self?.receive() }
        }
    }
    func enable(_ value: Bool) async {
        if !library.ready { await library.start(localOnly: true) }
        await library.setCloudEnabled(value)
        if value && library.cloudEnabled {
            NSApplication.shared.registerForRemoteNotifications()
            observeChanges()
            await sendRecent()
        }
    }
    func captured(_ item: ClipItem) {
        guard library.ready, library.cloudEnabled, !importing else { return }
        do { try send(item) } catch { status = error.localizedDescription }
    }
    private func send(_ item: ClipItem) throws {
        defer { library.releaseCaches() }
        guard try Self.needsArchive(item, store: model.store, scope: markerScope) else { return }
        let marker = Self.archiveMarker(item, scope: markerScope)
        let image = try model.store.blobURL(item).map { try Data(contentsOf: $0) }
        let key = try library.save(text: item.text, image: image, title: item.title, source: item.appName.isEmpty ? "Mac Clip" : item.appName,
            at: item.createdAt, revive: false)
        if item.pinned { try library.mutate(key, favorite: true) }
        try model.store.setMeta(marker.key, marker.digest)
        try model.store.setMeta("cloudReceived.\(markerScope).\(key)", String(item.id))
    }
    func sendRecent() async {
        guard library.ready, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let items = try model.store.list(pageSize: Self.recentLimit)
            for (index, item) in items.enumerated() {
                try send(item)
                if index.isMultiple(of: 20) { await Task.yield() }
            }
            status = "已整理最近 \(items.count) 条，iCloud 将增量同步"
        } catch { status = "整理未完成：\(error.localizedDescription)" }
    }
    /// `clip cloud push`: the 「补充最近历史」 button, only when the button would be enabled.
    func pushRequested() async {
        guard library.cloudEnabled else { return }
        await sendRecent()
    }
    /// Another process (`clip add`, `clip edit`, Deck import) changed the store while iCloud is on: archive the newest
    /// records the way a capture is archived. Idempotent through the per-record marker; never deletes from the archive.
    func storeChangedExternally() {
        guard library.ready, library.cloudEnabled, !importing, !busy else { return }
        do { for item in try model.store.list(pageSize: 50) { try send(item) } }
        catch { status = error.localizedDescription }
    }
    /// `clip cloud favorite|unfavorite|delete`: what the phone's 收藏 / 取消收藏 / 删除 do, through the same
    /// `ClipLibrary.mutate`. Only a record the phone's list shows can be changed. It changes the synced history alone:
    /// this Mac's own library keeps its copy and its pin, as it does when the phone makes the change.
    static func apply(_ change: ClipCloudChange, to library: ClipLibrary) -> ClipCloudChange.Answer {
        guard library.ready else { return .init(ok: false, code: "store", message: library.error ?? "同步历史没有打开") }
        do {
            guard try library.list(limit: .max).contains(where: { $0.id == change.key }) else {
                return .init(ok: false, code: "not_found", message: "同步历史里已经没有这条记录（可能刚在别的设备上删除）")
            }
            switch change.action {
            case .favorite: try library.mutate(change.key, favorite: true)
            case .unfavorite: try library.mutate(change.key, favorite: false)
            case .delete: try library.mutate(change.key, remove: true)
            }
            return .init(ok: true)
        } catch { return .init(ok: false, code: "store", message: error.localizedDescription) }
    }
    /// The changes `clip` left in the data dir, each answered. An archive that is not open yet is opened the way the
    /// app opens it at launch: on this Mac, and with iCloud only if 「iCloud 历史归档」 is on. Nothing else is started
    /// here: with the archive off this does not begin importing its records into this Mac's library.
    func changesRequested() async {
        let home = model.store.home
        let changes = ClipCloudChange.pending(home: home)
        guard !changes.isEmpty else { return }
        if !library.ready { await library.start() }
        var polls = 0   // a start already under way returns at once: give it a moment to finish loading
        while !library.ready && polls < 100 { try? await Task.sleep(nanoseconds: 50_000_000); polls += 1 }
        for change in changes { change.answer(Self.apply(change, to: library), home: home) }
    }
    private func receive() {
        guard library.ready, !importing else { return }
        importing = true; defer { importing = false }
        do {
            for item in try library.list(limit: 500) {
                let marker = "cloudReceived.\(markerScope).\(item.id)"
                if try model.store.meta(marker) != nil { continue }
                let image = item.kind == "image" ? try library.imageData(item) : nil
                var width = 0, height = 0
                if let image, let source = CGImageSourceCreateWithData(image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                    width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                    height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                }
                let capture = Capture(kind: image == nil ? Classifier.kind(of: item.text) : .image,
                    text: image == nil ? item.text : "图片 \(width)×\(height)", imagePNG: image, width: width, height: height,
                    appName: "Clip iCloud", appBundle: "cyou.tianli.clipmobile", title: item.title)
                let imported = try model.store.ingest(capture, at: item.date)
                if item.favorite { try model.store.setPinned(imported.id, true) }
                try model.store.setMeta(marker, String(imported.id))
            }
            model.reload()
        } catch { status = "接收未完成：\(error.localizedDescription)" }
    }
}

struct ClipCloudSettings: View {
    @ObservedObject var sync: MacClipSync
    @ObservedObject var library: ClipLibrary
    init(sync: MacClipSync) { self.sync = sync; self.library = sync.library }
    var body: some View {
        Form {
            Section("iPhone / iPad") {
                Toggle("iCloud 历史归档", isOn: Binding(get: { library.cloudEnabled }, set: { enabled in Task { await sync.enable(enabled) } }))
                    .accessibilityIdentifier("clipCloudSync")
                Text(library.syncStatus).foregroundStyle(.secondary)
                Text("首次开启整理最近 500 条，随后记录的新内容自动加入。文本、链接、图片可在 iOS Clip 取用；文件路径不上传，富文本按纯文本归档。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("这是独立同步历史：Mac 本地的清理、删除与保留天数不会删除云端归档。iOS 删除只作用于同步历史。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(sync.busy ? "正在整理…" : "补充最近历史") { Task { await sync.sendRecent() } }
                    .disabled(!library.cloudEnabled || sync.busy)
                Text(sync.status).font(.caption)
                if let error = library.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }.padding()
    }
}
