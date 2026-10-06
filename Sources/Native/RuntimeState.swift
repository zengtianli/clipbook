import AppKit
import Combine
import Foundation

/// What only the running app knows, published for `clip` to read: whether Accessibility is granted (a command-line
/// process would see its terminal's grant, not Clip's), whether each global shortcut registered, and the live iCloud
/// sync status. One small file in the data dir, rewritten only when a fact changes. `clip` trusts the shortcut and
/// iCloud parts only while the pid that wrote them is still a running Clip; the Accessibility grant is a system
/// setting, so its last reported value stays useful and carries its time.
struct ClipRuntimeState: Codable, Equatable {
    struct Shortcut: Codable, Equatable { var keys: String; var registered: Bool; var status: String }
    struct Cloud: Codable, Equatable { var syncStatus: String; var archiveStatus: String; var error: String?; var busy: Bool }
    var pid: Int32
    var updatedAt: Date
    var accessibilityTrusted: Bool
    /// Global bindings only, by action.
    var shortcuts: [String: Shortcut]
    /// nil until the app has opened its iCloud archive (设置 → iCloud, or the archive switched on).
    var cloud: Cloud?

    static func url(home: URL) -> URL { home.appendingPathComponent("runtime-state.json") }

    static func read(home: URL) -> ClipRuntimeState? {
        guard let data = try? Data(contentsOf: url(home: home)) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ClipRuntimeState.self, from: data)
    }

    func sameFacts(as other: ClipRuntimeState) -> Bool {
        var mine = self; mine.updatedAt = other.updatedAt
        return mine == other
    }

    func write(home: URL) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.url(home: home), options: .atomic)
    }
}

/// Owned by the running app. Re-reads the three facts when the shortcut centre or the iCloud archive changes and
/// when the app becomes active (the Accessibility grant is changed in System Settings), and writes on a difference.
@MainActor
final class ClipRuntimePublisher {
    private let home: URL
    private let shortcuts: ClipShortcuts
    private let trusted: () -> Bool
    private let cloud: () -> MacClipSync?
    private var subscriptions: Set<AnyCancellable> = []
    private var cloudSubscriptions: Set<AnyCancellable> = []
    private weak var observedCloud: MacClipSync?
    private var last: ClipRuntimeState?

    init(home: URL, shortcuts: ClipShortcuts, trusted: @escaping () -> Bool = { Paster.accessibilityTrusted },
         cloud: @escaping () -> MacClipSync? = { nil }) {
        self.home = home; self.shortcuts = shortcuts; self.trusted = trusted; self.cloud = cloud
        shortcuts.objectWillChange.debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.publish() } }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification).receive(on: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.publish() } }.store(in: &subscriptions)
        publish()
    }

    func snapshot() -> ClipRuntimeState {
        var keys: [String: ClipRuntimeState.Shortcut] = [:]
        for action in ClipAction.allCases {
            guard let binding = shortcuts.binding(action), binding.scope == .global else { continue }
            keys[action.rawValue] = .init(keys: binding.chord.label, registered: shortcuts.isRegistered(action), status: shortcuts.status(action))
        }
        let sync = cloud()
        let archive = sync.map { ClipRuntimeState.Cloud(syncStatus: $0.library.syncStatus, archiveStatus: $0.status, error: $0.library.error, busy: $0.busy) }
        return ClipRuntimeState(pid: ProcessInfo.processInfo.processIdentifier, updatedAt: Date(), accessibilityTrusted: trusted(),
                                shortcuts: keys, cloud: archive)
    }

    func publish() {
        if let sync = cloud(), observedCloud !== sync {
            observedCloud = sync; cloudSubscriptions = []
            for change in [sync.objectWillChange.eraseToAnyPublisher(), sync.library.objectWillChange.eraseToAnyPublisher()] {
                change.debounce(for: .milliseconds(500), scheduler: RunLoop.main)
                    .sink { [weak self] _ in MainActor.assumeIsolated { self?.publish() } }.store(in: &cloudSubscriptions)
            }
        }
        let state = snapshot()
        if let last, last.sameFacts(as: state) { return }
        // Never create the data dir: the store already did when the app opened its library.
        guard FileManager.default.fileExists(atPath: home.path) else { return }
        state.write(home: home)
        last = state
    }
}
