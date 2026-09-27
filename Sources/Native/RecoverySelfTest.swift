import AppKit
import Darwin
import SQLite3

/// `Clipbook --recovery-test`: failure injection against the production store, blob,
/// import and link-title paths inside the isolated CLIPBOOK_HOME.
@MainActor
enum RecoverySelfTest {
    /// A loopback port that was bound and then closed, so connecting is refused.
    static func closedLoopbackPort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        return ok ? UInt16(bigEndian: addr.sin_port) : nil
    }

    static func blobFiles(_ store: ClipStore) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: store.blobDir.path)) ?? [])
    }

    static func run() -> Int32 {
        let report = AcceptanceReport()
        guard let isolated = AcceptanceReport.isolatedRoot("--recovery-test") else { return 2 }
        let fm = FileManager.default
        let root = isolated.appendingPathComponent("recovery-\(UUID().uuidString)", isDirectory: true)
        let board = NSPasteboard(name: .init("cyou.tianli.clipbook.recovery.\(UUID().uuidString)"))
        defer { board.releaseGlobally(); try? fm.removeItem(at: root) }
        func home(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }
        func cap(_ text: String) -> Capture { Capture(kind: Classifier.kind(of: text), text: text, appName: "T", appBundle: "t") }
        report.notCovered = [
            "启动失败弹窗（AppDelegate.init 捕获错误后 NSAlert.runModal + exit(2)，模态 UI 不驱动；已断言同一 AppModel(home:) 抛出可读错误）",
            "磁盘已满 / 只读卷写入失败",
            "多进程同时写同一库（生产为单实例）",
            "写 blob 成功但 INSERT 失败时遗留的孤儿文件（生产无清理保证）",
            "进程被真实 SIGKILL（以复制未 checkpoint 的 db+wal 快照代替）",
        ]
        AppSettings.shared.copySound = false; AppSettings.shared.fetchLinkTitles = false
        do {
            // 1. Close and reopen: rows, pin, collection and blob persist.
            let h1 = home("reopen")
            var ids: [Int64] = []
            var blobName: String?
            do {
                let s = try ClipStore(home: h1)
                ids.append(try s.ingest(cap("持久化文本")).id)
                let img = try s.ingest(Capture(kind: .image, text: "图片 20×10", imagePNG: AcceptanceReport.png(20, 10, .systemBlue),
                                               width: 20, height: 10, appName: "T", appBundle: "t"))
                ids.append(img.id); blobName = img.blob
                try s.setPinned(ids[0], true)
                let c = try s.createCollection(name: "保留")
                try s.add([img.id], to: c.id)
            }
            let r1 = try ClipStore(home: h1)
            let reopened = try r1.list()
            report.check(try reopened.count == 2 && reopened.first?.id == ids[0] && reopened.first?.pinned == true
                         && (try r1.collections().first.map { try r1.count(.init(collection: $0.id)) }) == 1
                         && blobName.map { fm.fileExists(atPath: r1.blobDir.appendingPathComponent($0).path) } == true,
                         "reopen_preserves_rows_pin_collection_blob")

            // 2. WAL not checkpointed: a second connection reads it, and a copied db+wal snapshot recovers.
            let h2 = home("wal")
            let writer = try ClipStore(home: h2)
            for i in 0..<5 { _ = try writer.ingest(cap("WAL 条目 \(i)")) }
            let wal = h2.appendingPathComponent("clipbook.sqlite3-wal")
            let walSize = (try? fm.attributesOfItem(atPath: wal.path)[.size] as? Int) ?? 0
            let reader = try ClipStore(home: h2)
            report.check(try walSize > 0 && (try reader.count()) == 5, "wal_uncheckpointed_second_connection_reads", "wal \(walSize) B")
            let crash = home("wal-crash-copy")
            try fm.createDirectory(at: crash, withIntermediateDirectories: true)
            for name in ["clipbook.sqlite3", "clipbook.sqlite3-wal"] {
                try fm.copyItem(at: h2.appendingPathComponent(name), to: crash.appendingPathComponent(name))
            }
            let recovered = try ClipStore(home: crash)
            report.check(try (try recovered.count()) == 5 && (try recovered.list()).map(\.text).contains("WAL 条目 4"),
                         "wal_snapshot_recovers_after_simulated_crash")

            // 3. Blob removed behind the app's back.
            let h3 = home("missing-blob")
            let model = try AppModel(home: h3)
            model.watcher.stop()
            let img = try model.store.ingest(Capture(kind: .image, text: "图片 30×30", imagePNG: AcceptanceReport.png(30, 30, .systemRed),
                                                     width: 30, height: 30, appName: "T", appBundle: "t"))
            let rich = try model.store.ingest(Capture(kind: .richText, text: "富文本丢了 RTF", rtf: AcceptanceReport.rtf("富文本丢了 RTF"), appName: "T", appBundle: "t"))
            try fm.removeItem(at: model.store.blobURL(img)!)
            try fm.removeItem(at: model.store.rtfURL(rich)!)
            model.reload()
            report.check(model.items.contains { $0.id == img.id } && model.thumbnail(img) == nil
                         && AppModel.downsample(model.store.blobURL(img)!, maxPixels: 64) == nil,
                         "missing_blob_listed_thumbnail_nil")
            report.check(Paster.write(img, store: model.store, pasteboard: board) == -1, "missing_blob_copy_fails_cleanly")
            model.selection = [img.id]
            model.copySelection(pasteboard: board)
            report.check(model.notice?.contains("复制失败") == true, "missing_blob_copy_selection_reports_error", model.notice ?? "nil")
            report.check(model.richText(rich) == nil && Paster.write(rich, store: model.store, pasteboard: board) >= 0
                         && board.string(forType: .string) == rich.text, "missing_rtf_falls_back_to_plain_text")
            model.delete([img.id, rich.id])
            report.check(try (try model.store.item(id: img.id)) == nil && (try model.store.item(id: rich.id)) == nil && model.notice?.contains("删除失败") != true,
                         "missing_blob_item_deletable")

            // 4. Corrupt database: readable error, file left untouched for recovery.
            let h4 = home("corrupt")
            try fm.createDirectory(at: h4, withIntermediateDirectories: true)
            let dbURL = h4.appendingPathComponent("clipbook.sqlite3")
            var garbage = Data("THIS IS NOT A SQLITE DATABASE ".utf8)
            while garbage.count < 8192 { garbage.append(contentsOf: (0..<64).map { UInt8(($0 * 37 + garbage.count) % 251) }) }
            try garbage.write(to: dbURL)
            var storeError = ""
            do { _ = try ClipStore(home: h4); storeError = "未抛错" } catch { storeError = String(describing: error) }
            report.check(storeError.contains("SQL 失败") || storeError.contains("打不开数据库"), "corrupt_db_store_throws_readable_error", storeError)
            var modelError = ""
            do { _ = try AppModel(home: h4); modelError = "未抛错" } catch { modelError = String(describing: error) }
            report.check(!modelError.isEmpty && modelError != "未抛错", "corrupt_db_startup_path_throws", modelError)
            report.check((try Data(contentsOf: dbURL)) == garbage, "corrupt_db_file_not_overwritten")

            // 5. Deck import source missing / unusable: throws, library unchanged, no import marker.
            let h5 = home("deck")
            let target = try ClipStore(home: h5)
            _ = try target.ingest(cap("导入前已有"))
            let missing = home("no-such-deck")
            var missingThrew = false
            do { _ = try DeckImporter.run(into: target, deckHome: missing) } catch { missingThrew = true }
            report.check(try !DeckImporter.available(at: missing) && missingThrew && (try target.count()) == 1 && (try target.meta("deck_imported")) == nil,
                         "deck_missing_source_throws_library_unchanged")
            let badDeck = home("bad-deck")
            try fm.createDirectory(at: badDeck, withIntermediateDirectories: true)
            var ddb: OpaquePointer?
            sqlite3_open(badDeck.appendingPathComponent("Deck.sqlite3").path, &ddb)
            sqlite3_exec(ddb, "CREATE TABLE unrelated(x INTEGER)", nil, nil, nil)
            sqlite3_close(ddb)
            var schemaThrew = false
            do { _ = try DeckImporter.run(into: target, deckHome: badDeck) } catch { schemaThrew = true }
            report.check(try schemaThrew && (try target.count()) == 1 && (try target.meta("deck_imported")) == nil, "deck_wrong_schema_throws_library_unchanged")
            report.check(!fm.fileExists(atPath: fm.temporaryDirectory.appendingPathComponent("clipbook-deck-import-\(ProcessInfo.processInfo.processIdentifier)").path),
                         "deck_import_temp_copy_cleaned")

            // 6. Link title against a refused loopback port: nil, bounded time.
            if let port = closedLoopbackPort() {
                let result = AcceptanceReport.wait(8) { await LinkTitle.fetch("http://127.0.0.1:\(port)/") }
                report.check(result.elapsed < 6 && result.value != nil && result.value! == nil, "link_title_unreachable_returns_nil_bounded",
                             String(format: "%.2fs", result.elapsed))
            } else { report.check(false, "link_title_unreachable_returns_nil_bounded", "无法分配回环端口") }
            let invalid = AcceptanceReport.wait(3) { await LinkTitle.fetch("not a url") }
            report.check(invalid.value != nil && invalid.value! == nil, "link_title_invalid_url_nil")

            // 7. maxItems eviction leaves no orphan blobs.
            let h7 = home("evict")
            let ev = try ClipStore(home: h7)
            ev.maxItems = 3
            let t0 = Date().addingTimeInterval(-100)
            for i in 0..<6 {
                _ = try ev.ingest(Capture(kind: .image, text: "图片 \(10 + i)×10", imagePNG: AcceptanceReport.png(10 + i, 10, .systemGreen),
                                          width: 10 + i, height: 10, appName: "T", appBundle: "t"), at: t0.addingTimeInterval(Double(i)))
                _ = try ev.ingest(Capture(kind: .richText, text: "富文本 \(i)", rtf: AcceptanceReport.rtf("富文本 \(i)"), appName: "T", appBundle: "t"),
                                  at: t0.addingTimeInterval(Double(i) + 0.5))
            }
            let kept = try ev.list()
            let referenced = Set(kept.flatMap { [$0.blob, $0.rtf].compactMap { $0 } })
            let onDisk = blobFiles(ev)
            report.check(kept.count == 3 && onDisk == referenced, "max_items_eviction_no_orphan_blobs",
                         "保留 \(kept.count) 条，磁盘 \(onDisk.count) 个 blob，引用 \(referenced.count) 个")
            try ev.clear(keepPinned: false)
            report.check((try ev.count()) == 0 && blobFiles(ev).isEmpty, "clear_all_removes_every_blob")
        } catch {
            report.check(false, "recovery_test_error", "\(error)")
        }
        return report.finish()
    }
}
