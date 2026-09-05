import Foundation

/// 一条剪贴板记录。类型按 PastePal 的「智能类型」分：文本 / 富文本 / 链接 / 图片 / 文件 / 代码 / 颜色。
struct ClipItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case text, richText, link, image, file, code, color
        var id: String { rawValue }

        var symbol: String {
            switch self {
            case .text:     return "text.alignleft"
            case .richText: return "textformat"
            case .link:     return "link"
            case .image:    return "photo"
            case .file:     return "doc"
            case .code:     return "chevron.left.forwardslash.chevron.right"
            case .color:    return "paintpalette"
            }
        }
        var label: String {
            switch self {
            case .text:     return "文本"
            case .richText: return "富文本"
            case .link:     return "链接"
            case .image:    return "图片"
            case .file:     return "文件"
            case .code:     return "代码"
            case .color:    return "颜色"
            }
        }
        /// 正文可以在编辑器里直接改的类型
        var editable: Bool { [.text, .richText, .link, .code, .color].contains(self) }
        /// 文本家族：编辑保存后按内容重新识别
        var isTextFamily: Bool { [.text, .link, .code, .color].contains(self) }
    }

    let id: Int64
    let kind: Kind
    /// text/link/code/color = 内容本身；richText = 纯文本版；file = 路径按行；image = 尺寸说明
    let text: String
    /// image 的 PNG 落盘文件名（相对 blobs/）
    let blob: String?
    /// richText 的 RTF 落盘文件名（相对 blobs/）
    let rtf: String?
    let appName: String
    let appBundle: String
    let createdAt: Date
    let pinned: Bool
    let bytes: Int
    let width: Int
    let height: Int
    /// 用户自定义标题；空 = 用正文首行
    let title: String
    /// 附加信息：link = 页面标题；其余留空
    let extra: String

    /// 卡片上显示的名字
    var displayTitle: String {
        if !title.isEmpty { return title }
        switch kind {
        case .image:
            return "图片 \(width)×\(height)"
        case .file:
            let paths = filePaths
            if paths.count == 1 { return paths[0].lastPathComponent }
            return "\(paths.count) 个文件：" + paths.prefix(3).map(\.lastPathComponent).joined(separator: "、")
        case .link:
            return extra.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : extra
        default:
            return Self.firstLine(text)
        }
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        let squashed = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
        return squashed.count > 140 ? String(squashed.prefix(140)) + "…" : String(squashed)
    }

    var filePaths: [String] {
        kind == .file ? text.split(separator: "\n").map(String.init) : []
    }

    var lineCount: Int {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
    }
}

extension String {
    var lastPathComponent: String { (self as NSString).lastPathComponent }
}

/// 从剪贴板抓下来、还没入库的一条。Watcher / Importer 产出，Store 消费；SelfTest 直接造它。
struct Capture: Equatable {
    var kind: ClipItem.Kind
    var text: String
    var imagePNG: Data? = nil
    var rtf: Data? = nil
    var width: Int = 0
    var height: Int = 0
    var appName: String
    var appBundle: String
    var title: String = ""
    var extra: String = ""
}

/// 收藏夹
struct Collection: Identifiable, Hashable {
    let id: Int64
    var name: String
    var color: String   // hex，如 "#2563eb"
    var icon: String    // SF Symbol
    var sortOrder: Int
}
