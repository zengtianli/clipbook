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
    init(model: AppModel) {
        self.model = model
        library = ClipLibrary(home: model.store.home.appendingPathComponent("CloudLibrary"), preferences: AppPreferences.defaults)
    }
    func start() {
        Task {
            await library.start()
            if library.cloudEnabled { NSApplication.shared.registerForRemoteNotifications() }
            subscription = library.$revision.dropFirst().debounce(for: .milliseconds(600), scheduler: RunLoop.main).sink { [weak self] _ in
                Task { @MainActor in self?.receive() }
            }
            receive()
        }
    }
    func enable(_ value: Bool) async {
        if !library.ready { await library.start(localOnly: true) }
        await library.setCloudEnabled(value)
        if value && library.cloudEnabled {
            NSApplication.shared.registerForRemoteNotifications()
            if subscription == nil { start() }
            await sendRecent()
        }
    }
    func captured(_ item: ClipItem) {
        guard library.ready, library.cloudEnabled, !importing else { return }
        do { try send(item) } catch { status = error.localizedDescription }
    }
    private func send(_ item: ClipItem) throws {
        defer { library.releaseCaches() }
        guard item.kind != .file else { return }
        guard item.text.utf8.count <= ClipLibrary.maxTextBytes, item.bytes <= ClipLibrary.maxImageBytes else { return }
        let marker = "cloudArchive.v1.\(item.id)"
        // A capture is exported once. Edits with a new content hash form a new archive item.
        let fingerprint = "\(item.kind.rawValue):\(item.text):\(item.blob ?? "")"
        let digest = ClipLibrary.key(text: fingerprint, image: nil)
        if try model.store.meta(marker) == digest { return }
        let image = try model.store.blobURL(item).map { try Data(contentsOf: $0) }
        let key = try library.save(text: item.text, image: image, title: item.title, source: item.appName.isEmpty ? "Mac Clip" : item.appName,
            at: item.createdAt, revive: false)
        if item.pinned { try library.mutate(key, favorite: true) }
        try model.store.setMeta(marker, digest)
        try model.store.setMeta("cloudReceived.v1.\(key)", String(item.id))
    }
    func sendRecent() async {
        guard library.ready, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let items = try model.store.list(pageSize: 500)
            for (index, item) in items.enumerated() {
                try send(item)
                if index.isMultiple(of: 20) { await Task.yield() }
            }
            status = "已整理最近 \(items.count) 条，iCloud 将增量同步"
        } catch { status = "整理未完成：\(error.localizedDescription)" }
    }
    private func receive() {
        guard library.ready, !importing else { return }
        importing = true; defer { importing = false }
        do {
            for item in try library.list(limit: 500) {
                let marker = "cloudReceived.v1.\(item.id)"
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
