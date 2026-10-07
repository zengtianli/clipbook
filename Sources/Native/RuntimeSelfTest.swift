import AppKit
import Carbon.HIToolbox
import Foundation

/// `Clipbook --runtime-self-test` (opt-in, run by tests/test-runtime.sh on a built or installed Clip.app).
///
/// This process is the running Clip: the production `AppDelegate` with its two wiring methods (`installLifecycle`,
/// `connectCommandLine`), activation policy `.prohibited`, so no Dock icon, no status item, no window, no focus
/// change. Beside it the real `clip` command (the in-bundle link) runs as separate processes, and every verdict
/// is read back by yet another `clip` process: what another process finds stored, not this app's own reading.
///
/// It covers what only a running app can answer (Accessibility grant, global-key registration, the iCloud status
/// line) and two commands sent back to back, where a running app that stored its own stale reading would undo the
/// second one. Isolated data dir, preferences suite and 配置与更新 directories; the pasteboard watcher is never
/// started and iCloud is never switched on. It registers test hot keys (⌃⌥⇧⌘F20 / F19 / F18) for a few seconds,
/// which is why it is not part of `--selftest`.
@MainActor
enum RuntimeSelfTest {
    struct Answer {
        let code: Int32
        let json: [String: Any]
    }

    private static var command: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/clip") }
    private static var scratch = FileManager.default.temporaryDirectory
    private static var spawned = 0
    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Keeps the main run loop turning, as it does in the running app. Timed by uptime so a sleeping Mac cannot fail it.
    static func settle(_ seconds: TimeInterval) {
        let deadline = now + seconds
        while now < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02)) }
    }

    /// `clip <args>` as its own process, to completion. The app side keeps receiving notifications meanwhile.
    static func clip(_ args: String...) -> Answer { clip(args) }
    static func clip(_ args: [String]) -> Answer {
        spawned += 1
        let out = scratch.appendingPathComponent("clip-\(spawned).out")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: out) else { return Answer(code: -1, json: [:]) }
        defer { try? handle.close(); try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = command
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return Answer(code: -1, json: [:]) }
        let deadline = now + 30
        while process.isRunning && now < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
        guard !process.isRunning else { process.terminate(); return Answer(code: -2, json: [:]) }
        let data = (try? Data(contentsOf: out)) ?? Data()
        return Answer(code: process.terminationStatus, json: ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:])
    }

    /// Fresh-process reads until one satisfies `condition`, or the deadline.
    static func until(_ seconds: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = now + seconds
        while now < deadline {
            if condition() { return true }
            settle(0.05)
        }
        return condition()
    }

    /// Fresh-process reads for `seconds`, starting at once: every one of them must satisfy `condition`.
    static func holds(_ seconds: TimeInterval = 1.5, _ condition: () -> Bool) -> (ok: Bool, samples: Int) {
        let deadline = now + seconds
        var samples = 0
        repeat {
            samples += 1
            if !condition() { return (false, samples) }
            settle(0.02)
        } while now < deadline
        return (true, samples)
    }

    // What another process finds stored.
    static func row(_ action: String) -> [String: Any]? {
        (clip("shortcut", "list", "--json").json["shortcuts"] as? [[String: Any]])?.first { $0["action"] as? String == action }
    }
    static func registration(_ action: String) -> String? { row(action)?["registration"] as? String }
    static func scope(_ action: String) -> String? { row(action)?["scope"] as? String }
    static func paused() -> Bool? { (clip("status", "--json").json["recording"] as? [String: Any])?["paused"] as? Bool }
    static func maxItems() -> Int? { (clip("settings", "--json").json["settings"] as? [String: Any])?["maxItems"] as? Int }
    static func syncEnabled() -> Bool? { clip("config", "status", "--json").json["sync_enabled"] as? Bool }
    static func grant() -> [String: Any]? {
        (clip("status", "--json").json["permissions"] as? [String: Any])?["accessibility"] as? [String: Any]
    }

    static func run() -> Int32 {
        let report = AcceptanceReport()
        guard let home = AcceptanceReport.isolatedRoot("--runtime-self-test") else { return 2 }
        let fm = FileManager.default
        // 配置与更新 keeps its marker, backups and "cloud" copy inside the isolated data dir: never the user's Application
        // Support, never iCloud Drive. Set before the configuration exists; the `clip` processes inherit it.
        let lifecycle = home.appendingPathComponent("Lifecycle", isDirectory: true)
        let cloudCopy = lifecycle.appendingPathComponent("cloud/\(ClipPortableConfiguration.productID).json")
        setenv("APP_LIFECYCLE_SUPPORT_DIR", lifecycle.appendingPathComponent("support").path, 1)
        setenv("APP_LIFECYCLE_CLOUD_DIR", lifecycle.appendingPathComponent("cloud").path, 1)
        scratch = home.appendingPathComponent("runtime-self-test", isDirectory: true)
        try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        report.notCovered = [
            "本人日常运行的 Clip 实例（由系统启动，带窗口、Dock 与菜单栏图标）：这里是同一个可执行文件、同一套接线方法，但不上屏",
            "辅助功能授权归谁：从终端直接启动的进程，系统按启动它的那个 App 的授权回答；Clip 自己的授权要由系统启动的 Clip 报告",
            "iCloud 历史归档开着时由真实同步产生的状态文字（正在同步…、最近同步、同步错误）：要真实 iCloud 账户；这里验的是关闭状态那一句，以及归档对象上的状态变了之后命令读到新值（变化是自检直接改的）",
            "「使用 iCloud 记住配置」写真实 iCloud Drive：这里的云端副本是隔离目录里的文件；另一台设备同时改了云端配置时的合并没有验",
            "配置同步开着时 App 改设置后的再同步：隔离偏好域下各处拿到的不是同一个 UserDefaults 对象，这个触发不会发生（结果里的 cloud_copy_followed_last_value 记下本次有没有发生），所以再同步与命令写入的交错没有覆盖",
            "设置窗口与「配置与更新…」窗口里控件的显示：没有构造窗口，核对的是窗口读的同一个对象上的状态文字",
            "App 被激活时重读授权（.prohibited 的进程不会被激活）",
            "同步历史的收藏 / 取消收藏 / 删除经 iCloud 到达 iPhone / iPad：要真实 iCloud 账户；这里验的是这台 Mac 上那份归档被运行中的 App 改写、另起进程读回",
            "clip start 真的启动、clip quit 真的退出：这个进程已经是运行中的 Clip，只验「已在运行不再启动」与 quit --dry-run；真实的启动与退出在 tests/test-start.sh",
        ]
        guard fm.fileExists(atPath: command.path) else {
            report.check(false, "包内有 clip 命令入口", command.path)
            return report.finish()
        }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        var evidence: [String: Any] = ["pid": me, "executable": Bundle.main.executablePath ?? "", "home": home.path,
                                       "preferences_domain": AppPreferences.domain]
        var samples: [String: Int] = [:]

        // Nothing has been published yet: the command must not guess.
        let unpublished = grant()
        report.check(unpublished?["trusted"] is NSNull && unpublished?["as_of"] is NSNull,
                     "App 还没报告时 permissions.accessibility.trusted 为 null（不猜）")

        // Two recorded combinations, both 仅 Clip 内 (commands never add a combination; recording needs a person).
        // ⌃⌥⇧⌘F19 is already held by this process, standing in for a combination the system will refuse.
        let all = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let freeKey = ClipKey(code: UInt32(kVK_F20), modifiers: all, key: "F20")
        let takenKey = ClipKey(code: UInt32(kVK_F19), modifiers: all, key: "F19")
        let defaults = AppPreferences.defaults
        let seeded = ["toggleWindow": ClipBinding(chord: freeKey, scope: .application), "pause": ClipBinding(chord: takenKey, scope: .application)]
        defaults.set(try? JSONEncoder().encode(seeded), forKey: ClipShortcuts.storageKey)
        _ = defaults.synchronize()
        let holder = CarbonClipKeys()
        let held = holder.register(takenKey, id: 9001)
        defer { holder.unregister(9001) }

        // The running app: production delegate, production wiring. No watcher, no status item, no window, no iCloud start.
        let delegate = AppDelegate()
        delegate.installLifecycle()
        delegate.connectCommandLine()
        defer { delegate.shortcuts.suspend() }
        settle(0.3)

        // 1. The command recognises this process as the running Clip and reads the grant it published.
        let status = clip("status", "--json")
        let gui = status.json["gui"] as? [String: Any]
        let pids = (gui?["pids"] as? [Int]) ?? []
        report.check(status.code == 0 && gui?["running"] as? Bool == true && pids.contains(me),
                     "clip 认出这个进程是运行中的 Clip", "pids=\(pids) 本进程=\(me)")
        let asked = Paster.accessibilityTrusted
        let published = ClipRuntimeState.read(home: home)
        let live = (status.json["permissions"] as? [String: Any])?["accessibility"] as? [String: Any]
        let grantMatches = live?["trusted"] as? Bool == asked && published?.accessibilityTrusted == asked && published.map { Int($0.pid) } == me
        report.check(grantMatches && live?["live"] as? Bool == true && live?["as_of"] is String,
                     "status 的 permissions.accessibility 读到运行中的 App 向系统问到的结果",
                     "trusted=\(String(describing: live?["trusted"])) App 问到=\(asked)")
        evidence["accessibility"] = ["trusted": asked, "as_of": live?["as_of"] as? String ?? ""]
        // `clip start` / `clip quit` against a Clip that is already running: start does nothing, quit names this process.
        let again = clip("start", "--json")
        let wouldQuit = clip("quit", "--dry-run", "--json")
        report.check(again.code == 0 && again.json["started"] as? Bool == false && again.json["already_running"] as? Bool == true
                     && again.json["ready"] as? Bool == true && ((again.json["pids"] as? [Int]) ?? []).contains(me),
                     "start 在 Clip 已运行时不再启动，报告它已就绪", "pids=\(String(describing: again.json["pids"]))")
        report.check(wouldQuit.code == 0 && wouldQuit.json["would_quit"] as? Bool == true && wouldQuit.json["pids"] as? [Int] == [me],
                     "quit --dry-run 认出要退出的是使用这个数据目录的 Clip（本进程），不发退出请求", "pids=\(String(describing: wouldQuit.json["pids"]))")

        // 2. Global-key registration: the system accepts one combination and refuses the other.
        report.check(held == noErr, "测试前提：本进程先占住 \(takenKey.label)", "OSStatus \(held)")
        report.check(registration("toggleWindow") == "not_needed" && !delegate.shortcuts.isRegistered(.toggleWindow),
                     "仅 Clip 内的组合键：registration 为 not_needed，App 没有向系统注册")
        let widen = clip("shortcut", "scope", "toggleWindow", "global", "--json")
        let registered = until { registration("toggleWindow") == "registered" }
        let liveRow = row("toggleWindow")
        let sameSentence = liveRow?["status"] as? String == delegate.shortcuts.status(.toggleWindow)
        report.check(widen.code == 0 && registered && sameSentence && liveRow?["keys"] as? String == freeKey.label
                     && delegate.shortcuts.isRegistered(.toggleWindow),
                     "shortcut scope … global：运行中的 App 向系统注册成功，shortcut list 读到 registered 与窗口里那句话",
                     "\(String(describing: liveRow?["registration"])) · \(String(describing: liveRow?["status"]))")
        let refuse = clip("shortcut", "scope", "pause", "global", "--json")
        let failed = until { registration("pause") == "failed" }
        let failedRow = row("pause")
        let failedSentence = failedRow?["status"] as? String ?? ""
        report.check(refuse.code == 0 && failed && failedSentence.contains("系统拒绝注册") && failedSentence == delegate.shortcuts.status(.pause)
                     && !delegate.shortcuts.isRegistered(.pause) && registration("toggleWindow") == "registered",
                     "系统拒绝注册时 shortcut list 读到 failed 与窗口里的提示，另一个全局键仍是 registered",
                     "\(String(describing: failedRow?["registration"])) · \(failedSentence)")
        evidence["shortcuts"] = ["registered": ["keys": freeKey.label, "status": liveRow?["status"] as? String ?? ""],
                                 "failed": ["keys": takenKey.label, "status": failedSentence]]

        // 2b. shortcut set: a chord written out and an action named. Another process stores it through the window's own
        // save; this running app re-reads and registers it. Then the conflict refusal, and clear unregisters it.
        let setKey = ClipKey(code: UInt32(kVK_F18), modifiers: all, key: "F18")
        let set = clip("shortcut", "set", "pin", "ctrl+opt+shift+cmd+f18", "--scope", "global", "--json")
        let setLive = until { registration("pin") == "registered" }
        let setRow = row("pin")
        report.check(set.code == 0 && set.json["changed"] as? Bool == true && setLive && setRow?["keys"] as? String == setKey.label
                     && delegate.shortcuts.binding(.pin) == ClipBinding(chord: setKey, scope: .global) && delegate.shortcuts.isRegistered(.pin)
                     && setRow?["status"] as? String == delegate.shortcuts.status(.pin),
                     "shortcut set … --scope global：运行中的 App 读到写出来的组合键并向系统注册成功，shortcut list 读到 registered",
                     "\(String(describing: setRow?["keys"])) · \(String(describing: setRow?["status"]))")
        let clash = clip("shortcut", "set", "search", freeKey.label, "--json")
        let clashWith = clash.json["conflict"] as? [String: Any]
        settle(0.5)
        report.check(clash.code == 2 && clash.json["error"] as? String == "conflict" && clashWith?["action"] as? String == "toggleWindow"
                     && clashWith?["keys"] as? String == freeKey.label && delegate.shortcuts.binding(.search) == nil && row("search")?["keys"] is NSNull,
                     "shortcut set 给出已被另一个动作占用的组合键：退出 2、conflict 写明被谁占用，运行中的 App 的绑定不变",
                     clash.json["message"] as? String ?? "")
        let unset = clip("shortcut", "clear", "pin", "--json")
        let unsetLive = until { !delegate.shortcuts.isRegistered(.pin) && row("pin")?["keys"] is NSNull }
        report.check(unset.code == 0 && unsetLive && delegate.shortcuts.binding(.pin) == nil, "shortcut clear：运行中的 App 注销 set 设的全局键")
        evidence["shortcut_set"] = ["keys": setKey.label, "status": setRow?["status"] as? String ?? "", "conflict": clash.json["message"] as? String ?? ""]

        // 3. Two commands back to back. The second one's value must be what other processes read from the moment it
        // returns, and must stay; the app must end up on it too. Run with 配置同步 off, then again with it on.
        func backToBack(_ label: String) {
            // Scope: … application, then at once … global.
            let a1 = clip("shortcut", "scope", "toggleWindow", "application", "--json")
            let a2 = clip("shortcut", "scope", "toggleWindow", "global", "--json")
            let globalHeld = holds { scope("toggleWindow") == "global" }
            settle(0.8)
            let liveAgain = until { registration("toggleWindow") == "registered" }
            let liveHeld = holds { registration("toggleWindow") == "registered" }
            samples["\(label)·scope→global"] = globalHeld.samples + liveHeld.samples
            report.check(a1.code == 0 && a2.code == 0 && globalHeld.ok && liveAgain && liveHeld.ok
                         && delegate.shortcuts.binding(.toggleWindow)?.scope == .global && delegate.shortcuts.isRegistered(.toggleWindow),
                         "\(label)：背靠背 scope application → global，另起进程一直读到 global，全局键最终已注册并保持",
                         "读回 \(globalHeld.samples)+\(liveHeld.samples) 次")
            // … global, then at once … application (from application).
            _ = clip("shortcut", "scope", "toggleWindow", "application", "--json")
            _ = until { !delegate.shortcuts.isRegistered(.toggleWindow) }
            let b1 = clip("shortcut", "scope", "toggleWindow", "global", "--json")
            let b2 = clip("shortcut", "scope", "toggleWindow", "application", "--json")
            let localHeld = holds { scope("toggleWindow") == "application" }
            settle(0.8)
            let reported = ClipRuntimeState.read(home: home)?.shortcuts["toggleWindow"]
            samples["\(label)·scope→application"] = localHeld.samples
            report.check(b1.code == 0 && b2.code == 0 && localHeld.ok && reported == nil
                         && delegate.shortcuts.binding(.toggleWindow)?.scope == .application && !delegate.shortcuts.isRegistered(.toggleWindow),
                         "\(label)：背靠背 scope global → application，另起进程一直读到 application，App 最终没有注册全局键",
                         "读回 \(localHeld.samples) 次")
            _ = clip("shortcut", "scope", "toggleWindow", "global", "--json")
            _ = until { registration("toggleWindow") == "registered" }

            // 暂停记录: pause then at once resume, and the reverse.
            let p1 = clip("pause", "--json"), p2 = clip("resume", "--json")
            let resumed = holds { paused() == false }
            settle(0.3)
            let appResumed = !AppSettings.shared.paused && !AppModel.shared.watcher.paused
            _ = clip("pause", "--json")
            _ = until { AppSettings.shared.paused }
            let r1 = clip("resume", "--json"), r2 = clip("pause", "--json")
            let pausedHeld = holds { paused() == true }
            settle(0.3)
            let appPaused = AppSettings.shared.paused && AppModel.shared.watcher.paused
            samples["\(label)·pause"] = resumed.samples + pausedHeld.samples
            report.check(p1.code == 0 && p2.code == 0 && r1.code == 0 && r2.code == 0 && resumed.ok && appResumed && pausedHeld.ok && appPaused,
                         "\(label)：背靠背 pause → resume 与 resume → pause，另起进程一直读到后一条的值，App 跟到同一个值",
                         "读回 \(resumed.samples)+\(pausedHeld.samples) 次")
            _ = clip("resume", "--json")
            _ = until { !AppSettings.shared.paused }

            // 最多保留 N 条: two values back to back.
            let m1 = clip("settings", "set", "maxItems", "1111", "--json"), m2 = clip("settings", "set", "maxItems", "2222", "--json")
            let kept = holds { maxItems() == 2222 }
            settle(0.3)
            samples["\(label)·maxItems"] = kept.samples
            report.check(m1.code == 0 && m2.code == 0 && kept.ok && AppSettings.shared.maxItems == 2222 && AppModel.shared.store.maxItems == 2222,
                         "\(label)：背靠背 settings set maxItems 1111 → 2222，另起进程一直读到 2222，App 用上 2222", "读回 \(kept.samples) 次")
        }
        report.check(syncEnabled() == false && delegate.configuration?.enabled == false, "「使用 iCloud 记住配置」起始为关")
        backToBack("配置同步关")

        // 4. 配置与更新: export, import (the app re-reads), then the switch, asked of the running app.
        let exported = scratch.appendingPathComponent("config.json")
        let baseline = clip("settings", "set", "maxItems", "4321", "--json")
        let export = clip("config", "export", "-o", exported.path, "--json")
        let i1 = clip("settings", "set", "maxItems", "1234", "--json"), i2 = clip("config", "import", exported.path, "--yes", "--json")
        let restored = holds { maxItems() == 4321 }
        settle(0.3)
        samples["import"] = restored.samples
        report.check(baseline.code == 0 && export.code == 0 && i1.code == 0 && i2.code == 0 && restored.ok
                     && AppSettings.shared.maxItems == 4321 && AppModel.shared.store.maxItems == 4321,
                     "背靠背 settings set → config import：另起进程一直读到导入的值，运行中的 App 重读到它", "读回 \(restored.samples) 次")

        let on = clip("config", "sync", "on", "--yes", "--json")
        let turnedOn = until { syncEnabled() == true }
        let wroteCopy = until(4) { fm.fileExists(atPath: cloudCopy.path) }
        report.check(on.code == 0 && on.json["requested"] as? Bool == true && turnedOn && delegate.configuration?.enabled == true && wroteCopy,
                     "config sync on：运行中的 App 打开开关并写出云端副本（隔离目录），config status 读到开")
        // The sentence under the window's switch: the app records what it shows, `config status` reads it as sync_status.
        func sentence() -> [String: Any]? { clip("config", "status", "--json").json["sync_status"] as? [String: Any] }
        let shown = until { sentence()?["from"] as? String == "app" && sentence()?["text"] as? String == delegate.configuration?.status }
        let shownNow = sentence()
        report.check(shown && shownNow?["live"] as? Bool == true && shownNow?["at"] is String,
                     "config status 的 sync_status 读到运行中的 App 开关下面此刻那句话", shownNow?["text"] as? String ?? "nil")
        evidence["config_sync_status"] = shownNow?["text"] as? String ?? ""
        let refused = clip("config", "import", exported.path, "--yes", "--json")
        report.check(refused.code == 4 && refused.json["error"] as? String == "sync_enabled" && maxItems() == 4321,
                     "配置同步开着时 config import 退出 4（由运行中的 App 负责），设置不变")
        backToBack("配置同步开")
        // Observation, not a verdict. In the app every part shares UserDefaults.standard, so the app's own re-read of a
        // changed setting makes the configuration sync again; an isolated suite hands each part its own UserDefaults
        // object and that trigger does not fire. Recorded so the report can say which of the two this run was.
        settle(1.0)
        let copy = (try? Data(contentsOf: cloudCopy)).flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let copied = (copy?["values"] as? [String: Any])?["defaults.maxItems"] as? Int
        evidence["cloud_copy_followed_last_value"] = copied == 2222
        // The switch itself, back to back, three rounds each way: the last command wins and stays.
        var switchOK = true, switchSamples = 0, switchNotes: [String] = []
        for round in 1...3 {
            let off1 = clip("config", "sync", "off", "--yes", "--json"), on2 = clip("config", "sync", "on", "--yes", "--json")
            let endsOn = until { syncEnabled() == true }
            let staysOn = holds { syncEnabled() == true }
            let reset = clip("config", "sync", "off", "--yes", "--json")
            _ = until { syncEnabled() == false }
            let on1 = clip("config", "sync", "on", "--yes", "--json"), off2 = clip("config", "sync", "off", "--yes", "--json")
            let endsOff = until { syncEnabled() == false }
            let staysOff = holds { syncEnabled() == false }
            switchSamples += staysOn.samples + staysOff.samples
            let codes = [off1, on2, reset, on1, off2].allSatisfy { $0.code == 0 }
            let ok = codes && endsOn && staysOn.ok && endsOff && staysOff.ok && delegate.configuration?.enabled == false
            if !ok {
                switchOK = false
                switchNotes.append("第 \(round) 轮：off→on 结束于开=\(endsOn && staysOn.ok)（第二条 requested=\(String(describing: on2.json["requested"]))），on→off 结束于关=\(endsOff && staysOff.ok)（第二条 requested=\(String(describing: off2.json["requested"]))）")
            }
            if round < 3 {
                _ = clip("config", "sync", "on", "--yes", "--json")
                _ = until { syncEnabled() == true }
            }
        }
        samples["config sync"] = switchSamples
        report.check(switchOK, "背靠背 config sync off → on 与 on → off 各三轮：最后一条生效并保持，运行中的 App 没有把开关拨回去",
                     switchNotes.isEmpty ? "读回 \(switchSamples) 次" : switchNotes.joined(separator: "；"))

        // 5. iCloud 历史归档: the status line the settings page shows, read by the command. The app is asked to switch
        // the archive off, which opens the archive library on this Mac only; nothing here ever switches iCloud on.
        let quiet = clip("cloud", "status", "--json")
        report.check(quiet.code == 0 && quiet.json["live"] is NSNull && AppModel.shared.cloudIfLoaded == nil,
                     "App 还没打开 iCloud 归档时 cloud status 的 live 为 null；读它不会打开归档",
                     quiet.json["live_status"] as? String ?? "")
        defaults.set(true, forKey: "cloudEnabled")
        _ = defaults.synchronize()
        let off = clip("cloud", "off", "--yes", "--json")
        let opened = until { let s = clip("cloud", "status", "--json").json; return s["live"] is [String: Any] && s["enabled"] as? Bool == false }
        settle(0.8)
        let cloud = clip("cloud", "status", "--json")
        let liveCloud = cloud.json["live"] as? [String: Any]
        let sync = AppModel.shared.cloudIfLoaded
        let line = liveCloud?["sync_status"] as? String
        let sameLine = line != nil && line == sync?.library.syncStatus && cloud.json["live_status"] as? String == line
        let sameArchive = liveCloud?["archive_status"] as? String == sync?.status && liveCloud?["busy"] as? Bool == sync?.busy
        report.check(off.code == 0 && off.json["requested"] as? Bool == true && opened && sameLine && sameArchive && liveCloud?["error"] is NSNull
                     && sync?.library.cloudEnabled == false && sync?.library.error == nil,
                     "cloud off：运行中的 App 关闭归档，cloud status 的 live 读到设置页那句状态文字与整理状态",
                     "\(line ?? "nil") · \(liveCloud?["archive_status"] as? String ?? "nil")")
        evidence["cloud"] = ["sync_status": line ?? "", "archive_status": liveCloud?["archive_status"] as? String ?? ""]
        // After the archive is open its lines change: the publisher follows the archive object and its library, the two
        // objects the settings page observes. The changes below are made on those objects by this test (the 「补充最近历史」
        // action on the empty local archive, then an error text), not by a real sync.
        func liveLine(_ key: String) -> Any? { (clip("cloud", "status", "--json").json["live"] as? [String: Any])?[key] }
        if let sync {
            Task { await sync.sendRecent() }
            let arranged = until { sync.status != "尚未启用" && liveLine("archive_status") as? String == sync.status }
            let arrangedLine = sync.status
            sync.library.error = "自检写入的错误提示"
            let errorShown = until { liveLine("error") as? String == "自检写入的错误提示" }
            sync.library.error = nil
            let errorGone = until { liveLine("error") is NSNull }
            report.check(arranged && errorShown && errorGone,
                         "归档打开之后状态再变（整理状态、错误提示出现与消失）：运行中的 App 跟着重写，cloud status 的 live 读到新值", arrangedLine)
            evidence["cloud_after_change"] = ["archive_status": arrangedLine]

            // 5b. The phone's 收藏 / 取消收藏 / 删除 on the synced history. Another process asks; this running app writes,
            // through the phone's own ClipLibrary.mutate, into the archive opened above (this Mac only, never CloudKit);
            // every verdict is read back by yet another process and compared with what this app holds.
            let noteKey = (try? sync.library.save(text: "runtime self-test: a synced note", source: "自检")) ?? ""
            func held(_ key: String) -> PocketClip? { (try? sync.library.list(limit: .max))?.first { $0.id == key } }
            func shownFavorite(_ key: String) -> Bool? { (clip("cloud", "show", key, "--json").json["item"] as? [String: Any])?["favorite"] as? Bool }
            let fav = clip("cloud", "favorite", noteKey, "--json")
            report.check(!noteKey.isEmpty && fav.code == 0 && fav.json["changed"] as? Bool == true && fav.json["favorite"] as? Bool == true
                         && held(noteKey)?.favorite == true && shownFavorite(noteKey) == true,
                         "cloud favorite：另一个进程请求，运行中的 App 在同步历史里收藏这一条，cloud show 读到",
                         "退出码 \(fav.code) \(fav.json["message"] as? String ?? "")")
            let unfav = clip("cloud", "unfavorite", noteKey, "--json")
            report.check(unfav.code == 0 && unfav.json["favorite"] as? Bool == false && held(noteKey)?.favorite == false && shownFavorite(noteKey) == false,
                         "cloud unfavorite：运行中的 App 取消收藏，cloud show 读到", "退出码 \(unfav.code) \(unfav.json["message"] as? String ?? "")")
            let del = clip("cloud", "delete", noteKey, "--yes", "--json")
            let listed = ((clip("cloud", "list", "--json").json["items"] as? [[String: Any]]) ?? []).contains { $0["key"] as? String == noteKey }
            report.check(del.code == 0 && del.json["deleted"] as? Bool == true && held(noteKey) == nil && !listed
                         && clip("cloud", "show", noteKey, "--json").code == 3,
                         "cloud delete --yes：运行中的 App 从同步历史删除这一条，cloud list / show 不再有它", "退出码 \(del.code) \(del.json["message"] as? String ?? "")")
            let requestFiles = (try? fm.contentsOfDirectory(atPath: ClipCloudChange.directory(home: home).path)) ?? []
            report.check(requestFiles.isEmpty, "同步历史的改动请求与回应：读完即清，数据目录里不留文件", requestFiles.joined(separator: " "))
            evidence["cloud_change"] = ["key": String(noteKey.prefix(12)), "favorite": Int(fav.code), "unfavorite": Int(unfav.code), "delete": Int(del.code)]
        } else {
            report.check(false, "归档打开之后状态再变（整理状态、错误提示出现与消失）：运行中的 App 跟着重写，cloud status 的 live 读到新值", "归档没有打开")
        }

        // Left for the wrapper to read after this process has exited: toggleWindow global, pause global (refused).
        report.check(registration("toggleWindow") == "registered" && registration("pause") == "failed" && paused() == false && syncEnabled() == false,
                     "收尾：全局键一条已注册、一条被拒，记录未暂停，配置同步为关")
        evidence["samples"] = samples
        evidence["clip_processes"] = spawned
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys, .withoutEscapingSlashes]) {
            print("EVIDENCE " + String(decoding: data, as: UTF8.self))
        }
        try? fm.removeItem(at: scratch)
        return report.finish()
    }
}
