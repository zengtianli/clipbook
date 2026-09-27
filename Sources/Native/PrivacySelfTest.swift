import AppKit
import Darwin

/// Loopback-only HTTP responder that counts connections, so link-title fetching is observable
/// without leaving the machine. Bound to 127.0.0.1; closed when the test ends.
final class LoopbackTitleServer: @unchecked Sendable {
    let port: UInt16
    private let fd: Int32
    private let lock = NSLock()
    private var count = 0
    var hits: Int { lock.lock(); defer { lock.unlock() }; return count }

    init?(title: String) {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        guard ok, listen(fd, 8) == 0 else { close(fd); return nil }
        self.fd = fd
        self.port = UInt16(bigEndian: addr.sin_port)
        let body = "<html><head><title>\(title)</title></head><body>ok</body></html>"
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { break }
                lock.lock(); count += 1; lock.unlock()
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = read(c, &buffer, buffer.count)
                _ = response.withCString { write(c, $0, strlen($0)) }
                close(c)
            }
        }
    }

    func stop() { shutdown(fd, SHUT_RDWR); close(fd) }
}

/// `Clipbook --privacy-test`: drives the production PasteboardWatcher → AppModel.ingest path
/// on the isolated named pasteboard, plus the cloud archive mapping in local-only mode.
@MainActor
enum PrivacySelfTest {
    static func run() -> Int32 {
        let report = AcceptanceReport()
        guard let isolated = AcceptanceReport.isolatedRoot("--privacy-test") else { return 2 }
        let fm = FileManager.default
        let root = isolated.appendingPathComponent("privacy-\(UUID().uuidString)", isDirectory: true)
        var server: LoopbackTitleServer?
        let settings = AppSettings.shared
        let savedIgnored = settings.ignoredBundles
        defer {
            server?.stop()
            settings.ignoredBundles = savedIgnored; settings.paused = false; settings.fetchLinkTitles = false
            ProductIdentity.pasteboard.clearContents()
            ProductIdentity.pasteboard.releaseGlobally()
            try? fm.removeItem(at: root)
        }
        report.notCovered = [
            "iCloud 真实上传与 CloudKit 账户切换（仅在本地模式驱动生产映射 MacClipSync.sendRecent → ClipLibrary.save，不连 iCloud）",
            "编辑/删除/收藏的云端双向镜像（产品声明不承诺）",
            "来源应用识别依赖系统前台应用；忽略名单用当前前台 bundle 驱动同一生产判据",
        ]
        do {
            let generalBefore = NSPasteboard.general.changeCount
            let board = ProductIdentity.pasteboard
            report.check(board !== NSPasteboard.general && board.name != .general, "isolated_named_pasteboard", board.name.rawValue)

            let prefs = AppPreferences.defaults
            let cloudDefault = prefs.object(forKey: "cloudEnabled") == nil || prefs.bool(forKey: "cloudEnabled") == false
            settings.copySound = false; settings.paused = false; settings.fetchLinkTitles = false; settings.plainTextOnly = false
            let home = root.appendingPathComponent("watch", isDirectory: true)
            let model = try AppModel(home: home)
            AppModel.shared = model
            model.watcher.stop()
            let watcher = model.watcher!
            func count() -> Int { (try? model.store.count()) ?? -1 }
            func copyExternally(_ fill: (NSPasteboard) -> Void) { board.clearContents(); fill(board); watcher.poll() }

            // Positive control: an ordinary copy is recorded through the production path.
            copyExternally { $0.setString("普通复制应当被记录", forType: .string) }
            report.check(try count() == 1 && (try model.store.list()).first?.text == "普通复制应当被记录", "control_plain_copy_recorded")

            copyExternally { $0.setString("hunter2-concealed", forType: .string); $0.setData(Data(), forType: PasteboardWatcher.concealed) }
            report.check(try count() == 1 && (try model.store.list(.init(text: "hunter2"))).isEmpty, "concealed_type_not_recorded")
            copyExternally { $0.setString("otp-transient-123456", forType: .string); $0.setData(Data(), forType: PasteboardWatcher.transient) }
            report.check(try count() == 1 && (try model.store.list(.init(text: "otp-transient"))).isEmpty, "transient_type_not_recorded")
            copyExternally {
                $0.setData(AcceptanceReport.png(8, 8, .systemRed), forType: .png); $0.setData(Data(), forType: PasteboardWatcher.concealed)
            }
            report.check(count() == 1, "concealed_image_not_recorded")

            let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
            settings.ignoredBundles = [front]
            copyExternally { $0.setString("来自忽略名单应用的复制", forType: .string) }
            let ignoredOK = count() == 1 && watcher.ignoredBundles.contains(front)
            settings.ignoredBundles = savedIgnored
            report.check(ignoredOK, "ignored_bundle_not_recorded", "bundle \(front.isEmpty ? "<空>" : front)")

            settings.paused = true
            copyExternally { $0.setString("暂停期间的复制", forType: .string) }
            let pausedOK = count() == 1 && watcher.paused
            settings.paused = false
            copyExternally { $0.setString("恢复后的复制", forType: .string) }
            report.check(pausedOK && count() == 2, "paused_not_recorded_resume_records")

            // Clip's own copy is not re-captured as a new clipboard event.
            let own = try model.store.list().first!
            model.copy(own)
            let beforeOwn = (try model.store.list()).map(\.id)
            watcher.poll()
            report.check(try count() == 2 && (try model.store.list()).map(\.id) == beforeOwn, "own_copy_suppressed")

            // Link titles: no connection while disabled; the same loopback server is hit when enabled (control).
            server = LoopbackTitleServer(title: "Clip Loopback Title")
            if let server {
                let disabledURL = "http://127.0.0.1:\(server.port)/disabled"
                copyExternally { $0.setString(disabledURL, forType: .string) }
                AcceptanceReport.settle(1.5)
                let disabledItem = try model.store.list(.init(text: "/disabled")).first
                report.check(server.hits == 0 && disabledItem?.kind == .link && disabledItem?.extra == "", "link_title_not_fetched_when_disabled",
                             "连接数 \(server.hits)")
                settings.fetchLinkTitles = true
                copyExternally { $0.setString("http://127.0.0.1:\(server.port)/enabled", forType: .string) }
                let deadline = Date().addingTimeInterval(6)
                while Date() < deadline, (try model.store.list(.init(text: "/enabled")).first?.extra ?? "").isEmpty {
                    AcceptanceReport.settle(0.1)
                }
                settings.fetchLinkTitles = false
                let enabledItem = try model.store.list(.init(text: "/enabled")).first
                report.check(server.hits >= 1 && enabledItem?.extra == "Clip Loopback Title", "link_title_control_fetches_when_enabled",
                             "连接数 \(server.hits)，标题 \(enabledItem?.extra ?? "nil")")
            } else { report.check(false, "link_title_not_fetched_when_disabled", "无法启动回环服务") }

            // Cloud is off by default and never started: no archive store on disk.
            let cloudDirs = ["CloudLibrary", "CloudLibrary-Production"].map { home.appendingPathComponent($0).path }
            report.check(cloudDefault && !prefs.bool(forKey: "cloudEnabled") && cloudDirs.allSatisfy { !fm.fileExists(atPath: $0) },
                         "cloud_disabled_by_default_no_cloud_library")
            let metaKeys = (try? model.store.list())?.compactMap { item in try? model.store.meta("cloudArchive.v2.Production.\(item.id)") } ?? []
            report.check(metaKeys.isEmpty, "no_cloud_archive_markers_written")

            // Cloud mapping in local-only mode via the production MacClipSync.sendRecent → ClipLibrary.save.
            let mapHome = root.appendingPathComponent("cloud-map", isDirectory: true)
            let mapModel = try AppModel(home: mapHome)
            mapModel.watcher.stop()
            let secretPath = "/Users/example/Private/合同-机密.pdf"
            _ = try mapModel.store.ingest(Capture(kind: .file, text: secretPath + "\n/Users/example/Private/b.txt", appName: "Finder", appBundle: "com.apple.finder"))
            let rich = try mapModel.store.ingest(Capture(kind: .richText, text: "粗体富文本", rtf: AcceptanceReport.rtf("粗体富文本"), appName: "Notes", appBundle: "com.apple.Notes"))
            _ = try mapModel.store.ingest(Capture(kind: .text, text: "普通文本归档", appName: "T", appBundle: "t"))
            _ = try mapModel.store.ingest(Capture(kind: .image, text: "图片 12×12", imagePNG: AcceptanceReport.png(12, 12, .systemBlue), width: 12, height: 12, appName: "T", appBundle: "t"))
            let sync = mapModel.cloud
            let started = AcceptanceReport.wait(15) { await sync.library.start(localOnly: true); return sync.library.ready }
            report.check(started.value == true && !sync.library.cloudEnabled && sync.library.container?.persistentStoreDescriptions.first?.cloudKitContainerOptions == nil,
                         "cloud_mapping_local_only_store", sync.library.error ?? "")
            _ = AcceptanceReport.wait(15) { await sync.sendRecent(); return true }
            let archived = (try? sync.library.list(limit: 100)) ?? []
            let texts = archived.map(\.text)
            report.check(!archived.isEmpty && !texts.contains { $0.contains(secretPath) || $0.contains("/Users/example/Private") },
                         "cloud_mapping_file_paths_not_uploaded", "归档 \(archived.count) 条")
            let entity = ClipLibrary.makeModel().entitiesByName["ClipRecord"]
            report.check(texts.contains(rich.text) && archived.first { $0.text == rich.text }?.kind == "text"
                         && entity?.attributesByName.keys.contains { $0.lowercased().contains("rtf") } == false,
                         "cloud_mapping_rich_text_as_plain_text")
            report.check(archived.count == 3 && archived.contains { $0.kind == "image" } && texts.contains("普通文本归档"), "cloud_mapping_text_and_image_archived")
            report.check(NSPasteboard.general.changeCount == generalBefore, "general_pasteboard_untouched")
        } catch {
            report.check(false, "privacy_test_error", "\(error)")
        }
        return report.finish()
    }
}
