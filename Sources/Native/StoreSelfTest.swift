#if APP_STORE
import AppKit

/// Runs only under a disposable test bundle identity, before NSApplication or any permission request.
@MainActor
enum StoreSelfTest {
    static func run() -> Int32 {
        guard Bundle.main.bundleIdentifier == "test.tianli.clipbook.store" else {
            print("Store self-test requires the disposable test bundle identity")
            return 2
        }
        do {
            let home = ClipStore.defaultHome()
            let container = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] ?? ""
            guard container == "test.tianli.clipbook.store", home.path.contains("/Containers/\(container)/Data/") else {
                print("Not running in the expected App Sandbox: \(home.path)")
                return 1
            }
            let store = try ClipStore(home: home)
            let text = "Store self-test \(UUID().uuidString)"
            let item = try store.ingest(Capture(kind: .text, text: text, appName: "Store self-test", appBundle: container))
            guard try store.item(id: item.id)?.text == text else { return 1 }
            try store.delete(item.id)
            let board = NSPasteboard(name: .init("\(container).store-self-test"))
            defer { board.releaseGlobally() }
            var captured: Capture?
            let watcher = PasteboardWatcher(pasteboard: board) { captured = $0 }
            board.clearContents(); board.setString(text, forType: .string)
            watcher.poll()
            guard captured?.text == text else { return 1 }
            let configuration = ClipPortableConfiguration.make(defaults: .standard)
            let old = UserDefaults.standard.object(forKey: "maxItems")
            defer {
                if let old { UserDefaults.standard.set(old, forKey: "maxItems") }
                else { UserDefaults.standard.removeObject(forKey: "maxItems") }
            }
            UserDefaults.standard.set(700, forKey: "maxItems")
            let file = home.appendingPathComponent("store-settings-test.json")
            defer { try? FileManager.default.removeItem(at: file) }
            try StoreConfigurationTransfer.export(configuration, to: file)
            UserDefaults.standard.set(900, forKey: "maxItems")
            try StoreConfigurationTransfer.import(configuration, from: file)
            guard UserDefaults.standard.integer(forKey: "maxItems") == 700 else { return 1 }
            let configurationDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("TianliApps/Configuration/\(ClipPortableConfiguration.productID)")
            guard FileManager.default.fileExists(atPath: configurationDirectory.appendingPathComponent("pending-import.json").path),
                  !(try FileManager.default.contentsOfDirectory(atPath: configurationDirectory.appendingPathComponent("Backups").path)).isEmpty else {
                return 1
            }
            UserDefaults.standard.synchronize()
            let result: [String: Any] = ["ok": true, "sandbox_container": container,
                "home": NSHomeDirectory(), "store": home.path, "configuration_round_trip": true,
                "clipboard_poll": true,
                "configuration_directory": configurationDirectory.path,
                "cloud_archive": ProductIdentity.cloudSupported,
                "accessibility_preflight": Paster.accessibilityTrusted]
            print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
            return 0
        } catch { print("Store self-test failed: \(error)"); return 1 }
    }
}
#endif
