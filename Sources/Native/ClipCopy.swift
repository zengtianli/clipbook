import AppKit

/// One copy path for the standard Edit menu and user-configured copy shortcuts.
@MainActor
enum ClipCopy {
    @discardableResult
    static func perform(firstResponder: NSResponder?, recordAvailable: Bool,
                        copyRecord: () -> Void) -> Bool {
        if let text = firstResponder as? NSTextView, text.selectedRange().length > 0 {
            let before = NSPasteboard.general.changeCount
            text.copy(nil)
            CopyFeedback.completed(success: NSPasteboard.general.changeCount != before, enabled: AppSettings.shared.copySound,
                                   changeCount: NSPasteboard.general.changeCount)
            return true
        }
        guard recordAvailable else { return false }
        copyRecord()
        return true
    }
}

@MainActor
enum CopyFeedback {
    static let soundNames: [String] = ((try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? [])
        .filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
    private static var currentSound: NSSound?
    private static var lastChangeCount: Int?
    private(set) static var lastPlayedAt: Date?
    static func playSystemSound() -> Bool {
        currentSound?.stop()
        guard let sound = NSSound(named: NSSound.Name(AppSettings.shared.copySoundName)) else { return false }
        sound.volume = Float(AppSettings.shared.copySoundVolume)
        currentSound = sound
        let played = sound.play()
        if played { lastPlayedAt = Date() }
        return played
    }
    @discardableResult
    static func completed(success: Bool, enabled: Bool, changeCount: Int? = nil, play: (() -> Bool)? = nil) -> Bool {
        guard success, enabled else { return false }
        if let changeCount {
            guard lastChangeCount != changeCount else { return false }
            lastChangeCount = changeCount
        }
        return (play ?? playSystemSound)()
    }
}
