import Foundation
import CryptoKit
import SQLite3

/// SQLite 落盘。单表 + LIKE 检索，图片 PNG 落 blobs/ 目录。
///
/// 为什么不上 FTS5：实测 Deck 一个月 2435 条，一年不到 3 万行，LIKE 全表扫毫秒级；
/// FTS5 的 unicode61 分词把连续中文当一个 token，子串搜不到，反而要再套 trigram —— 复杂度买不到收益。
///
/// 去重：同内容再复制 = 把旧条目顶到最上（created_at 刷新），不产生第二行。
/// 留存：非置顶条目超过 `maxItems` 时按时间淘汰，blob 一起删。
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

    let home: URL
    let blobDir: URL
    var maxItems = 5000
    private var db: OpaquePointer?

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// 默认落 ~/Library/Application Support/Clipbook；CLIPBOOK_HOME 覆盖（自检用临时目录）。
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
        try exec("""
        CREATE TABLE IF NOT EXISTS items(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          text TEXT NOT NULL DEFAULT '',
          blob TEXT,
          hash TEXT NOT NULL UNIQUE,
          app_name TEXT NOT NULL DEFAULT '',
          app_bundle TEXT NOT NULL DEFAULT '',
          created_at REAL NOT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          bytes INTEGER NOT NULL DEFAULT 0,
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0
        )
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_items_order ON items(pinned DESC, created_at DESC)")
    }

    deinit { sqlite3_close(db) }

    // MARK: - 写

    /// 入库。返回落库后的条目（去重命中时是被顶上来的旧条目）。
    @discardableResult
    func ingest(_ c: Capture, at now: Date = Date()) throws -> ClipItem {
        let hash = Self.hash(of: c)
        if let existing = try first("SELECT * FROM items WHERE hash = ?", [hash]) {
            try run("UPDATE items SET created_at = ?, app_name = ?, app_bundle = ? WHERE id = ?",
                    [now.timeIntervalSince1970, c.appName, c.appBundle, existing.id])
            return try item(id: existing.id)!
        }
        var blobName: String?
        var bytes = c.text.utf8.count
        if c.kind == .image, let png = c.imagePNG {
            blobName = "\(hash.prefix(24)).png"
            try png.write(to: blobDir.appendingPathComponent(blobName!), options: .atomic)
            bytes = png.count
        }
        try run("""
        INSERT INTO items(kind, text, blob, hash, app_name, app_bundle, created_at, pinned, bytes, width, height)
        VALUES(?,?,?,?,?,?,?,0,?,?,?)
        """, [c.kind.rawValue, c.text, blobName as Any, hash, c.appName, c.appBundle,
              now.timeIntervalSince1970, bytes, c.width, c.height])
        let id = sqlite3_last_insert_rowid(db)
        try trim()
        return try item(id: id)!
    }

    func setPinned(_ id: Int64, _ pinned: Bool) throws {
        try run("UPDATE items SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id])
    }

    /// 粘贴过 = 顶到最上（Deck/Maccy 同款行为）
    func touch(_ id: Int64, at now: Date = Date()) throws {
        try run("UPDATE items SET created_at = ? WHERE id = ?", [now.timeIntervalSince1970, id])
    }

    func delete(_ id: Int64) throws {
        guard let it = try item(id: id) else { return }
        try run("DELETE FROM items WHERE id = ?", [id])
        removeBlob(it.blob)
    }

    /// 清空（默认保留置顶）
    func clear(keepPinned: Bool = true) throws {
        let victims = try query(keepPinned ? "SELECT * FROM items WHERE pinned = 0" : "SELECT * FROM items", [])
        try run(keepPinned ? "DELETE FROM items WHERE pinned = 0" : "DELETE FROM items", [])
        victims.forEach { removeBlob($0.blob) }
    }

    private func trim() throws {
        let over = try query("""
        SELECT * FROM items WHERE pinned = 0 ORDER BY created_at DESC LIMIT -1 OFFSET ?
        """, [maxItems])
        guard !over.isEmpty else { return }
        for it in over {
            try run("DELETE FROM items WHERE id = ?", [it.id])
            removeBlob(it.blob)
        }
    }

    private func removeBlob(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: blobDir.appendingPathComponent(name))
    }

    // MARK: - 读

    /// 置顶在前，其余按时间倒序。query 非空时按 text / app_name 子串匹配（大小写不敏感限 ASCII）。
    func list(query: String = "", limit: Int = 400) throws -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return try self.query("SELECT * FROM items ORDER BY pinned DESC, created_at DESC LIMIT ?", [limit])
        }
        let pat = "%" + q.replacingOccurrences(of: "\\", with: "\\\\")
                          .replacingOccurrences(of: "%", with: "\\%")
                          .replacingOccurrences(of: "_", with: "\\_") + "%"
        return try self.query("""
        SELECT * FROM items WHERE text LIKE ? ESCAPE '\\' OR app_name LIKE ? ESCAPE '\\'
        ORDER BY pinned DESC, created_at DESC LIMIT ?
        """, [pat, pat, limit])
    }

    func count() throws -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM items", -1, &stmt, nil) == SQLITE_OK else { throw err() }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw err() }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    func item(id: Int64) throws -> ClipItem? {
        try first("SELECT * FROM items WHERE id = ?", [id])
    }

    func blobURL(_ item: ClipItem) -> URL? {
        item.blob.map { blobDir.appendingPathComponent($0) }
    }

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

    private func first(_ sql: String, _ args: [Any]) throws -> ClipItem? {
        try query(sql, args).first
    }

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
            appName: str(5),
            appBundle: str(6),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 7)),
            pinned: sqlite3_column_int64(s, 8) != 0,
            bytes: Int(sqlite3_column_int64(s, 9)),
            width: Int(sqlite3_column_int64(s, 10)),
            height: Int(sqlite3_column_int64(s, 11))
        )
    }
}
