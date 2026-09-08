import AppKit
import Darwin

/// Compiled with baseline/current production sources into an isolated executable.
@MainActor
enum MemoryProbe {
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576 : -1
    }
    static func sample(_ stage: String) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.0))
        print(String(format: "%@: %.1f MiB", stage, footprint()))
        fflush(stdout)
    }
    static func run() -> Int32 {
        guard ProcessInfo.processInfo.environment["CLIPBOOK_HOME"] != nil,
              ProcessInfo.processInfo.environment["CLIPBOOK_PREFERENCES_SUITE"] != nil else { return 2 }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        AppSettings.shared.paused = true
        AppSettings.shared.copySound = false
        AppSettings.shared.fetchLinkTitles = false
        let delegate = AppDelegate(); app.delegate = delegate
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        AppModel.shared.watcher.stop()
        sample("main-window")
        delegate.showSettings(); sample("main-and-settings")
        for window in app.windows where window.isVisible { _ = delegate.windowShouldClose(window) }
        sample("both-closed")
        delegate.showWindow(); AppModel.shared.sidebar = .kind(.image)
        sample("image-grid")
        for page in 0..<min(4, AppModel.shared.pageCount) {
            AppModel.shared.setPage(page); RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        }
        sample("image-pages")
        for window in app.windows where window.isVisible { _ = delegate.windowShouldClose(window) }
        sample("closed-after-images")
        delegate.showWindow(); sample("reopen")
        delegate.shortcuts.suspend()
        return 0
    }
}
