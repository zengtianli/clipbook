import AppKit
import SQLite3

/// 一次性把 Deck（deckclip）的历史导进来。**只读** Deck 的库：先拷到临时目录再开，不碰原文件。
///
/// Deck 表 ClipboardHistory（2026-09-05 实测 1.4.5）：
///   item_type ∈ text/image/file/richText/url/code；data = 文本字节 / RTF / 路径按行；
///   图片 data 为空，PNG 在 Blobs/<blob_path ?? unique_id>；timestamp = epoch 秒；
///   app_path 可推 bundle id；custom_title 是用户标题；is_encrypted/is_temporary 跳过。
enum DeckImporter {
    struct Report: CustomStringConvertible {
        var scanned = 0, imported = 0, skipped = 0, failed = 0
        var byKind: [ClipItem.Kind: Int] = [:]
        var description: String {
            let kinds = ClipItem.Kind.allCases.compactMap { k in byKind[k].map { "\(k.label) \($0)" } }.joined(separator: " / ")
            return "扫 \(scanned) 条：导入 \(imported)（\(kinds)），跳过 \(skipped)，失败 \(failed)"
        }
    }

    static var defaultDeckHome: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Deck", isDirectory: true)
    }

    static func available(at deckHome: URL = defaultDeckHome) -> Bool {
        FileManager.default.fileExists(atPath: deckHome.appendingPathComponent("Deck.sqlite3").path)
    }

    static func run(into store: ClipStore, deckHome: URL = defaultDeckHome) throws -> Report {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("clipbook-deck-import-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        for name in ["Deck.sqlite3", "Deck.sqlite3-wal", "Deck.sqlite3-shm"] {
            let src = deckHome.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) { try fm.copyItem(at: src, to: tmp.appendingPathComponent(name)) }
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(tmp.appendingPathComponent("Deck.sqlite3").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ClipStore.StoreError.open("Deck 库打不开：\(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = """
        SELECT unique_id, item_type, data, timestamp, app_path, app_name, custom_title, blob_path, search_text
        FROM ClipboardHistory WHERE is_encrypted = 0 AND is_temporary = 0 ORDER BY timestamp ASC, id ASC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ClipStore.StoreError.sql(String(cString: sqlite3_errmsg(db)))
        }
        var report = Report()
        let blobs = deckHome.appendingPathComponent("Blobs", isDirectory: true)
        while sqlite3_step(stmt) == SQLITE_ROW {
            report.scanned += 1
            func str(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            let uniqueID = str(0), itemType = str(1)
            let n = Int(sqlite3_column_bytes(stmt, 2))
            let data = n > 0 ? Data(bytes: sqlite3_column_blob(stmt, 2), count: n) : Data()
            let ts = Date(timeIntervalSince1970: Double(sqlite3_column_int64(stmt, 3)))
            let appPath = str(4), appName = str(5), title = str(6), blobPath = str(7)
            let bundle = Bundle(path: appPath)?.bundleIdentifier ?? ""
            do {
                guard let cap = capture(itemType: itemType, data: data, uniqueID: uniqueID, blobPath: blobPath, blobs: blobs,
                                        appName: appName, appBundle: bundle, title: title) else { report.skipped += 1; continue }
                try store.ingest(cap, at: ts, trim: false)
                report.imported += 1
                report.byKind[cap.kind, default: 0] += 1
            } catch {
                report.failed += 1
            }
        }
        try store.setMeta("deck_imported", ISO8601DateFormatter().string(from: Date()))
        return report
    }

    /// 一行 Deck 记录 → Capture（纯函数，SelfTest 直接喂）
    static func capture(itemType: String, data: Data, uniqueID: String, blobPath: String, blobs: URL,
                        appName: String, appBundle: String, title: String) -> Capture? {
        switch itemType {
        case "text", "url", "code":
            guard let s = String(data: data, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Capture(kind: Classifier.kind(of: s), text: s, appName: appName, appBundle: appBundle, title: title)
        case "richText":
            guard let attr = NSAttributedString(rtf: data, documentAttributes: nil) else {
                guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
                return Capture(kind: Classifier.kind(of: s), text: s, appName: appName, appBundle: appBundle, title: title)
            }
            let plain = attr.string
            guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Capture(kind: .richText, text: plain, rtf: data, appName: appName, appBundle: appBundle, title: title)
        case "file":
            guard let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
            return Capture(kind: .file, text: s, appName: appName, appBundle: appBundle, title: title)
        case "image":
            let name = blobPath.isEmpty ? uniqueID : blobPath.lastPathComponent
            guard let png = try? Data(contentsOf: blobs.appendingPathComponent(name)),
                  let rep = NSBitmapImageRep(data: png) else { return nil }
            let normalized = png.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? png : rep.representation(using: .png, properties: [:])
            guard let normalized else { return nil }
            return Capture(kind: .image, text: "图片 \(rep.pixelsWide)×\(rep.pixelsHigh)", imagePNG: normalized,
                           width: rep.pixelsWide, height: rep.pixelsHigh, appName: appName, appBundle: appBundle, title: title)
        default:
            return nil
        }
    }
}
