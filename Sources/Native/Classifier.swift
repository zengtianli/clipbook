import Foundation

/// 文本家族的类型识别（纯函数，Watcher / 编辑保存 / 导入三处共用 —— 判据只写这一份）。
enum Classifier {
    private static let colorRe = try! NSRegularExpression(
        pattern: #"^(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*(?:,\s*[\d.]+\s*)?\))$"#)

    static func isLink(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isWhitespace) else { return false }
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    static func isColor(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return colorRe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    /// 代码：多行，且出现足够多的代码特征（符号 / 关键字 / 缩进）。单行一律不算。
    static func isCode(_ s: String) -> Bool {
        let lines = s.split(whereSeparator: \.isNewline).map { String($0) }
        guard lines.count >= 2 else { return false }
        let indented = lines.filter { $0.hasPrefix("    ") || $0.hasPrefix("\t") }.count
        let tokens = ["{", "}", ";", "=>", "->", "def ", "func ", "fn ", "import ", "#include", "class ", "return ", "</", "<?", "let ", "var ", "const ", "if (", "for (", "while (", "elif ", "SELECT ", "select ", "FROM "]
        let hits = tokens.reduce(0) { $0 + (s.contains($1) ? 1 : 0) }
        let symbolRatio = Double(s.filter { "{}[]();=<>|&$#\\".contains($0) }.count) / Double(max(s.count, 1))
        return hits >= 2 || indented >= 2 || (hits >= 1 && symbolRatio > 0.04)
    }

    /// 文本家族分类（不产 richText / image / file，那三种由数据形态决定）
    static func kind(of text: String) -> ClipItem.Kind {
        if isLink(text) { return .link }
        if isColor(text) { return .color }
        if isCode(text) { return .code }
        return .text
    }
}
