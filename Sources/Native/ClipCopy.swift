import AppKit

/// One copy path for the standard Edit menu and user-configured copy shortcuts.
@MainActor
enum ClipCopy {
    @discardableResult
    static func perform(firstResponder: NSResponder?, recordAvailable: Bool,
                        copyRecord: () -> Void) -> Bool {
        if let text = firstResponder as? NSTextView, text.selectedRange().length > 0 {
            text.copy(nil)
            return true
        }
        guard recordAvailable else { return false }
        copyRecord()
        return true
    }
}
