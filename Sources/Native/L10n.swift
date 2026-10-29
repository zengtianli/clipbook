import Foundation

/// Clip's interface language: English (development language) or Simplified Chinese, following the system.
///
/// View code uses SwiftUI's own localization (`Text("…")`, `Button("…")`) and `String(localized:)` for AppKit
/// titles; `Localizable.xcstrings` keeps the Chinese sentence as the key, with English and Chinese values.
///
/// Sentences produced by the shared core (AppModel status lines, refusals in ClipActions/Shortcuts, Deck import
/// summaries, iCloud archive status) stay Chinese byte for byte: `clip`, runtime-state.json and the acceptance
/// entries read them. The interface shows them through `L10n.display`, which looks the Chinese sentence up in the
/// same catalog: an exact key, or a key with `%@` / `%lld` placeholders matched against the sentence.
enum L10n {
    /// True when the interface is Chinese: the language the bundle resolved, or the system's for a bare executable.
    static let chinese: Bool = {
        let bundled = Bundle.main.localizations.contains { $0 != "Base" }
        let first = (bundled ? Bundle.main.preferredLocalizations : Locale.preferredLanguages).first { $0 != "Base" } ?? "en"
        return first.lowercased().hasPrefix("zh")
    }()

    private static let spec = try! NSRegularExpression(pattern: "%(?:(\\d+)\\$)?(?:lld|ld|d|@)")

    private struct Pattern { let regex: NSRegularExpression; let positions: [Int]; let english: String; let weight: Int }

    /// The English table compiled from the catalog, and every key with placeholders as a matcher.
    private static let table: (exact: [String: String], patterns: [Pattern]) = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let url = Bundle(path: path)?.url(forResource: "Localizable", withExtension: "strings"),
              let strings = NSDictionary(contentsOf: url) as? [String: String] else { return ([:], []) }
        var patterns: [Pattern] = []
        for (key, english) in strings where key.contains("%") {
            let ns = key as NSString
            var regex = "^", last = 0, positions: [Int] = [], index = 0
            for match in spec.matches(in: key, range: NSRange(location: 0, length: ns.length)) {
                regex += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: last, length: match.range.location - last)))
                regex += "(.+?)"
                index += 1
                let explicit = match.range(at: 1).location != NSNotFound ? Int(ns.substring(with: match.range(at: 1))) : nil
                positions.append(explicit ?? index)
                last = match.range.location + match.range.length
            }
            regex += NSRegularExpression.escapedPattern(for: ns.substring(from: last)) + "$"
            if let compiled = try? NSRegularExpression(pattern: regex, options: [.dotMatchesLineSeparators]) {
                patterns.append(Pattern(regex: compiled, positions: positions, english: english, weight: key.count - index * 4))
            }
        }
        // The most specific sentence (most literal text) wins over a general prefix such as "%@：%@".
        patterns.sort { $0.weight > $1.weight }
        return (strings, patterns)
    }()

    /// A Chinese sentence from the shared core in the interface language; unknown text is shown as it is.
    static func display(_ message: String) -> String {
        guard !chinese, !message.isEmpty else { return message }
        if let exact = table.exact[message] { return exact }
        let ns = message as NSString
        for p in table.patterns {
            guard let m = p.regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)) else { continue }
            var values: [Int: String] = [:]
            for (i, position) in p.positions.enumerated() { values[position] = display(ns.substring(with: m.range(at: i + 1))) }
            return fill(p.english, values)
        }
        return LifecycleTextBridge.display(message)
    }

    /// Puts captured values into an English format: `%@`, `%lld`, `%1$@` … all take the captured text.
    private static func fill(_ format: String, _ values: [Int: String]) -> String {
        let ns = format as NSString
        var out = "", last = 0, index = 0
        for match in spec.matches(in: format, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            index += 1
            let explicit = match.range(at: 1).location != NSNotFound ? Int(ns.substring(with: match.range(at: 1))) : nil
            out += values[explicit ?? index] ?? ""
            last = match.range.location + match.range.length
        }
        return (out + ns.substring(from: last)).replacingOccurrences(of: "%%", with: "%")
    }
}

/// Sentences from the shared configuration core (AppConfiguration) that Clip's own catalog does not carry.
enum LifecycleTextBridge {
    static func display(_ message: String) -> String {
        #if APP_STORE
        return message
        #else
        return LifecycleText.display(message)
        #endif
    }
}
