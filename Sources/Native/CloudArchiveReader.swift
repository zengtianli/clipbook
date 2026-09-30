import CoreData
import Foundation

/// Read-only view of this Mac's copy of the iCloud archive (the Core Data store that the app's
/// optional sync keeps in `CloudLibrary-Production/`). It is what iPhone/iPad Clip lists.
///
/// No rule lives here: the file is opened with `ClipLibrary.openReadOnly(home:)` (plain coordinator,
/// `NSReadOnlyPersistentStoreOption`, no migration, never a sync container) and listed with the phone's own
/// `ClipLibrary.list(in:search:filter:limit:)`, so `clip cloud list` cannot drift from the phone list.
/// Nothing is imported, exported, migrated or written. Freshness is whatever the app last synced.
@MainActor
struct CloudArchiveReader {
    struct Stats {
        var rows = 0, visible = 0, tombstones = 0, favorites = 0
        var kinds: [String: Int] = [:]
    }

    enum ReaderError: Error, CustomStringConvertible {
        case missing(String)
        var description: String { if case .missing(let p) = self { return "本机还没有 iCloud 归档缓存：\(p)" }; return "" }
    }

    /// The phone's filter values (ClipHome): all, favorites, or one archived kind.
    static let filters = ["all", "favorites", "text", "link", "image"]

    let url: URL
    private let context: NSManagedObjectContext

    /// Directory the app uses for the archive cache in this build's CloudKit environment.
    static func home(store: URL, production: Bool) -> URL {
        store.appendingPathComponent(production ? "CloudLibrary-Production" : "CloudLibrary", isDirectory: true)
    }

    init(home: URL) throws {
        url = home.appendingPathComponent("history.sqlite")
        guard FileManager.default.fileExists(atPath: url.path) else { throw ReaderError.missing(url.path) }
        context = try ClipLibrary.openReadOnly(home: home)
    }

    /// Exactly the phone list: same filter values, same search, same order and tombstone rule.
    func list(search: String = "", filter: String = "all", limit: Int = 50) throws -> [PocketClip] {
        try ClipLibrary.list(in: context, search: search, filter: filter, limit: limit)
    }

    /// Visible = everything the phone list shows (the shared rule, unfiltered); rows and tombstones are raw counts.
    func stats() throws -> Stats {
        let visible = try list(limit: .max)
        var s = Stats()
        s.rows = try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "ClipRecord"))
        let removed = NSFetchRequest<NSManagedObject>(entityName: "ClipRecord")
        removed.predicate = NSPredicate(format: "removed == YES")
        s.tombstones = try context.count(for: removed)
        s.visible = visible.count
        s.favorites = visible.filter(\.favorite).count
        for item in visible { s.kinds[item.kind, default: 0] += 1 }
        return s
    }
}
