import Foundation
import CryptoKit
import SQLite3

/// SQLite 落盘。单表 items + 收藏夹两表，LIKE 检索；图片 PNG / 富文本 RTF 落 blobs/。
///
/// 去重：同内容再复制 = 旧条目顶到最上（created_at 刷新），不产生第二行。
/// 留存：非置顶、不在收藏夹的条目超过 `maxItems` 或超过 `retentionDays` 时淘汰，blob 一起删。
final class ClipStore {
    enum StoreError: Error, CustomStringConvertible {
        case open(String), sql(String)
        var description: String {
            switch self {
            case .open(let m): return "打不开数据库：\(m)"
            case .sql(let m):  return "SQL 失败：\(m)"
            }
        }
    }

    struct Filter: Equatable {
        var text = ""
        var kind: ClipItem.Kind? = nil
        var appBundle: String? = nil
        var collection: Int64? = nil
        var pinnedOnly = false
    }

    struct AppCount: Identifiable, Hashable {
        var id: String { bundle }
        let bundle: String
        let name: String
        let count: Int
    }

    let home: URL
    let blobDir: URL
    var maxItems = 5000
    /// 0 = 不按时长淘汰
    var retentionDays = 0
    private var db: OpaquePointer?

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let columns = "id, kind, text, blob, rtf, hash, app_name, app_bundle, created_at, pinned, bytes, width, height, title, extra"

    static func defaultHome() -> URL {
        if let env = ProcessInfo.processInfo.environment["CLIPBOOK_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Clipbook", isDirectory: true)
    }

    init(home: URL) throws {
        self.home = home
        self.blobDir = home.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)
        let path = home.appendingPathComponent("clipbook.sqlite3").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try migrate()
    }

    deinit { sqlite3_close(db) }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          text TEXT NOT NULL DEFAULT '',
          blob TEXT,
          rtf TEXT,
          hash TEXT NOT NULL UNIQUE,
          app_name TEXT NOT NULL DEFAULT '',
          app_bundle TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          bytes INTEGER NOT NULL DEFAULT 0,
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0,
          title TEXT NOT NULL DEFAULT '',
          extra TEXT NOT NULL DEFAULT ''
        )
        """)
        // v1（2026-09-05 上午的面板版）没有 rtf/title/extra 三列：有旧库就补列
        let cols = try columnNames("items")
        for (c, ddl) in [("rtf", "rtf TEXT"), ("title", "title TEXT NOT NULL DEFAULT ''"), ("extra", "extra TEXT NOT NULL DEFAULT ''")]
        where !cols.contains(c) {
            try exec("ALTER TABLE items ADD COLUMN \(ddl)")
        }
        try exec("CREATE INDEX IF NOT EXISTS idx_items_order ON items(pinned DESC, created_at DESC)")
        try exec("CREATE INDEX IF NOT EXISTS idx_items_kind ON items(kind)")
        try exec("CREATE INDEX IF NOT EXISTS idx_items_app ON items(app_bundle)")
        try exec("""
        CREATE TABLE IF NOT EXISTS collections(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          color TEXT NOT NULL DEFAULT '#2563eb',
          icon TEXT NOT NULL DEFAULT 'folder',
          sort_order INTEGER NOT NULL DEFAULT 0
        )
        """)
        try exec("""
        CREATE TABLE IF NOT EXISTS item_collections(
          item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
          collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
          PRIMARY KEY(item_id, collection_id)
        )
        """)
        try exec("CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    }

    private func columnNames(_ table: String) throws -> [String] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(String(cString: sqlite3_column_text(stmt, 1))) }
        return out
    }

    // MARK: - meta

    func meta(_ key: String) throws -> String? {
        try scalarText("SELECT value FROM meta WHERE key = ?", [key])
    }

    func setMeta(_ key: String, _ value: String) throws {
        try run("INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [key, value])
    }

    // MARK: - 写

    /// 入库。返回落库后的条目（去重命中时是被顶上来的旧条目）。
    @discardableResult
    func ingest(_ c: Capture, at now: Date = Date(), trim: Bool = true) throws -> ClipItem {
        let hash = Self.hash(of: c)
        if let existing = try first("SELECT \(Self.columns) FROM items WHERE hash = ?", [hash]) {
            try run("UPDATE items SET created_at = ?, app_name = ?, app_bundle = ? WHERE id = ?",
                    [max(now.timeIntervalSince1970, existing.createdAt.timeIntervalSince1970), c.appName, c.appBundle, existing.id])
            return try item(id: existing.id)!
        }
        var blobName: String?
        var rtfName: String?
        var bytes = c.text.utf8.count
        if c.kind == .image, let png = c.imagePNG {
            blobName = "\(hash.prefix(24)).png"
            try png.write(to: blobDir.appendingPathComponent(blobName!), options: .atomic)
            bytes = png.count
        }
        if c.kind == .richText, let rtf = c.rtf {
            rtfName = "\(hash.prefix(24)).rtf"
            try rtf.write(to: blobDir.appendingPathComponent(rtfName!), options: .atomic)
        }
        try run("""
        INSERT INTO items(kind, text, blob, rtf, hash, app_name, app_bundle, created_at, pinned, bytes, width, height, title, extra)
        VALUES(?,?,?,?,?,?,?,?,0,?,?,?,?,?)
        """, [c.kind.rawValue, c.text, blobName as Any, rtfName as Any, hash, c.appName, c.appBundle,
              now.timeIntervalSince1970, bytes, c.width, c.height, c.title, c.extra])
        let id = sqlite3_last_insert_rowid(db)
        if trim { try self.trim() }
        return try item(id: id)!
    }

    /// 编辑正文后保存（覆盖原条目）。文本家族按新内容重新识别类型；富文本保存后降为纯文本（RTF 删掉）。
    /// 新内容与另一条重复 → 删掉另一条（库里不留两份一样的）。
    @discardableResult
    func updateText(_ id: Int64, text: String) throws -> ClipItem {
        guard let old = try item(id: id) else { throw StoreError.sql("条目 \(id) 不存在") }
        let newKind: ClipItem.Kind = old.kind.isTextFamily || old.kind == .richText ? Classifier.kind(of: text) : old.kind
        let hash = Self.hash(of: Capture(kind: newKind, text: text, appName: "", appBundle: ""))
        if let dup = try first("SELECT \(Self.columns) FROM items WHERE hash = ? AND id != ?", [hash, id]) {
            try delete(dup.id)
        }
        if old.kind == .richText { removeBlob(old.rtf) }
        try run("UPDATE items SET kind = ?, text = ?, rtf = NULL, hash = ?, bytes = ? WHERE id = ?",
                [newKind.rawValue, text, hash, text.utf8.count, id])
        return try item(id: id)!
    }

    func setTitle(_ id: Int64, _ title: String) throws {
        try run("UPDATE items SET title = ? WHERE id = ?", [title.trimmingCharacters(in: .whitespacesAndNewlines), id])
    }

    func setExtra(_ id: Int64, _ extra: String) throws {
        try run("UPDATE items SET extra = ? WHERE id = ?", [extra, id])
    }

    func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id])
    }

    /// 粘贴过 / 复制过 = 顶到最上
    func touch(_ id: Int64, at now: Date = Date()) throws {
        try run("UPDATE items SET created_at = ? WHERE id = ?", [now.timeIntervalSince1970, id])
    }

    func delete(_ id: Int64) throws {
        guard let it = try item(id: id) else { return }
        try run("DELETE FROM items WHERE id = ?", [id])
        removeBlob(it.blob)
        removeBlob(it.rtf)
    }

    func delete(_ ids: [Int64]) throws {
        try exec("BEGIN")
        do { for id in ids { try delete(id) }; try exec("COMMIT") } catch { try? exec("ROLLBACK"); throw error }
    }

    /// 清空：保留置顶和收藏夹里的
    func clear(keepPinned: Bool = true) throws {
        let sql = keepPinned
            ? "SELECT \(Self.columns) FROM items WHERE pinned = 0 AND id NOT IN (SELECT item_id FROM item_collections)"
            : "SELECT \(Self.columns) FROM items"
        let victims = try query(sql, [])
        try delete(victims.map(\.id))
    }

    /// 多条合并成一条新文本（按传入顺序，空行分隔）
    @discardableResult
    func merge(_ ids: [Int64], appName: String = "Clipbook", appBundle: String = "cyou.tianli.clipbook") throws -> ClipItem {
        let parts = try ids.compactMap { try item(id: $0) }.map(\.text)
        let joined = parts.joined(separator: "\n\n")
        return try ingest(Capture(kind: Classifier.kind(of: joined), text: joined, appName: appName, appBundle: appBundle))
    }

    private func trim() throws {
        let protectedSQL = "pinned = 0 AND id NOT IN (SELECT item_id FROM item_collections)"
        let over = try query("SELECT \(Self.columns) FROM items WHERE \(protectedSQL) ORDER BY created_at DESC LIMIT -1 OFFSET ?", [maxItems])
        var victims = over.map(\.id)
        if retentionDays > 0 {
            let cutoff = Date().timeIntervalSince1970 - Double(retentionDays) * 86400
            let stale = try query("SELECT \(Self.columns) FROM items WHERE \(protectedSQL) AND created_at < ?", [cutoff])
            victims.append(contentsOf: stale.map(\.id))
        }
        guard !victims.isEmpty else { return }
        try delete(Array(Set(victims)))
    }

    private func removeBlob(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: blobDir.appendingPathComponent(name))
    }

    // MARK: - 收藏夹

    func collections() throws -> [Collection] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT id, name, color, icon, sort_order FROM collections ORDER BY sort_order, id", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        var out: [Collection] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Collection(id: sqlite3_column_int64(stmt, 0),
                                  name: String(cString: sqlite3_column_text(stmt, 1)),
                                  color: String(cString: sqlite3_column_text(stmt, 2)),
                                  icon: String(cString: sqlite3_column_text(stmt, 3)),
                                  sortOrder: Int(sqlite3_column_int64(stmt, 4))))
        }
        return out
    }

    @discardableResult
    func createCollection(name: String, color: String = "#2563eb", icon: String = "folder") throws -> Collection {
        let order = try scalarInt("SELECT COALESCE(MAX(sort_order), 0) + 1 FROM collections", [])
        try run("INSERT INTO collections(name, color, icon, sort_order) VALUES(?,?,?,?)", [name, color, icon, order])
        let id = sqlite3_last_insert_rowid(db)
        return Collection(id: id, name: name, color: color, icon: icon, sortOrder: order)
    }

    func updateCollection(_ c: Collection) throws {
        try run("UPDATE collections SET name = ?, color = ?, icon = ?, sort_order = ? WHERE id = ?", [c.name, c.color, c.icon, c.sortOrder, c.id])
    }

    func deleteCollection(_ id: Int64) throws {
        try run("DELETE FROM collections WHERE id = ?", [id])
    }

    func reorderCollections(_ ids: [Int64]) throws {
        for (i, id) in ids.enumerated() { try run("UPDATE collections SET sort_order = ? WHERE id = ?", [i, id]) }
    }

    func add(_ itemIDs: [Int64], to collection: Int64) throws {
        for id in itemIDs { try run("INSERT OR IGNORE INTO item_collections(item_id, collection_id) VALUES(?, ?)", [id, collection]) }
    }

    func remove(_ itemID: Int64, from collection: Int64) throws {
        try run("DELETE FROM item_collections WHERE item_id = ? AND collection_id = ?", [itemID, collection])
    }

    func collectionIDs(of itemID: Int64) throws -> Set<Int64> {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT collection_id FROM item_collections WHERE item_id = ?", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        sqlite3_bind_int64(stmt, 1, itemID)
        var out = Set<Int64>()
        while sqlite3_step(stmt) == SQLITE_ROW { out.insert(sqlite3_column_int64(stmt, 0)) }
        return out
    }

    /// 每条属于哪些收藏夹（一次查全，给网格画色点用）
    func collectionMap(for itemIDs: [Int64]) throws -> [Int64: [Int64]] {
        guard !itemIDs.isEmpty else { return [:] }
        let marks = Array(repeating: "?", count: itemIDs.count).joined(separator: ",")
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT item_id, collection_id FROM item_collections WHERE item_id IN (\(marks))", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        for (i, id) in itemIDs.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), id) }
        var out: [Int64: [Int64]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW { out[sqlite3_column_int64(stmt, 0), default: []].append(sqlite3_column_int64(stmt, 1)) }
        return out
    }

    // MARK: - 读

    private func whereClause(_ f: Filter) -> (String, [Any]) {
        var conds: [String] = []
        var args: [Any] = []
        let q = f.text.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            let pat = "%" + q.replacingOccurrences(of: "\\", with: "\\\\")
                              .replacingOccurrences(of: "%", with: "\\%")
                              .replacingOccurrences(of: "_", with: "\\_") + "%"
            conds.append("(text LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR extra LIKE ? ESCAPE '\\' OR app_name LIKE ? ESCAPE '\\')")
            args += [pat, pat, pat, pat]
        }
        if let k = f.kind { conds.append("kind = ?"); args.append(k.rawValue) }
        if let a = f.appBundle { conds.append("app_bundle = ?"); args.append(a) }
        if let c = f.collection { conds.append("id IN (SELECT item_id FROM item_collections WHERE collection_id = ?)"); args.append(c) }
        if f.pinnedOnly { conds.append("pinned = 1") }
        return (conds.isEmpty ? "" : " WHERE " + conds.joined(separator: " AND "), args)
    }

    /// 置顶在前，其余按时间倒序；分页。
    func list(_ f: Filter = Filter(), page: Int = 0, pageSize: Int = 200) throws -> [ClipItem] {
        let (w, args) = whereClause(f)
        return try query("SELECT \(Self.columns) FROM items\(w) ORDER BY pinned DESC, created_at DESC LIMIT ? OFFSET ?", args + [pageSize, page * pageSize])
    }

    func count(_ f: Filter = Filter()) throws -> Int {
        let (w, args) = whereClause(f)
        return try scalarInt("SELECT COUNT(*) FROM items\(w)", args)
    }

    func kindCounts() throws -> [ClipItem.Kind: Int] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT kind, COUNT(*) FROM items GROUP BY kind", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        var out: [ClipItem.Kind: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let k = ClipItem.Kind(rawValue: String(cString: sqlite3_column_text(stmt, 0))) { out[k] = Int(sqlite3_column_int64(stmt, 1)) }
        }
        return out
    }

    func appCounts() throws -> [AppCount] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT app_bundle, MAX(app_name), COUNT(*) AS n FROM items WHERE app_bundle != '' GROUP BY app_bundle ORDER BY n DESC", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        var out: [AppCount] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(AppCount(bundle: String(cString: sqlite3_column_text(stmt, 0)),
                                name: String(cString: sqlite3_column_text(stmt, 1)),
                                count: Int(sqlite3_column_int64(stmt, 2))))
        }
        return out
    }

    func collectionCounts() throws -> [Int64: Int] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT collection_id, COUNT(*) FROM item_collections GROUP BY collection_id", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        var out: [Int64: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW { out[sqlite3_column_int64(stmt, 0)] = Int(sqlite3_column_int64(stmt, 1)) }
        return out
    }

    func item(id: Int64) throws -> ClipItem? {
        try first("SELECT \(Self.columns) FROM items WHERE id = ?", [id])
    }

    func blobURL(_ item: ClipItem) -> URL? { item.blob.map { blobDir.appendingPathComponent($0) } }
    func rtfURL(_ item: ClipItem) -> URL? { item.rtf.map { blobDir.appendingPathComponent($0) } }

    // MARK: - 内部

    static func hash(of c: Capture) -> String {
        var h = SHA256()
        h.update(data: Data(c.kind.rawValue.utf8))
        h.update(data: Data([0]))
        if let png = c.imagePNG, c.kind == .image {
            h.update(data: png)
        } else {
            h.update(data: Data(c.text.utf8))
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func err() -> StoreError { .sql(String(cString: sqlite3_errmsg(db))) }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw err() }
    }

    private func bind(_ stmt: OpaquePointer?, _ args: [Any]) throws {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch a {
            case let v as Int64:  rc = sqlite3_bind_int64(stmt, idx, v)
            case let v as Int:    rc = sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: rc = sqlite3_bind_double(stmt, idx, v)
            case let v as String: rc = sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case let v as String?: rc = v.map { sqlite3_bind_text(stmt, idx, $0, -1, Self.transient) } ?? sqlite3_bind_null(stmt, idx)
            default:
                if a is NSNull { rc = sqlite3_bind_null(stmt, idx) } else { throw StoreError.sql("不认识的绑定类型 \(type(of: a))") }
            }
            guard rc == SQLITE_OK else { throw err() }
        }
    }

    private func run(_ sql: String, _ args: [Any]) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw err() }
        try bind(stmt, args)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw err() }
    }

    private func scalarInt(_ sql: String, _ args: [Any]) throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw err() }
        try bind(stmt, args)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw err() }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func scalarText(_ sql: String, _ args: [Any]) throws -> String? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw err() }
        try bind(stmt, args)
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE { return nil }
        guard rc == SQLITE_ROW else { throw err() }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) }
    }

    private func first(_ sql: String, _ args: [Any]) throws -> ClipItem? { try query(sql, args).first }

    private func query(_ sql: String, _ args: [Any]) throws -> [ClipItem] {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw err() }
        try bind(stmt, args)
        var out: [ClipItem] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw err() }
            out.append(row(stmt))
        }
        return out
    }

    private func row(_ s: OpaquePointer?) -> ClipItem {
        func str(_ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
        func optStr(_ i: Int32) -> String? { sqlite3_column_type(s, i) == SQLITE_NULL ? nil : str(i) }
        return ClipItem(
            id: sqlite3_column_int64(s, 0),
            kind: ClipItem.Kind(rawValue: str(1)) ?? .text,
            text: str(2),
            blob: optStr(3),
            rtf: optStr(4),
            appName: str(6),
            appBundle: str(7),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 8)),
            pinned: sqlite3_column_int64(s, 9) != 0,
            bytes: Int(sqlite3_column_int64(s, 10)),
            width: Int(sqlite3_column_int64(s, 11)),
            height: Int(sqlite3_column_int64(s, 12)),
            title: str(13),
            extra: str(14)
        )
    }
}
