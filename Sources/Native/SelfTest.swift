import AppKit
import Foundation

/// `Clipbook --selftest` —— build.sh 的阻断门。**只驱动生产函数**（ClipStore / PasteboardWatcher.extract），
/// 不另写一遍逻辑去「验证」。每条判据都带反例（该拒的真拒了、该去重的真去重了）。
enum SelfTest {
    private static var failures: [String] = []

    private static func check(_ ok: Bool, _ what: String) {
        print(ok ? "  ✅ \(what)" : "  🔴 \(what)")
        if !ok { failures.append(what) }
    }

    private static func cap(_ kind: ClipItem.Kind, _ text: String, png: Data? = nil, w: Int = 0, h: Int = 0, app: String = "T") -> Capture {
        Capture(kind: kind, text: text, imagePNG: png, width: w, height: h, appName: app, appBundle: "cyou.tianli.test.\(app)")
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

    static func run() -> Int32 {
        failures = []
        print("Clipbook --selftest")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("clipbook-selftest-\(ProcessInfo.processInfo.processIdentifier)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        do {
            let store = try ClipStore(home: tmp)
            let t0 = Date(timeIntervalSince1970: 1_000_000)

            print("· 入库 / 去重 / 顺序")
            let a = try store.ingest(cap(.text, "hello"), at: t0)
            let b = try store.ingest(cap(.text, "world"), at: t0.addingTimeInterval(1))
            check(try store.count() == 2, "两条不同文本 → 2 行")
            check(try store.list().map(\.id) == [b.id, a.id], "新的在上")
            let a2 = try store.ingest(cap(.text, "hello", app: "U"), at: t0.addingTimeInterval(2))
            check(try store.count() == 2 && a2.id == a.id, "同内容再复制不产生新行（id 复用 \(a.id)）")
            check(try store.list().first?.id == a.id, "再复制的旧条目被顶到最上")
            check(try store.list().first?.appName == "U", "顶上来时来源 app 更新为最新一次")
            check(ClipStore.hash(of: cap(.text, "x")) != ClipStore.hash(of: cap(.link, "x")), "同文本不同 kind 哈希不同")
            check((try store.ingest(cap(.text, "  \n"), at: t0)).text == "  \n", "Store 不做空白过滤（那是 Watcher 的职责）")
            try store.delete(try store.list().first { $0.text == "  \n" }!.id)

            print("· 图片 blob")
            let img = try store.ingest(cap(.image, "图片 8×6", png: png(8, 6), w: 8, h: 6), at: t0.addingTimeInterval(3))
            let blob = store.blobURL(img)
            check(blob.map { FileManager.default.fileExists(atPath: $0.path) } == true, "PNG 落盘到 blobs/")
            check(img.width == 8 && img.height == 6 && img.bytes > 0, "尺寸与字节数记录正确 (\(img.width)×\(img.height), \(img.bytes)B)")
            check(store.thumbOK(img), "落盘的 PNG 能被 NSImage 读回")
            try store.delete(img.id)
            check(blob.map { !FileManager.default.fileExists(atPath: $0.path) } == true, "删除条目时 blob 一起删")

            print("· 搜索（LIKE，含转义）")
            _ = try store.ingest(cap(.text, "浙江省水利水电勘测设计院"), at: t0.addingTimeInterval(4))
            _ = try store.ingest(cap(.text, "progress 100% done"), at: t0.addingTimeInterval(5))
            _ = try store.ingest(cap(.text, "snake_case_name"), at: t0.addingTimeInterval(6))
            check(try store.list(query: "水利").count == 1, "中文子串命中 1 条")
            check(try store.list(query: "zzz-none").isEmpty, "无匹配 → 空")
            check(try store.list(query: "100%").count == 1, "查询里的 % 按字面匹配（转义生效）")
            check(try store.list(query: "_case_").count == 1, "查询里的 _ 按字面匹配")
            check(try store.list(query: "  ").count == try store.count(), "纯空白查询 = 全量")
            check(try store.list(query: "U").count >= 1, "来源 app 名也参与匹配")

            print("· 置顶 / 清空 / 留存")
            let old = try store.list().last!
            try store.setPinned(old.id, true)
            check(try store.list().first?.id == old.id, "置顶后最老的一条排到最上")
            store.maxItems = 2
            for i in 0..<4 { _ = try store.ingest(cap(.text, "bulk \(i)"), at: t0.addingTimeInterval(Double(10 + i))) }
            let after = try store.list()
            check(after.filter { !$0.pinned }.count == 2 && after.contains { $0.pinned }, "超过 maxItems 淘汰最老的非置顶，置顶不动（\(after.count) 行）")
            check(after.filter { !$0.pinned }.map(\.text) == ["bulk 3", "bulk 2"], "留下的是最新两条")
            try store.clear(keepPinned: true)
            check(try store.list().map(\.id) == [old.id], "清空保留置顶")
            try store.clear(keepPinned: false)
            check(try store.count() == 0, "全清 → 0")
        } catch {
            check(false, "Store 抛错：\(error)")
        }

        print("· Watcher.extract（私有 pasteboard 驱动同一函数）")
        let pb = NSPasteboard(name: .init("cyou.tianli.clipbook.selftest"))
        func reset() { pb.clearContents() }
        reset(); pb.setString("plain text", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a")?.kind == .text, "纯字符串 → text")
        reset(); pb.setString("https://example.com/a?b=1", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a")?.kind == .link, "单行 http(s) → link")
        reset(); pb.setString("看 https://example.com 这个", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a")?.kind == .text, "含空格的句子里有链接仍是 text")
        reset(); pb.setString("   \n\t", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "A", appBundle: "a") == nil, "纯空白 → 不记")
        reset(); pb.writeObjects([URL(fileURLWithPath: "/tmp") as NSURL]); pb.setString("tmp", forType: .string)
        let f = PasteboardWatcher.extract(from: pb, appName: "Finder", appBundle: "f")
        check(f?.kind == .file && f?.text == "/tmp", "文件 URL + 文件名文本 → file 优先（\(f?.text ?? "nil")）")
        reset(); pb.setData(png(4, 4), forType: .png); pb.setString("word says", forType: .string)
        check(PasteboardWatcher.extract(from: pb, appName: "Word", appBundle: "w")?.kind == .text, "文本 + 渲染图 → text 优先（Word/Excel 场景）")
        reset(); pb.setData(png(5, 3), forType: .png)
        let i = PasteboardWatcher.extract(from: pb, appName: "Shot", appBundle: "s")
        check(i?.kind == .image && i?.width == 5 && i?.height == 3 && i?.imagePNG != nil, "只有图 → image 5×3")
        reset(); pb.setString("secret", forType: .string); pb.setData(Data(), forType: PasteboardWatcher.concealed)
        check(PasteboardWatcher.extract(from: pb, appName: "1P", appBundle: "p") == nil, "ConcealedType（密码管理器）→ 不记")
        reset(); pb.setString("tmp", forType: .string); pb.setData(Data(), forType: PasteboardWatcher.transient)
        check(PasteboardWatcher.extract(from: pb, appName: "X", appBundle: "x") == nil, "TransientType → 不记")
        pb.releaseGlobally()

        print("· 标题")
        let multi = ClipItem(id: 1, kind: .text, text: "\n\n  第一行   有  空格\n第二行", blob: nil, appName: "", appBundle: "",
                             createdAt: Date(), pinned: false, bytes: 0, width: 0, height: 0)
        check(multi.title == "第一行 有 空格", "标题取首个非空行并压空白（得「\(multi.title)」）")
        check(multi.lineCount == 4, "行数按原文算（\(multi.lineCount)）")

        if failures.isEmpty {
            print("✅ selftest 全部通过")
            return 0
        }
        print("🔴 selftest 失败 \(failures.count) 项：")
        failures.forEach { print("   - \($0)") }
        return 1
    }
}

extension ClipStore {
    func thumbOK(_ item: ClipItem) -> Bool {
        guard let url = blobURL(item) else { return false }
        return NSImage(contentsOf: url) != nil
    }
}
