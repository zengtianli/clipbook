import Foundation

/// 一条剪贴板记录。四种形态覆盖实测 Deck 里 99% 的条目
/// （文本 60% / 图片 20% / 文件 7% / 富文本 7% → 富文本按纯文本记，链接从文本里分出来）。
struct ClipItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable {
        case text, link, image, file

        var symbol: String {
            switch self {
            case .text:  return "text.alignleft"
            case .link:  return "link"
            case .image: return "photo"
            case .file:  return "doc"
            }
        }
        var label: String {
            switch self {
            case .text:  return "文本"
            case .link:  return "链接"
            case .image: return "图片"
            case .file:  return "文件"
            }
        }
    }

    let id: Int64
    let kind: Kind
    /// text/link = 内容本身；file = 路径按行；image = 尺寸说明
    let text: String
    /// image 的 PNG 落盘相对路径（相对 blobs/）
    let blob: String?
    let appName: String
    let appBundle: String
    let createdAt: Date
    let pinned: Bool
    let bytes: Int
    let width: Int
    let height: Int

    /// 列表里那一行：首个非空行，压掉多余空白，最多 140 字符
    var title: String {
        switch kind {
        case .image:
            return "图片 \(width)×\(height)"
        case .file:
            let paths = filePaths
            if paths.count == 1 { return paths[0].lastPathComponent }
            return "\(paths.count) 个文件：" + paths.prefix(3).map(\.lastPathComponent).joined(separator: "、")
        default:
            let line = text.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
            let squashed = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            return squashed.count > 140 ? String(squashed.prefix(140)) + "…" : String(squashed)
        }
    }

    var filePaths: [String] {
        kind == .file ? text.split(separator: "\n").map(String.init) : []
    }

    var lineCount: Int {
        kind == .text ? text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count : 1
    }
}

private extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}

/// 从剪贴板抓下来、还没入库的一条。Watcher 产出，Store 消费；SelfTest 也直接造它。
struct Capture: Equatable {
    var kind: ClipItem.Kind
    var text: String
    var imagePNG: Data?
    var width: Int = 0
    var height: Int = 0
    var appName: String
    var appBundle: String
}
