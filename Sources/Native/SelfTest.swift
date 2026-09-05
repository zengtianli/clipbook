import AppKit
import Foundation
import SQLite3

/// `Clipbook --selftest` —— build.sh 的阻断门。**只驱动生产函数**（ClipStore / Classifier / PasteboardWatcher.extract /
/// DeckImporter / Transform），不另写一遍逻辑去「验证」。每条判据都带反例。
enum SelfTest {
    private static var failures: [String] = []

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "  ✅ \(what)" : "  🔴 \(what)")
        if !ok { failures.append(what) }
    }

    private static func cap(_ kind: ClipItem.Kind, _ text: String, png: Data? = nil, rtf: Data? = nil, w: Int = 0, h: Int = 0, app: String = "T", title: String = "") -> Capture {
        Capture(kind: kind, text: text, imagePNG: png, rtf: rtf, width: w, height: h, appName: app, appBundle: "cyou.tianli.test.\(app)", title: title)
    }

    private static func png(_ w: Int, _ h: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    private static func rtf(_ s: String) -> Data {
        let a = NSAttributedString(string: s, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        return a.rtf(from: NSRange(location: 0, length: a.length), documentAttributes: [:])!
    }

    static func run() -> Int32 {
        failures = []
        print("Clipbook --selftest")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clipbook-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        print("· Classifier")
        check(Classifier.kind(of: "https://example.com/a?b=1") == .link, "单行 http(s) → link")
        check(Classifier.kind(of: "看 https://example.com 这个") == .text, "句子里夹链接 → text")
        check(Classifier.kind(of: "#2E6F5E") == .color && Classifier.kind(of: "rgb(10, 20, 30)") == .color, "#hex / rgb() → color")
        check(Classifier.kind(of: "#2E6F5E 是主色") == .text, "带说明的色值不算 color")
        check(Classifier.kind(of: "def f(x):\n    return x * 2\n\nprint(f(21))\n") == .code, "Python 片段 → code")
        check(Classifier.kind(of: "func a() {\n  let b = 1;\n}") == .code, "Swift 片段 → code")
        check(Classifier.kind(of: "浙江省水利水电勘测设计院\n第二行普通文字") == .text, "两行中文 → text（不误判代码）")
        check(Classifier.kind(of: "let it be") == .text, "单行含关键字 → text（单行永不算代码）")

        do {
            let store = try ClipStore(home: tmp)
            let t0 = Date(timeIntervalSince1970: 1_000_000)

            print("· 入库 / 去重 / 顺序")
            let a = try store.ingest(cap(.text, "hello"), at: t0)
            let b = try store.ingest(cap(.text, "world"), at: t0.addingTimeInterval(1))
            check(try store.count() == 2, "两条不同文本 → 2 行")
            check(try store.list().map(\.id) == [b.id, a.id], "新的在上")
            let a2 = try store.ingest(cap(.text, "hello", app: "U"), at: t0.addingTimeInterval(2))
            let n2 = try store.count()
            check(n2 == 2 && a2.id == a.id, "同内容再复制不产生新行（id 复用 \(a.id)）")
            let top = try store.list().first
            check(top?.id == a.id && top?.appName == "U", "再复制的旧条目顶到最上、来源更新")
            let older = try store.ingest(cap(.text, "hello"), at: t0)
            check(older.createdAt.timeIntervalSince1970 == t0.addingTimeInterval(2).timeIntervalSince1970, "更早时间戳的重复（导入场景）不把条目往回拖")

            print("· 图片 / 富文本 blob")
            let img = try store.ingest(cap(.image, "图片 8×6", png: png(8, 6), w: 8, h: 6), at: t0.addingTimeInterval(3))
            let blob = store.blobURL(img)
            check(blob.map { FileManager.default.fileExists(atPath: $0.path) } == true, "PNG 落盘到 blobs/")
            check(img.width == 8 && img.height == 6 && img.bytes > 0, "尺寸与字节数记录正确")
            try store.delete(img.id)
            check(blob.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "删除条目时 blob 一起删")
            let rich = try store.ingest(cap(.richText, "粗体字", rtf: rtf("粗体字")), at: t0.addingTimeInterval(4))
            check(rich.kind == .richText && store.rtfURL(rich).map { FileManager.default.fileExists(atPath: $0.path) } == true, "RTF 落盘")
            let richEdited = try store.updateText(rich.id, text: "粗体字改过")
            check(richEdited.kind == .text && richEdited.rtf == nil, "富文本编辑保存 → 降为纯文本，RTF 删掉")

            print("· 编辑保存")
            let e = try store.ingest(cap(.text, "edit me"), at: t0.addingTimeInterval(5))
            let e2 = try store.updateText(e.id, text: "https://edited.example")
            check(e2.id == e.id && e2.text == "https://edited.example" && e2.kind == .link, "覆盖原条目，且按新内容重识别为 link")
            _ = try store.ingest(cap(.text, "dup target"), at: t0.addingTimeInterval(6))
            let e3 = try store.ingest(cap(.text, "will become dup"), at: t0.addingTimeInterval(7))
            let before = try store.count()
            _ = try store.updateText(e3.id, text: "dup target")
            check(try store.count() == before - 1, "改成与另一条相同 → 另一条被删，库里不留两份")
            try store.setTitle(e3.id, "  我的标题 ")
            check(try store.item(id: e3.id)?.title == "我的标题", "标题保存并去首尾空白")
            check(try store.item(id: e3.id)?.displayTitle == "我的标题", "有标题时卡片显示标题")

            print("· 搜索 / 筛选 / 分页")
            _ = try store.ingest(cap(.text, "浙江省水利水电勘测设计院"), at: t0.addingTimeInterval(8))
            _ = try store.ingest(cap(.text, "progress 100% done"), at: t0.addingTimeInterval(9))
            _ = try store.ingest(cap(.link, "https://github.com/x", app: "Dia"), at: t0.addingTimeInterval(10))
            try store.setExtra(try store.list(.init(kind: .link)).first { $0.text == "https://github.com/x" }!.id, "GitHub 首页")
            check(try store.list(.init(text: "水利")).count == 1, "中文子串命中 1 条")
            check(try store.list(.init(text: "100%")).count == 1, "查询里的 % 按字面匹配")
            check(try store.list(.init(text: "GitHub 首页")).count == 1, "链接标题（extra）参与搜索")
            let links = try store.list(.init(kind: .link)); let nLinks = try store.count(.init(kind: .link))
            check(links.allSatisfy { $0.kind == .link } && nLinks == 2, "按类型筛（link 2 条）")
            check(try store.count(.init(appBundle: "cyou.tianli.test.Dia")) == 1, "按来源 app 筛")
            let p0 = try store.list(.init(), page: 0, pageSize: 3); let p1 = try store.list(.init(), page: 1, pageSize: 3)
            check(p0.count == 3 && p1.count == 3 && Set(p0.map(\.id)).isDisjoint(with: p1.map(\.id)), "分页每页 3 条且不重叠")
            let kc = try store.kindCounts(); let ac = try store.appCounts()
            check(kc[.text, default: 0] >= 4 && ac.contains { $0.bundle == "cyou.tianli.test.Dia" }, "侧栏计数")

            print("· 收藏夹")
            let c1 = try store.createCollection(name: "工作")
            let c2 = try store.createCollection(name: "灵感", color: "#dc2626", icon: "star")
            check(try store.collections().map(\.name) == ["工作", "灵感"], "新建两个收藏夹按顺序")
            try store.add([a.id, b.id], to: c1.id)
            try store.add([a.id], to: c2.id)
            let nC1 = try store.count(.init(collection: c1.id)); let aCols = try store.collectionIDs(of: a.id)
            check(nC1 == 2 && aCols == [c1.id, c2.id], "一条可属多个收藏夹")
            try store.remove(a.id, from: c2.id)
            check(try store.collectionIDs(of: a.id) == [c1.id], "移出收藏夹")
            try store.reorderCollections([c2.id, c1.id])
            check(try store.collections().map(\.name) == ["灵感", "工作"], "收藏夹排序")
            try store.deleteCollection(c2.id)
            let nCols = try store.collections().count; let aStill = try store.item(id: a.id)
            check(nCols == 1 && aStill != nil, "删收藏夹不删条目")

            print("· 合并 / 置顶 / 留存 / 清空")
            let m = try store.merge([a.id, b.id])
            check(m.text == "hello\n\nworld", "合并按顺序、空行分隔（\(m.text.replacingOccurrences(of: "\n", with: "⏎"))）")
            try store.setPinned(b.id, true)
            check(try store.list().first?.id == b.id, "置顶排到最上")
            store.maxItems = 3
            for i in 0..<4 { _ = try store.ingest(cap(.text, "bulk \(i)"), at: t0.addingTimeInterval(Double(20 + i))) }
            let after = try store.list()
            let unprotected = after.filter { !$0.pinned && !(try! store.collectionIDs(of: $0.id).contains(c1.id)) }
            check(unprotected.count == 3 && after.contains { $0.id == b.id } && after.contains { $0.id == a.id }, "超 maxItems 淘汰最老的无保护条目；置顶与收藏夹里的不动")
            try store.clear(keepPinned: true)
            check(Set(try store.list().map(\.id)) == [a.id, b.id], "清空保留置顶与收藏夹里的")
            try store.clear(keepPinned: false)
            check(try store.count() == 0, "全清 → 0")

            print("· Deck 导入（造一个 Deck 结构的库喂给同一个导入器）")
            let deck = tmp.appendingPathComponent("deck", isDirectory: true)
            try FileManager.default.createDirectory(at: deck.appendingPathComponent("Blobs"), withIntermediateDirectories: true)
            try png(3, 2).write(to: deck.appendingPathComponent("Blobs/img-uid"))
            var ddb: OpaquePointer?
            sqlite3_open(deck.appendingPathComponent("Deck.sqlite3").path, &ddb)
            sqlite3_exec(ddb, """
            CREATE TABLE ClipboardHistory(id INTEGER PRIMARY KEY, unique_id TEXT, type TEXT, item_type TEXT, data BLOB, preview_data BLOB,
              timestamp INTEGER, app_path TEXT, app_name TEXT, custom_title TEXT, source_anchor TEXT, search_text TEXT, content_length INTEGER,
              tag_id INTEGER DEFAULT -1, blob_path TEXT, is_temporary INTEGER DEFAULT 0, is_encrypted INTEGER DEFAULT 0, received_from_lan INTEGER DEFAULT 0);
            INSERT INTO ClipboardHistory(unique_id,type,item_type,data,timestamp,app_path,app_name,custom_title,search_text,content_length) VALUES
              ('u1','public.utf8-plain-text','text',CAST('hello deck' AS BLOB),1700000000,'/System/Applications/TextEdit.app','TextEdit','旧标题','hello deck',10),
              ('u2','public.utf8-plain-text','url',CAST('https://deck.example/x' AS BLOB),1700000001,'/System/Applications/TextEdit.app','TextEdit',NULL,'',22),
              ('u3','public.file-url','file',CAST('/tmp/a.txt\n/tmp/b.txt' AS BLOB),1700000002,'/System/Library/CoreServices/Finder.app','Finder',NULL,'',21),
              ('img-uid','public.png','image',X'',1700000003,'/System/Applications/TextEdit.app','TextEdit',NULL,'',0),
              ('u5','public.utf8-plain-text','text',CAST('hello deck' AS BLOB),1700000004,'/System/Applications/TextEdit.app','TextEdit',NULL,'hello deck',10),
              ('img-old','public.png','image',X'',1700000007,'/System/Applications/Preview.app','Preview',NULL,'',0),
              ('u6','public.utf8-plain-text','text',CAST('secret' AS BLOB),1700000005,'/System/Applications/TextEdit.app','TextEdit',NULL,'secret',6);
            UPDATE ClipboardHistory SET is_encrypted = 1 WHERE unique_id = 'u6';
            """, nil, nil, nil)
            var pvStmt: OpaquePointer?
            sqlite3_prepare_v2(ddb, "UPDATE ClipboardHistory SET preview_data = ? WHERE unique_id = 'img-old'", -1, &pvStmt, nil)
            let pv = png(7, 5)
            _ = pv.withUnsafeBytes { sqlite3_bind_blob(pvStmt, 1, $0.baseAddress, Int32(pv.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_step(pvStmt); sqlite3_finalize(pvStmt)
            var rtfStmt: OpaquePointer?
            sqlite3_prepare_v2(ddb, "INSERT INTO ClipboardHistory(unique_id,type,item_type,data,timestamp,app_path,app_name,search_text,content_length) VALUES('u7','public.rtf','richText',?,1700000006,'/System/Applications/Notes.app','Notes','',0)", -1, &rtfStmt, nil)
            let rtfData = rtf("富文本来的")
            _ = rtfData.withUnsafeBytes { sqlite3_bind_blob(rtfStmt, 1, $0.baseAddress, Int32(rtfData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            sqlite3_step(rtfStmt); sqlite3_finalize(rtfStmt); sqlite3_close(ddb)

            let rep = try DeckImporter.run(into: store, deckHome: deck)
            check(rep.scanned == 7 && rep.imported == 7 && rep.byKind[.image] == 2 && rep.byKind[.richText] == 1, "扫 7（加密的那条不扫）→ 导 7（\(rep)）")
            let all = try store.list()
            check(all.count == 6, "同内容两条合成一条 → 库里 6 条（实得 \(all.count)）")
            check(all.contains { $0.kind == .image && $0.width == 7 && $0.height == 5 }, "没原图的老图片用 preview_data 缩略导入 7×5")
            check(all.first { $0.text == "hello deck" }?.title == "旧标题", "Deck 的 custom_title 进标题")
            check(all.first { $0.text == "hello deck" }?.appBundle == "com.apple.TextEdit", "app_path 推出 bundle id")
            check(all.contains { $0.kind == .link && $0.text == "https://deck.example/x" }, "url → link")
            check(all.contains { $0.kind == .file && $0.filePaths == ["/tmp/a.txt", "/tmp/b.txt"] }, "file 路径按行")
            check(all.contains { $0.kind == .image && $0.width == 3 && $0.height == 2 }, "image 从 Blobs/<unique_id> 读出 3×2")
            check(all.contains { $0.kind == .richText && $0.text == "富文本来的" }, "richText 解出纯文本并存 RTF")
            check(try store.meta("deck_imported") != nil, "记录导入时间")
            let rep2 = try DeckImporter.run(into: store, deckHome: deck)
            let nAfter2 = try store.count()
            check(nAfter2 == 6 && rep2.imported == 7, "重复导入幂等（还是 6 条）")
        } catch {
            check(false, "Store 抛错：\(error)")
        }

        print("· Transform")
        check(Transform.trim.apply("  a b \n") == "a b" && Transform.oneLine.apply("a\n  b\nc") == "a b c", "去空白 / 去换行")
        check(Transform.json.apply("{\"b\":1,\"a\":[2]}") == "{\n  \"a\" : [\n    2\n  ],\n  \"b\" : 1\n}", "JSON 格式化（键排序）")
        check(Transform.json.apply("not json") == "not json", "非 JSON 原样返回")

        print("· Watcher.extract（私有 pasteboard 驱动同一函数）")
        let pb = NSPasteboard(name: .init("cyou.tianli.clipbook.selftest"))
        func reset() { pb.clearContents() }
        reset(); pb.setString("plain text", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a")?.kind == .text, "纯字符串 → text")
        reset(); pb.setString("https://example.com/a?b=1", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a")?.kind == .link, "单行 http(s) → link")
        reset(); pb.setString("   \n\t", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a") == nil, "纯空白 → 不记")
        reset(); pb.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL]); pb.setString("tmp", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "Finder", appBundle: "f")?.kind == .file, "文件 URL + 文件名文本 → file 优先")
        reset(); pb.setData(png(4, 4), forType: .png); pb.setString("word says", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "Word", appBundle: "w")?.kind == .text, "文本 + 渲染图 → text 优先")
        reset(); pb.setString("粗体", forType: .string); pb.setData(rtf("粗体"), forType: .rtf)
        let r1 = PasteboardWatcher.extract(from: pb, appName: "Notes", appBundle: "n")
        check(r1?.kind == .richText && r1?.rtf != nil, "文本 + RTF → richText")
        check(PasteboardWatcher.extract(from: pb, appName: "Notes", appBundle: "n", plainTextOnly: true)?.kind == .text, "纯文本模式 → 丢 RTF 记 text")
        reset(); pb.setString("#AABBCC", forType: .string); pb.setData(rtf("#AABBCC"), forType: .rtf)
        check(PasteboardWatcher.extract(from: pb, appName: "X", appBundle: "x")?.kind == .color, "带 RTF 的色值仍识别为 color")
        reset(); pb.setData(png(5, 3), forType: .png)
        let i = PasteboardWatcher.extract(from: pb, appName: "Shot", appBundle: "s")
        check(i?.kind == .image && i?.width == 5 && i?.height == 3, "只有图 → image 5×3")
        reset(); pb.setString("secret", forType: .string); pb.setData(Data(), forType: PasteboardWatcher.concealed)
        check(PasteboardWatcher.extract(from: pb, appName: "1P", appBundle: "p") == nil, "ConcealedType → 不记")
        pb.releaseGlobally()

        print("· LinkTitle.parseTitle")
        check(LinkTitle.parseTitle("<html><head><TITLE>\n  A &amp; B\n</TITLE></head>") == "A & B", "大小写不敏感、解实体、压空白")
        check(LinkTitle.parseTitle("<html>no title</html>") == nil, "没有 title → nil")

        if failures.isEmpty { print("✅ selftest 全部通过"); return 0 }
        print("🔴 selftest 失败 \(failures.count) 项："); failures.forEach { print("   - \($0)") }
        return 1
    }
}
