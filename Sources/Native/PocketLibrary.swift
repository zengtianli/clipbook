import Foundation
import CoreData
import CloudKit
import CryptoKit
import Combine
import ImageIO
import UniformTypeIdentifiers

/// The schema is identical in iOS, the share extension and the Mac bridge.
/// No cross-app imports; consumers vendor this file and verify its SHA256.
struct PocketClip: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
    let kind: String
    let source: String
    let date: Date
    let favorite: Bool
    let objectID: NSManagedObjectID
    var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == "image" { return "图片" }
        return String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(100) ?? "")
    }
    var symbol: String { kind == "image" ? "photo" : kind == "link" ? "link" : "text.alignleft" }
}

@MainActor
final class ClipLibrary: ObservableObject {
    static let containerID = "iCloud.cyou.tianli.clip"
    static let groupID = "group.cyou.tianli.clip"
    static let maxImageBytes = 20 * 1024 * 1024
    static let maxTextBytes = 500_000
    @Published private(set) var ready = false
    @Published private(set) var revision = 0
    @Published private(set) var cloudEnabled = false
    @Published private(set) var syncStatus = "仅保存在本机"
    @Published var error: String?
    private(set) var container: NSPersistentCloudKitContainer?
    let home: URL
    let preferences: UserDefaults
    private var observers: [NSObjectProtocol] = []
    private var loading = false
    private let thumbs = NSCache<NSString, NSData>()

    init(home: URL? = nil, preferences: UserDefaults? = nil) {
        self.preferences = preferences ?? UserDefaults(suiteName: Self.groupID)!
        if let home { self.home = home }
        else {
            let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)
                ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.home = root.appendingPathComponent("ClipLibrary", isDirectory: true)
        }
        thumbs.totalCostLimit = 4 * 1024 * 1024
        thumbs.countLimit = 40
    }

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "ClipRecord"
        entity.managedObjectClassName = "NSManagedObject"
        func attribute(_ name: String, _ type: NSAttributeType, _ value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription(); a.name = name; a.attributeType = type
            a.isOptional = true; a.defaultValue = value
            if type == .binaryDataAttributeType { a.allowsExternalBinaryDataStorage = true }
            return a
        }
        entity.properties = [attribute("key", .stringAttributeType, ""),
            attribute("text", .stringAttributeType, ""), attribute("title", .stringAttributeType, ""),
            attribute("kind", .stringAttributeType, "text"), attribute("source", .stringAttributeType, ""),
            attribute("createdAt", .dateAttributeType), attribute("updatedAt", .dateAttributeType),
            attribute("favorite", .booleanAttributeType, false), attribute("removed", .booleanAttributeType, false),
            attribute("image", .binaryDataAttributeType), attribute("thumbnail", .binaryDataAttributeType)]
        let index = NSFetchIndexDescription(name: "clipKey", elements: [NSFetchIndexElementDescription(property: entity.properties[0], collationType: .binary)])
        entity.indexes = [index]
        model.entities = [entity]
        return model
    }

    func start(localOnly: Bool = false) async {
        guard !loading, !ready else { return }
        let wantsCloud = !localOnly && preferences.bool(forKey: "cloudEnabled")
        await load(cloud: false)
        if wantsCloud { await setCloudEnabled(true) }
    }

    private func load(cloud: Bool) async {
        loading = true; ready = false
        defer { loading = false }
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let c = NSPersistentCloudKitContainer(name: "ClipLibrary", managedObjectModel: Self.makeModel())
            let d = NSPersistentStoreDescription(url: home.appendingPathComponent("history.sqlite"))
            d.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            d.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            d.shouldMigrateStoreAutomatically = true
            d.shouldInferMappingModelAutomatically = true
            if cloud { d.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.containerID) }
            c.persistentStoreDescriptions = [d]
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                c.loadPersistentStores { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            c.viewContext.automaticallyMergesChangesFromParent = true
            c.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            c.viewContext.transactionAuthor = Bundle.main.bundleIdentifier ?? "Clip"
            container = c; cloudEnabled = cloud; ready = true
            syncStatus = cloud ? "iCloud 已开启，等待同步" : "仅保存在本机"
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers = [NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: c.persistentStoreCoordinator, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }, NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: c, queue: .main) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else { return }
                Task { @MainActor in
                    guard let self else { return }
                    if let error = event.error { self.syncStatus = "同步暂未完成：\(error.localizedDescription)" }
                    else if event.endDate != nil && event.succeeded {
                        self.syncStatus = "最近同步 \(Date().formatted(date: .omitted, time: .shortened))"
                        self.refresh()
                    } else { self.syncStatus = "正在同步…" }
                }
            }, NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.validateAccount() }
            }]
            revision += 1
        } catch { self.error = error.localizedDescription; syncStatus = "数据库未打开" }
    }

    func setCloudEnabled(_ enabled: Bool) async {
        guard !loading else { return }
        if enabled {
            do {
                let cloud = CKContainer(identifier: Self.containerID)
                guard try await cloud.accountStatus() == .available else { throw LibraryError.message("请先在系统设置登录 iCloud，并开启 iCloud Drive。") }
                let account = try await cloud.userRecordID().recordName
                if let previous = preferences.string(forKey: "cloudAccount"), previous != account {
                    throw LibraryError.message("iCloud 账户已变化。已保留本地记录并暂停同步，请切回原账户，避免把历史上传到其他账户。")
                }
                preferences.set(account, forKey: "cloudAccount")
            } catch { self.error = error.localizedDescription; return }
        }
        do {
            if let container {
                if container.viewContext.hasChanges { try container.viewContext.save() }
                for store in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(store) }
            }
            container = nil
            preferences.set(enabled, forKey: "cloudEnabled")
            await load(cloud: enabled)
        } catch { self.error = error.localizedDescription }
    }

    private func validateAccount() async {
        guard cloudEnabled else { return }
        do {
            let current = try await CKContainer(identifier: Self.containerID).userRecordID().recordName
            if current == preferences.string(forKey: "cloudAccount") { return }
        } catch { /* Stop rather than exporting local history into a different account. */ }
        await setCloudEnabled(false)
        error = "iCloud 登录状态改变，已暂停同步；本地记录保留。"
    }

    func refresh() {
        container?.viewContext.refreshAllObjects()
        thumbs.removeAllObjects()
        revision += 1
    }
    func releaseCaches() { thumbs.removeAllObjects(); container?.viewContext.refreshAllObjects() }

    private var context: NSManagedObjectContext {
        get throws { guard let context = container?.viewContext, ready else { throw LibraryError.message("历史库尚未就绪，请稍后重试。") }; return context }
    }
    private func objects(key: String) throws -> [NSManagedObject] {
        let r = NSFetchRequest<NSManagedObject>(entityName: "ClipRecord")
        r.predicate = NSPredicate(format: "key == %@", key)
        r.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        return try context.fetch(r)
    }
    static func key(text: String, image: Data?) -> String {
        var data = Data((image == nil ? "text:" : "image:").utf8)
        data.append(image ?? Data(text.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    @discardableResult
    func save(text: String, image: Data? = nil, title: String = "", source: String = "Clip", at: Date = Date(), revive: Bool = true) throws -> String {
        guard image != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.message("请先输入或粘贴内容。") }
        guard text.utf8.count <= Self.maxTextBytes else { throw LibraryError.message("单条文本最多 500 KB。") }
        if let image, image.count > Self.maxImageBytes { throw LibraryError.message("单张图片最多 20 MB。") }
        let id = Self.key(text: text, image: image)
        let existing = try objects(key: id)
        if !revive, !existing.isEmpty { return id }
        let thumbnail = image.flatMap { Self.thumbnail($0) }
        if image != nil && thumbnail == nil { throw LibraryError.message("无法读取这张图片。") }
        let ctx = try context
        let obj = existing.first ?? NSEntityDescription.insertNewObject(forEntityName: "ClipRecord", into: ctx)
        if let image {
            obj.setValue(image, forKey: "image"); obj.setValue(thumbnail, forKey: "thumbnail")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let link = !trimmed.contains(where: \.isWhitespace) && (trimmed.hasPrefix("https://") || trimmed.hasPrefix("http://"))
        obj.setValue(id, forKey: "key"); obj.setValue(text, forKey: "text")
        if !title.isEmpty || existing.isEmpty { obj.setValue(title, forKey: "title") }
        obj.setValue(image != nil ? "image" : link ? "link" : "text", forKey: "kind")
        obj.setValue(source, forKey: "source"); obj.setValue(at, forKey: "createdAt")
        obj.setValue(Date(), forKey: "updatedAt"); obj.setValue(false, forKey: "removed")
        for duplicate in existing.dropFirst() { try context.delete(duplicate) }
        try context.save(); revision += 1
        return id
    }

    func list(search: String = "", filter: String = "all", limit: Int = 100) throws -> [PocketClip] {
        let r = NSFetchRequest<NSManagedObject>(entityName: "ClipRecord")
        // Read tombstones too: a newer deletion must mask an older duplicate from an offline device.
        var conditions: [NSPredicate] = [NSPredicate(format: "removed == NO")]
        if filter == "favorites" { conditions.append(NSPredicate(format: "favorite == YES")) }
        else if filter != "all" { conditions.append(NSPredicate(format: "kind == %@", filter)) }
        if !search.isEmpty { conditions.append(NSPredicate(format: "text CONTAINS[cd] %@ OR title CONTAINS[cd] %@", search, search)) }
        r.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conditions)
        r.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false), NSSortDescriptor(key: "updatedAt", ascending: false)]
        r.fetchBatchSize = 50
        r.fetchLimit = 100
        var seen = Set<String>(); var result: [PocketClip] = []
        while result.count < limit {
            let rows = try context.fetch(r)
            if rows.isEmpty { break }
            let candidates = rows.compactMap { $0.value(forKey: "key") as? String }
            let duplicates = NSFetchRequest<NSManagedObject>(entityName: "ClipRecord")
            duplicates.predicate = NSPredicate(format: "key IN %@", candidates)
            duplicates.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
            var newest: [String: NSManagedObject] = [:]
            for row in try context.fetch(duplicates) {
                let key = row.value(forKey: "key") as? String ?? ""
                if newest[key] == nil { newest[key] = row }
            }
            for key in candidates {
                guard seen.insert(key).inserted, let latest = newest[key],
                      !(latest.value(forKey: "removed") as? Bool ?? false) else { continue }
                let item = Self.item(latest)
                guard filter == "all" || (filter == "favorites" ? item.favorite : item.kind == filter) else { continue }
                result.append(item)
                if result.count >= limit { break }
            }
            r.fetchOffset += rows.count
            if rows.count < r.fetchLimit { break }
        }
        return result
    }
    private static func item(_ o: NSManagedObject) -> PocketClip {
        PocketClip(id: o.value(forKey: "key") as? String ?? "", title: o.value(forKey: "title") as? String ?? "",
            text: o.value(forKey: "text") as? String ?? "", kind: o.value(forKey: "kind") as? String ?? "text",
            source: o.value(forKey: "source") as? String ?? "", date: o.value(forKey: "createdAt") as? Date ?? .distantPast,
            favorite: o.value(forKey: "favorite") as? Bool ?? false, objectID: o.objectID)
    }
    func mutate(_ id: String, favorite: Bool? = nil, remove: Bool = false, title: String? = nil) throws {
        for obj in try objects(key: id) {
            if let favorite { obj.setValue(favorite, forKey: "favorite") }
            if let title { obj.setValue(title, forKey: "title") }
            if remove {
                obj.setValue(true, forKey: "removed")
                obj.setValue(nil, forKey: "image"); obj.setValue(nil, forKey: "thumbnail")
                obj.setValue("", forKey: "text"); obj.setValue("", forKey: "title")
                obj.setValue("", forKey: "source"); obj.setValue(false, forKey: "favorite")
            }
            obj.setValue(Date(), forKey: "updatedAt")
        }
        try context.save()
        if remove { thumbs.removeObject(forKey: id as NSString) }
        revision += 1
    }
    func imageData(_ item: PocketClip, thumbnail: Bool = false) throws -> Data? {
        let key = item.id as NSString
        if thumbnail, let data = thumbs.object(forKey: key) { return data as Data }
        let data = try context.existingObject(with: item.objectID).value(forKey: thumbnail ? "thumbnail" : "image") as? Data
        if thumbnail, let data { thumbs.setObject(data as NSData, forKey: key, cost: data.count) }
        return data
    }
    static func thumbnail(_ data: Data, pixels: Int = 320) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    enum LibraryError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
    }
}
