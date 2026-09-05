import AppKit

/// 轮询 NSPasteboard.general.changeCount（macOS 没有剪贴板变更通知，Maccy/Deck 都是轮询）。
///
/// 抓取优先级 **文件 > 文本 > 图片**：
///   · Finder 复制文件时同时带文件名文本 → 要文件不要文本；
///   · Word/Excel 复制一段字时同时带 TIFF 渲染图 → 要文本不要图（Deck 实测 258 条 Word 条目里 TIFF 只 27 条）；
///   · 只有纯图片（截图/浏览器拷图）才落图片。
/// 跳过：密码管理器标记的 ConcealedType / TransientType；自己刚写进去的那一次（Paster 记 changeCount）。
final class PasteboardWatcher {
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pb: NSPasteboard
    private var lastCount: Int
    private var timer: Timer?
    private let onCapture: (Capture) -> Void
    /// Paster 写完剪贴板后把 changeCount 记在这里，轮询到同一个值就跳过（不把自己粘贴的再记一遍）。
    var suppressedChangeCount: Int = -1
    var paused = false

    init(pasteboard: NSPasteboard = .general, onCapture: @escaping (Capture) -> Void) {
        self.pb = pasteboard
        self.lastCount = pasteboard.changeCount
        self.onCapture = onCapture
    }

    func start(interval: TimeInterval = 0.25) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.1
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let c = pb.changeCount
        guard c != lastCount else { return }
        lastCount = c
        guard !paused, c != suppressedChangeCount else { return }
        let front = NSWorkspace.shared.frontmostApplication
        guard let cap = Self.extract(from: pb,
                                     appName: front?.localizedName ?? "",
                                     appBundle: front?.bundleIdentifier ?? "") else { return }
        onCapture(cap)
    }

    /// 纯函数：从任意 pasteboard 抽一条 Capture。SelfTest 用私有 pasteboard 直接驱动**这同一个函数**。
    static func extract(from pb: NSPasteboard, appName: String, appBundle: String) -> Capture? {
        let types = Set(pb.types ?? [])
        if types.contains(concealed) || types.contains(transient) { return nil }

        // ① 文件
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let text = urls.map(\.path).joined(separator: "\n")
            return Capture(kind: .file, text: text, appName: appName, appBundle: appBundle)
        }
        // ② 文本 / 链接
        if let s = pb.string(forType: .string), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            let isLink = !trimmed.contains(where: \.isWhitespace)
                && (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            return Capture(kind: isLink ? .link : .text, text: s, appName: appName, appBundle: appBundle)
        }
        // ③ 图片
        if types.contains(.png) || types.contains(.tiff) {
            let data = pb.data(forType: .png) ?? pb.data(forType: .tiff)
            guard let data, let rep = NSBitmapImageRep(data: data) else { return nil }
            let png = (types.contains(.png) ? data : rep.representation(using: .png, properties: [:]))
            guard let png else { return nil }
            return Capture(kind: .image, text: "图片 \(rep.pixelsWide)×\(rep.pixelsHigh)", imagePNG: png,
                           width: rep.pixelsWide, height: rep.pixelsHigh, appName: appName, appBundle: appBundle)
        }
        return nil
    }
}
