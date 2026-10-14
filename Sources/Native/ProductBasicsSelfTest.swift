#if !APP_STORE
import AppKit
import SwiftUI
import Carbon.HIToolbox
import CryptoKit

/// Real product objects and callbacks, in a disposable bundle/domain. No desktop event is posted.
@MainActor
enum ProductBasicsSelfTest {
    static func run(out: URL) -> Int32 {
        guard let home = AcceptanceReport.isolatedRoot("--product-basics-self-test"),
              Bundle.main.bundleIdentifier?.hasPrefix("test.tianli.clipbook.basics.") == true,
              ProcessInfo.processInfo.environment["APP_LIFECYCLE_SUPPORT_DIR"] != nil,
              let cloudDirectory = ProcessInfo.processInfo.environment["APP_LIFECYCLE_CLOUD_DIR"] else { return 2 }
        let report = AcceptanceReport()
        let fm = FileManager.default
        func wait(_ condition: () -> Bool) -> Bool {
            let until = Date(timeIntervalSinceNow: 12)
            while !condition() && Date() < until { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
            return condition()
        }
        func sync(_ config: AppConfiguration) -> Bool {
            var finished = false; var succeeded = false
            config.reconcile { error in succeeded = error == nil; finished = true }
            return wait { finished } && succeeded
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func command(_ arguments: [String]) -> (Int32, [String: Any]) {
            let process = Process(); let pipe = Pipe()
            process.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/clip")
            process.arguments = arguments + ["--json"]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return (-1, [:]) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (process.terminationStatus, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
        }
        do {
            try fm.createDirectory(at: out, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: cloudDirectory, withIntermediateDirectories: true)
            let defaults = AppPreferences.defaults
            defaults.set(false, forKey: "copySound")
            defaults.set(700, forKey: "maxItems"); defaults.set(7, forKey: "retentionDays")
            let delegate = AppDelegate()
            let mainWindow = delegate.prepareBasicsWindow()
            defer { delegate.shortcuts.suspend(); mainWindow.close() }
            delegate.installLifecycle()
            guard let configuration = delegate.configuration else { return 1 }
            let model = AppModel.shared!
            let item = try model.store.ingest(Capture(kind: .text, text: "basics preserved business record", appName: "Test", appBundle: "test"))
            model.reload(); model.selection = [item.id]
            // Native SettingsView is the user's actual view. Never order this window.
            let settingsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            settingsWindow.contentView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings, shortcuts: delegate.shortcuts))
            settingsWindow.contentView?.layoutSubtreeIfNeeded()
            defer { settingsWindow.close() }
            AppLifecycleUI.install(name: "Clip", configuration: configuration, updateSource: .privateCloud(channel: "basics"), startConfiguration: false)
            let snapshot = try AppLifecycleUI.shared.offscreenSnapshot(to: out.appendingPathComponent("settings.png"), showingUpdateOptions: true)
            report.check(snapshot.values.allSatisfy { $0 } && !settingsWindow.isVisible, "settings.real_views_offscreen")
            let switches = NSApp.windows.flatMap { $0.contentView.map(descendants) ?? [] }.compactMap { $0 as? NSSwitch }
            let updateSwitch = switches.first { $0.action.map(NSStringFromSelector) == "changedUpdateOption:" }
            let cloudSwitch = switches.first { $0.action.map(NSStringFromSelector) == "toggleCloud" }
            if let control = updateSwitch, let action = control.action {
                control.state = .on
                _ = NSApp.sendAction(action, to: control.target, from: control)
            }
            let readOptions = command(["update", "options"])
            let options = readOptions.1["options"] as? [String: Any]
            report.check(updateSwitch != nil && options?["automaticCheck"] as? Bool == true, "settings.interaction")
            let stored = command(["settings"])
            report.check(readOptions.0 == 0 && (stored.1["settings"] as? [String: Any])?["maxItems"] as? Int == 700, "settings.persisted_readback")
            let beforeImport = try configuration.exportData()
            do { try configuration.importData(Data("{bad".utf8)); report.check(false, "settings.error_preserves_data") }
            catch { report.check(try configuration.exportData() == beforeImport, "settings.error_preserves_data") }

            let key = ClipKey(code: UInt32(kVK_F20), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), key: "F20")
            let binding = ClipBinding(chord: key, scope: .application)
            let paused = model.settings.paused
            let seeded = delegate.shortcuts.set(.pause, to: binding)
            let acted = delegate.shortcuts.handleLocal(key)
            report.check(seeded && acted && model.settings.paused != paused && model.watcher.paused == model.settings.paused, "shortcuts.action_path")
            _ = delegate.shortcuts.set(.pause, to: nil)
            let disabled = !delegate.shortcuts.handleLocal(key)
            _ = delegate.shortcuts.set(.pause, to: binding)
            let freshKeys = command(["shortcut", "list"])
            let restored = delegate.shortcuts.handleLocal(key) && model.settings.paused == paused
            let rows = freshKeys.1["shortcuts"] as? [[String: Any]] ?? []
            report.check(disabled && restored && rows.contains { $0["action"] as? String == "pause" && $0["keys"] as? String == key.label }, "shortcuts.disable_restore")
            let bindingsBefore = defaults.data(forKey: ClipShortcuts.storageKey)
            let duplicate = !delegate.shortcuts.set(.search, to: binding)
            let reserved = ClipKey(code: 9, modifiers: UInt32(cmdKey | shiftKey), key: "V")
            report.check(duplicate && !delegate.shortcuts.set(.search, to: .init(chord: reserved, scope: .application)) && defaults.data(forKey: ClipShortcuts.storageKey) == bindingsBefore, "shortcuts.conflict_or_reserved_keys")

            // Enable via the actual native switch, then receive a coordinated remote write.
            if let control = cloudSwitch, let action = control.action {
                control.state = .on; _ = NSApp.sendAction(action, to: control.target, from: control)
            }
            let cloud = URL(fileURLWithPath: cloudDirectory).appendingPathComponent(ClipPortableConfiguration.productID + ".json")
            let pushed = cloudSwitch != nil && configuration.enabled && sync(configuration) && fm.fileExists(atPath: cloud.path)
            var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: cloud)) as! [String: Any]
            var values = envelope["values"] as! [String: Any]
            guard let maxKey = values.keys.first(where: { $0.hasSuffix("maxItems") }) else { return 1 }
            values[maxKey] = 900; envelope["values"] = values
            let remote = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            var wrote = false
            DispatchQueue.global().async {
                var error: NSError?
                NSFileCoordinator().coordinate(writingItemAt: cloud, options: .forReplacing, error: &error) { url in try? remote.write(to: url, options: .atomic) }
                DispatchQueue.main.async { wrote = error == nil }
            }
            let received = wait { wrote && defaults.integer(forKey: "maxItems") == 900 && model.settings.maxItems == 900 }
            report.check(pushed && received, "icloud.push_pull")
            unsetenv("APP_LIFECYCLE_CLOUD_DIR")
            let localBefore = try configuration.exportData()
            let failedUnavailable = !sync(configuration)
            report.check(try failedUnavailable && configuration.status.contains("未完成") && configuration.exportData() == localBefore && model.store.item(id: item.id)?.text == item.text, "icloud.unavailable_local_fallback")
            setenv("APP_LIFECYCLE_CLOUD_DIR", cloudDirectory, 1)
            try Data("{broken remote".utf8).write(to: cloud, options: .atomic)
            let bad = !sync(configuration)
            let kept = try configuration.exportData() == localBefore
            try remote.write(to: cloud, options: .atomic)
            let recovered = sync(configuration)
            report.check(bad && kept && recovered && defaults.integer(forKey: "maxItems") == 900, "icloud.conflict_or_corrupt_recovery")
            let localSaved = try configuration.exportData(), cloudSaved = try Data(contentsOf: cloud)
            configuration.setEnabled(false)
            report.check(try !configuration.enabled && configuration.exportData() == localSaved && Data(contentsOf: cloud) == cloudSaved && model.store.item(id: item.id)?.text == item.text, "icloud.disable_preserves_data")

            let bid = Bundle.main.bundleIdentifier!
            let feedDir = URL(fileURLWithPath: cloudDirectory).appendingPathComponent("TianliApps/Updates/\(bid)/basics")
            try fm.createDirectory(at: feedDir, withIntermediateDirectories: true)
            let feed = feedDir.appendingPathComponent("release.json")
            let archive = feedDir.appendingPathComponent("Clip.zip")
            let archiveData = Data("isolated update preview".utf8)
            try archiveData.write(to: archive)
            let archiveHash = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
            let release: [String: Any] = ["bundle_id": bid, "channel": "basics", "version": "99.0", "build": "999", "filename": "Clip.zip", "sha256": archiveHash, "size_bytes": archiveData.count]
            let validFeed = try JSONSerialization.data(withJSONObject: release)
            try validFeed.write(to: feed)
            func lifecycle(_ words: [String]) -> (Int32, [String: Any]) {
                var output: [String] = []
                var product = AppLifecycleCLI.Product(command: "clip", name: "Clip", configuration: configuration, updateSource: .privateCloud(channel: "basics"))
                product.out = { output.append($0) }; product.err = { _ in }; product.runningApp = { [] }
                let code = AppLifecycleCLI.run(words + ["--json"], product: product)
                let json = (try? JSONSerialization.jsonObject(with: Data(output.joined().utf8))) as? [String: Any] ?? [:]
                return (code, json)
            }
            AppLifecycleUI.shared.checkForUpdates(present: false)
            let uiUpdated = wait {
                NSApp.windows.flatMap { $0.contentView.map(descendants) ?? [] }.compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("有新版 99.0") }
            }
            let checked = lifecycle(["update", "check"])
            report.check(uiUpdated && checked.0 == 0 && checked.1["update_available"] as? Bool == true && (checked.1["latest"] as? [String: Any])?["version"] as? String == "99.0", "updates.check_result")
            try Data("{bad feed".utf8).write(to: feed)
            let failedFeed = lifecycle(["update", "check"])
            try fm.removeItem(at: feed)
            let missingFeed = lifecycle(["update", "check"])
            try validFeed.write(to: feed)
            report.check(failedFeed.0 != 0 && missingFeed.0 != 0 && lifecycle(["update", "check"]).0 == 0, "updates.failure_recovery")
            let savedOptions = command(["update", "options", "--auto-check", "on", "--interval", "6", "--yes"])
            let optionsRead = command(["update", "options"])
            let optionValues = optionsRead.1["options"] as? [String: Any]
            let badInterval = command(["update", "options", "--interval", "0", "--yes"])
            report.check(savedOptions.0 == 0 && optionsRead.0 == 0 && optionValues?["intervalHours"] as? Int == 6 && optionValues?["automaticCheck"] as? Bool == true && badInterval.0 != 0, "updates.options_or_store_entry")
            let businessBefore = try model.store.item(id: item.id)
            let preferencesBefore = try configuration.exportData()
            let preview = lifecycle(["update", "install", "--yes", "--dry-run"])
            report.check(try preview.0 == 0 && preview.1["dry_run"] as? Bool == true && configuration.exportData() == preferencesBefore && model.store.item(id: item.id) == businessBefore, "updates.data_preservation", "preview=\(preview)")
            report.check(!mainWindow.isVisible && !settingsWindow.isVisible && NSApp.activationPolicy() == .prohibited, "settings.no_screen_or_dock")
            let payload: [String: Any] = ["checks": Dictionary(uniqueKeysWithValues: report.checks.map { ($0.0, $0.1) }), "cloud_scope": "Isolated shared configuration engine; Apple server/device transfer not tested", "home": home.path]
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .prettyPrinted]).write(to: out.appendingPathComponent("checks.json"))
        } catch { report.check(false, "settings.unexpected_error", String(describing: error)) }
        return report.finish()
    }
}
#endif
