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
            CopyFeedback.completed(success: NSPasteboard.general.changeCount != before, enabled: AppSettings.shared.copySound)
            return true
        }
        guard recordAvailable else { return false }
        copyRecord()
        return true
    }
}

@MainActor
enum CopyFeedback {
    private static let sound = NSSound(named: NSSound.Name("Tink"))
    static func playSystemSound() -> Bool {
        guard let sound else { return false }
        if sound.isPlaying { sound.stop() }
        sound.volume = 0.35
        return sound.play()
    }
    @discardableResult
    static func completed(success: Bool, enabled: Bool, play: (() -> Bool)? = nil) -> Bool {
        guard success, enabled else { return false }
        return (play ?? playSystemSound)()
    }
}
