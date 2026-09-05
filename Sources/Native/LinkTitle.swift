import Foundation

/// 抓链接的页面标题（PastePal 同款）。只 GET 前 256KB，5 秒超时，失败静默。
/// 这是本 app **唯一**的网络访问，可在设置里关掉（默认开）。
enum LinkTitle {
    static func fetch(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.setValue("bytes=0-262143", forHTTPHeaderField: "Range")
        req.setValue("Mozilla/5.0 (Macintosh) Clipbook", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let html = String(decoding: data.prefix(262_144), as: UTF8.self)
        return parseTitle(html)
    }

    static func parseTitle(_ html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: .caseInsensitive),
              let m = re.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        var t = String(html[r])
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        t = t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.isEmpty ? nil : t
    }
}
