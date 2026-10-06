import AppKit
import Foundation
import SQLite3

/// `clip` in-process checks for `--selftest`: the production ClipCLI.run against an isolated data dir,
/// preferences suite and private pasteboard. Covers success output (JSON "ok"), refusal exit codes,
/// read-only reads, shared validation and the cross-process marker. Never touches the user's data,
/// preferences or general pasteboard, and posts no notifications.
@MainActor
enum CLISelfTest {
    struct Result { let code: Int32; let out: String; let err: String
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any] ?? [:] }
    }

    static func run(tmp: URL) -> [(Bool, String)] {
        var checks: [(Bool, String)] = []
        func check(_ ok: Bool, _ what: String) { checks.append((ok, "clip " + what)) }
        let home = tmp.appendingPathComponent("cli-home", isDirectory: true)
        let suite = "cyou.tianli.clipbook.cli-selftest.\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let board = NSPasteboard(name: .init("cyou.tianli.clipbook.cli-selftest-\(UUID().uuidString)"))
        defer {
            defaults.removePersistentDomain(forName: suite)
            _ = defaults.synchronize()
            let plist = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(suite).plist")
            try? FileManager.default.removeItem(at: plist)
            board.releaseGlobally()
        }
        var stdin = Data()
        var appPIDs: [Int32] = []   // what the running-Clip probe answers (never the real system)
        func clip(_ args: String...) -> Result { clipArgs(args) }
        func clipArgs(_ args: [String]) -> Result {
            var out = "", err = ""
            var ctx = ClipCLI.Context(home: home, defaults: defaults, domain: suite, pasteboard: { board }, stdin: { stdin },
                                      out: { out += $0 + "\n" }, err: { err += $0 + "\n" }, notify: false,
                                      deckHome: tmp.appendingPathComponent("no-deck"))
            let pids = appPIDs
            ctx.runningApp = { pids }
            return Result(code: ClipCLI.run(args, context: ctx), out: out, err: err)
        }
        func id(_ r: Result) -> Int64 { (r.json["id"] as? NSNumber)?.int64Value ?? -1 }

        // Entry detection: the in-bundle link name or a verb; never LaunchServices / test flags.
        check(ClipCLI.requested(["/Users/x/.local/bin/clip"]) && ClipCLI.requested(["Clipbook", "list"])
              && !ClipCLI.requested(["Clipbook"]) && !ClipCLI.requested(["Clipbook", "-psn_0_123"])
              && !ClipCLI.requested(["Clipbook", "--selftest"]) && !ClipCLI.requested(["Clipbook", "--background"]), "入口识别：clip 链接或命令词；GUI 启动与测试参数不进命令行")
        check(clip("--help").code == 0 && clip("list", "--help").code == 0 && clip("frobnicate").code == 2, "--help 退出 0，未知命令退出 2")

        // Reads never create or write anything.
        let st = clip("status", "--json")
        check(st.code == 0 && st.json["ok"] as? Bool == true && ((st.json["data"] as? [String: Any])?["database_exists"] as? Bool) == false
              && !FileManager.default.fileExists(atPath: home.path), "status 在空目录只读：不建目录、不建库")
        let missing = clip("list", "--json")
        check(missing.code == 3 && missing.json["ok"] as? Bool == false && missing.json["error"] as? String == "not_found", "没有库时 list 返回 ok:false、退出 3")

        // add → dedupe → attribution.
        let a = clip("add", "--text", "hello cli", "--json")
        let a2 = clip("add", "--text", "hello cli", "--json")
        check(a.code == 0 && id(a) > 0 && a.json["deduplicated"] as? Bool == false && id(a2) == id(a) && a2.json["deduplicated"] as? Bool == true,
              "add 新增 → 同内容再加只顶上（去重）")
        let link = clip("add", "--text", "https://example.com/cli", "--no-fetch-title", "--json")
        check(link.json["kind"] as? String == "link", "add 与复制入库同一识别：单行链接 → link")
        stdin = Data("from stdin\nsecond line".utf8)
        let s = clip("add", "--stdin", "--title", "标题", "--json")
        check(s.code == 0 && clip("show", "\(id(s))", "--json").json["item"].flatMap { ($0 as? [String: Any])?["title"] as? String } == "标题", "add --stdin 带标题")
        check(clip("add", "--text", "   ", "--json").code == 2 && clip("add", "--json").code == 2, "空内容 / 未给来源 → 退出 2")
        let shown = clip("show", "\(id(a))", "--json").json["item"] as? [String: Any]
        check(shown?["app_bundle"] as? String == ClipRules.cliBundle && shown?["text"] as? String == "hello cli", "来源记为 Clip CLI")
        let safari = try? ClipStore(home: home).ingest(Capture(kind: .text, text: "from safari text", appName: "Safari", appBundle: "com.apple.Safari"))
        let again = clip("add", "--text", "from safari text", "--json")
        check(id(again) == safari?.id && (again.json["previous_source"] as? [String: Any])?["app_bundle"] as? String == "com.apple.Safari"
              && (again.json["source"] as? [String: Any])?["app_bundle"] as? String == ClipRules.cliBundle,
              "同内容再 add：与再次复制相同改记来源，JSON 给出原来源")
        _ = clip("delete", "\(id(again))", "--yes")
        check(clip("show", "999999", "--json").code == 3 && clip("show", "abc").code == 2, "不存在的 id 退出 3，非法 id 退出 2")

        // list / stats read the same query as the grid.
        let listed = clip("list", "--json")
        check(listed.code == 0 && (listed.json["total"] as? Int) == 3 && ((listed.json["items"] as? [[String: Any]])?.first?["id"] as? NSNumber)?.int64Value == id(s),
              "list 总数与顺序（新的在上）")
        let meta = clip("list", "--no-text", "--json").json["items"] as? [[String: Any]] ?? []
        check(!meta.isEmpty && meta.allSatisfy { $0["preview"] == nil && $0["title"] == nil && $0["display_title"] == nil }, "--no-text 不输出正文与标题")
        check((clip("search", "hello", "--json").json["total"] as? Int) == 1 && (clip("list", "--kind", "link", "--json").json["total"] as? Int) == 1, "search / --kind 筛选")
        check(clip("list", "--kind", "bogus").code == 2 && clip("list", "--limit", "0").code == 2, "非法筛选参数退出 2")

        // edit / transform / merge reuse the window's rules.
        let e = clip("edit", "\(id(a))", "--text", "https://edited.example", "--title", "T", "--json")
        check(e.code == 0 && e.json["kind"] as? String == "link" && e.json["title"] as? String == "T", "edit 与「保存」相同：改标题、按新内容重识别")
        let refused = clip("edit", "\(id(a))", "--title", "不应写入", "--text", "   ", "--json")
        check(refused.code == 2 && (clip("show", "\(id(a))", "--json").json["item"] as? [String: Any])?["title"] as? String == "T",
              "edit 先校验再写：被拒绝时标题也不变")
        let rtf = "{\\rtf1\\ansi {\\b bold} text}".data(using: .utf8)!
        let rich = try? ClipStore(home: home).ingest(Capture(kind: .richText, text: "bold text", rtf: rtf, appName: "TextEdit", appBundle: "com.apple.TextEdit"))
        let same = clip("edit", "\(rich?.id ?? -1)", "--text", "bold text", "--title", "富文本", "--json")
        let richAfter = try? ClipStore(home: home, readOnly: true).item(id: rich?.id ?? -1)
        check(same.code == 0 && same.json["text_changed"] as? Bool == false && same.json["title_changed"] as? Bool == true
              && richAfter?.kind == .richText && richAfter?.rtf != nil && richAfter?.title == "富文本",
              "edit 正文未变不重写：富文本与 RTF 保留，只改标题")
        let noop = clip("edit", "\(rich?.id ?? -1)", "--title", "富文本", "--json")
        check(noop.code == 0 && noop.json["changed"] as? Bool == false, "edit 无变化时 changed:false")
        _ = clip("delete", "\(rich?.id ?? -1)", "--yes")
        let t = clip("add", "--text", "{\"b\":1,\"a\":2}", "--json")
        let before = board.changeCount
        let tr = clip("transform", "\(id(t))", "json", "--json")
        let tText = (clip("show", "\(id(t))", "--json").json["item"] as? [String: Any])?["text"] as? String
        check(tr.code == 0 && tr.json["copied"] as? Bool == false && tText == "{\n  \"a\" : 2,\n  \"b\" : 1\n}" && board.changeCount == before,
              "transform 保存结果，默认不动剪贴板")
        check(clip("transform", "\(id(t))", "plain").code == 2, "转纯文本只用于富文本")
        let img = try? ClipStore(home: home).ingest(Capture(kind: .image, text: "图片 2×2", imagePNG: png(), width: 2, height: 2, appName: "T", appBundle: "t"))
        let imgID = img?.id ?? -1
        check(clip("transform", "\(imgID)", "upper").code == 2 && clip("edit", "\(imgID)", "--text", "x").code == 2, "图片不能转换或改正文（退出 2）")
        check(clip("merge", "\(id(s))", "\(imgID)").code == 2 && clip("merge", "\(id(s))").code == 2 && clip("merge", "\(id(s))", "999999").code == 3,
              "merge 拒绝图片 / 单条 / 不存在的 id")
        let m = clip("merge", "\(id(t))", "\(id(s))", "--json")
        let mText = (clip("show", "\(id(m))", "--json").json["item"] as? [String: Any])?["text"] as? String
        check(m.code == 0 && mText?.hasSuffix("\n\nfrom stdin\nsecond line") == true, "merge 按给出顺序空行连接")

        // pin / delete / clear confirmations.
        check(clip("pin", "\(id(s))").code == 0 && (clip("list", "--pinned", "--json").json["total"] as? Int) == 1, "pin 后 --pinned 可见")
        check(clip("delete", "\(id(link))").code == 2 && clip("delete", "\(id(link))", "--dry-run", "--json").json["would_delete"] as? Int == 1
              && clip("show", "\(id(link))").code == 0, "delete 无 --yes 拒绝；--dry-run 不删")
        check(clip("delete", "\(id(link))", "--yes").code == 0 && clip("show", "\(id(link))").code == 3, "delete --yes 删除")

        // export (image only, no silent overwrite).
        let dest = tmp.appendingPathComponent("cli-export.png")
        check(clip("export", "\(imgID)", "-o", dest.path).code == 0 && FileManager.default.fileExists(atPath: dest.path)
              && clip("export", "\(imgID)", "-o", dest.path).code == 2 && clip("export", "\(imgID)", "-o", dest.path, "--force").code == 0
              && clip("export", "\(id(s))", "-o", dest.path, "--force").code == 2, "export：图片原图；已存在需 --force；非图片退出 2")

        // copy: private pasteboard, marker, touch; the watcher skips Clip's own marked write.
        var captured = 0, sounded = 0
        let watcher = PasteboardWatcher(pasteboard: board, onCopy: { _ in sounded += 1 }) { _ in captured += 1 }
        let dryChange = board.changeCount
        check(clip("copy", "\(id(t))", "--dry-run").code == 0 && board.changeCount == dryChange, "copy --dry-run 不写剪贴板")
        let cp = clip("copy", "\(id(t))", "--json")
        watcher.poll()
        check(cp.code == 0 && board.string(forType: .string) == tText && board.string(forType: Paster.sourceType) == Paster.sourceID
              && captured == 0 && sounded == 0, "copy 写入正文并带来源标记；运行中的 Clip 不重复记录、不响")
        check(((clip("list", "--json").json["items"] as? [[String: Any]])?.dropFirst().first?["id"] as? NSNumber)?.int64Value == id(t),
              "单条 copy 与「复制」相同：顶到置顶之后的最上")

        // collections: whitelist, reorder, membership, delete needs --yes.
        let badIcon = clip("collection", "create", "工作", "--icon", "rocket", "--json")
        check(badIcon.code == 2 && badIcon.json["command"] as? String == "collection create", "收藏夹图标沿用编辑器白名单")
        let c1 = clip("collection", "create", "工作", "--json"), c2 = clip("collection", "create", "灵感", "--icon", "star", "--color", "#dc2626", "--json")
        check(clip("collection", "add", "工作", "\(id(t))", "\(id(s))").code == 0 && (clip("list", "--collection", "工作", "--json").json["total"] as? Int) == 2,
              "按名字加入收藏夹并筛选")
        check(clip("collection", "move", "\(id(c2))", "up").code == 0 && (clip("collections", "--json").json["collections"] as? [[String: Any]])?.first?["name"] as? String == "灵感"
              && clip("collection", "move", "\(id(c2))", "up").code == 2, "上移与越界")
        check(clip("collection", "delete", "\(id(c1))").code == 2 && clip("collection", "delete", "\(id(c1))", "--yes").code == 0
              && clip("show", "\(id(t))").code == 0, "删收藏夹需 --yes，记录保留")

        // clear keeps pinned.
        check(clip("clear").code == 2, "clear 无 --yes 拒绝")
        let dryClear = clip("clear", "--dry-run", "--json")
        let cl = clip("clear", "--yes", "--json")
        check(cl.code == 0 && (dryClear.json["would_delete"] as? Int) == (cl.json["deleted"] as? Int) && clip("show", "\(id(s))").code == 0,
              "clear 保留置顶（dry-run 预告与实删一致）")

        // settings: window ranges, persisted in the same keys, picked up by AppSettings.reload().
        let live = AppSettings(defaults: defaults)
        let badDays = clip("settings", "set", "retentionDays", "31", "--json")
        check(clip("settings", "set", "maxItems", "50").code == 2 && badDays.code == 2 && badDays.json["command"] as? String == "settings set"
              && clip("settings", "set", "nope", "1").code == 2, "设置取值沿用设置页范围；失败的 JSON command 与成功相同")
        let login = clip("settings", "set", "launchAtLogin", "true", "--json")
        let loginDry = clip("settings", "set", "launchAtLogin", "true", "--dry-run", "--json")
        check(login.code == 4 && login.json["error"] as? String == "system_setting" && loginDry.code == 0 && loginDry.json["dry_run"] as? Bool == true
              && clip("settings", "set", "maxItems", "700", "--dry-run").code == 2, "开机自启是系统登录项：隔离运行拒绝（退出 4），--dry-run 只报告")
        check(clip("settings", "set", "maxItems", "700").code == 0 && defaults.integer(forKey: "maxItems") == 700
              && clip("pause").code == 0 && defaults.bool(forKey: "paused"), "settings set / pause 写入同一偏好键")
        live.reload()
        check(live.maxItems == 700 && live.paused, "运行中的设置对象 reload 后读到命令行的修改")
        check(clip("resume").code == 0 && !defaults.bool(forKey: "paused") && clip("ignore", "add", "com.example.x").code == 0
              && defaults.stringArray(forKey: "ignoredBundles") == ["com.example.x"] && clip("ignore", "remove", "com.example.x").code == 0,
              "resume 与忽略名单")
        let sj = clip("settings", "--json").json["settings"] as? [String: Any]
        check(sj?["maxItems"] as? Int == 700 && (sj?["shortcuts"] as? [Any])?.isEmpty == true, "settings --json 回读；快捷键只读列出（默认无绑定）")

        let badVersion = clip("version", "--definitely-not-a-flag", "--json")
        check(clip("version", "--json").code == 0 && badVersion.code == 2 && badVersion.json["error"] as? String == "usage"
              && badVersion.json["command"] as? String == "version" && clip("--version", "extra").code == 2, "version 校验参数：多余的参数退出 2")
        // Every subcommand a feature is registered against is listed at the start of a line in the top-level help,
        // and the help keeps 仅在窗口中 (a person, or the window) apart from 暂无命令 (not reachable yet).
        let helpText: String = ClipCLI.usage()
        let helpLines: [String] = helpText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let helpCommands: [String] = ["status", "stats", "list", "search", "show", "export", "collections", "settings", "ignore list", "shortcut list",
                                      "config status", "config export", "update check", "cloud status", "cloud list", "cloud show", "version", "add", "edit", "transform",
                                      "pin", "unpin", "merge", "delete", "clear", "collection", "settings set", "pause", "resume", "ignore add",
                                      "ignore remove", "shortcut scope", "shortcut clear", "config import", "import-deck", "copy", "cloud push", "config sync"]
        func helpLists(_ name: String) -> Bool {
            helpLines.contains { (line: String) -> Bool in line == name || line.hasPrefix(name + " ") || line.hasPrefix(name + "|") }
        }
        let unlisted: [String] = helpCommands.filter { !helpLists($0) }
        let afterWindow: String = helpText.components(separatedBy: "仅在窗口中").last ?? ""
        let windowOnly: String = afterWindow.components(separatedBy: "暂无命令").first ?? ""
        let separated: Bool = helpText.contains("暂无命令") && !windowOnly.contains("检查更新") && !windowOnly.contains("同步状态") && !windowOnly.contains("升级到新版")
        let keepsHuman: Bool = windowOnly.contains("录制快捷键") && windowOnly.contains("试听")
        let helpNote: String = unlisted.isEmpty ? "" : "（缺 " + unlisted.joined(separator: "、") + "）"
        check(unlisted.isEmpty && separated && keepsHuman, "顶层帮助：每个子命令都在行首列出" + helpNote + "；「仅在窗口中」不混入暂无命令的项")

        // 设置 → 快捷键: scope and clear go through ClipShortcuts; a chord is never invented by the command line.
        func storedBindings() -> [String: ClipBinding] {
            defaults.data(forKey: ClipShortcuts.storageKey).flatMap { try? JSONDecoder().decode([String: ClipBinding].self, from: $0) } ?? [:]
        }
        let keyList = clip("shortcut", "--json")
        let keyRows = keyList.json["shortcuts"] as? [[String: Any]] ?? []
        check(keyList.code == 0 && keyList.json["command"] as? String == "shortcut list" && keyRows.count == ClipAction.allCases.count
              && keyRows.allSatisfy { $0["keys"] is NSNull } && storedBindings().isEmpty, "shortcut list：每个动作一行，默认没有任何绑定")
        let keyUnbound = clip("shortcut", "scope", "search", "global", "--json")
        check(keyUnbound.code == 2 && keyUnbound.json["error"] as? String == "invalid" && storedBindings().isEmpty
              && clip("shortcut", "scope", "nope", "global").code == 2 && clip("shortcut", "scope", "search", "everywhere").code == 2,
              "shortcut scope 不替你新增组合键：未录制的动作、未知动作、未知范围都退出 2")
        // A keyRecorded ⌥⌘F for 聚焦搜索, as the Settings window stores it (cmdKey 256 | optionKey 2048).
        let keyRecorded = ["search": ClipBinding(chord: ClipKey(code: 3, modifiers: 256 | 2048, key: "F"), scope: .application)]
        defaults.set(try? JSONEncoder().encode(keyRecorded), forKey: ClipShortcuts.storageKey)
        let keyWidened = clip("shortcut", "scope", "search", "global", "--json")
        check(keyWidened.code == 0 && keyWidened.json["changed"] as? Bool == true && storedBindings()["search"]?.scope == .global
              && storedBindings()["search"]?.chord == keyRecorded["search"]?.chord, "shortcut scope 只改作用范围，组合键不变")
        let widenedRow = (keyWidened.json["shortcuts"] as? [[String: Any]])?.first { $0["action"] as? String == "search" }
        check(widenedRow?["registration"] as? String == "app_not_running" && (widenedRow?["status"] as? String)?.hasPrefix("已保存") == true
              && (widenedRow?["status"] as? String)?.contains("已启用") == false,
              "shortcut list 不替 App 声称全局键已启用：Clip 未运行时 registration 为 app_not_running，status 写「已保存」")
        let scopeAgain = clip("shortcut", "scope", "search", "global", "--json")
        check(scopeAgain.code == 0 && scopeAgain.json["changed"] as? Bool == false, "shortcut scope 重复执行不再写入")
        check(clip("shortcut", "clear", "search", "--json").json["changed"] as? Bool == true && storedBindings().isEmpty
              && clip("shortcut", "clear", "--all", "--json").json["changed"] as? Bool == false, "shortcut clear 清除绑定；已空时 clear --all 不变")

        // What only the running app knows reaches the command line through ClipRuntimeState: the app-side publisher runs
        // here over a shortcut centre whose key backend refuses ⌥⌘G, with an injected Accessibility answer.
        let me = ProcessInfo.processInfo.processIdentifier
        let globalKeys = ["search": ClipBinding(chord: ClipKey(code: 3, modifiers: 256 | 2048, key: "F"), scope: .global),
                          "pause": ClipBinding(chord: ClipKey(code: 5, modifiers: 256 | 2048, key: "G"), scope: .global)]
        defaults.set(try? JSONEncoder().encode(globalKeys), forKey: ClipShortcuts.storageKey)
        let appCenter = ClipShortcuts(defaults: defaults, backend: RefusingKeys(refusedCode: 5), monitorsEnabled: false) { _ in }
        var granted = true
        let publisher = ClipRuntimePublisher(home: home, shortcuts: appCenter, trusted: { granted })
        func keyRow(_ action: String) -> [String: Any]? {
            (clip("shortcut", "list", "--json").json["shortcuts"] as? [[String: Any]])?.first { $0["action"] as? String == action }
        }
        func grant() -> [String: Any]? { (clip("status", "--json").json["permissions"] as? [String: Any])?["accessibility"] as? [String: Any] }
        appPIDs = [me]
        let failedRow = keyRow("pause")
        check(keyRow("search")?["registration"] as? String == "registered" && keyRow("search")?["status"] as? String == "已启用 · 全局"
              && failedRow?["registration"] as? String == "failed" && (failedRow?["status"] as? String)?.contains("系统拒绝注册") == true,
              "shortcut list 读到运行中的 App 报告的注册结果：registered / failed，status 是窗口里那句话")
        let grantLive = grant()
        granted = false; publisher.publish()
        let grantRevoked = grant()
        check(grantLive?["trusted"] as? Bool == true && grantLive?["live"] as? Bool == true && grantRevoked?["trusted"] as? Bool == false,
              "status 的 permissions.accessibility 来自运行中的 App；授权变了随之变")
        var withCloud = publisher.snapshot()
        withCloud.cloud = .init(syncStatus: "最近同步 12:00", archiveStatus: "已整理最近 3 条，iCloud 将增量同步", error: "账户需要重新登录", busy: false)
        withCloud.write(home: home)
        let cloudLive = clip("cloud", "status", "--json")
        let liveBody = cloudLive.json["live"] as? [String: Any]
        check(cloudLive.json["live_status"] as? String == "最近同步 12:00" && liveBody?["archive_status"] as? String == "已整理最近 3 条，iCloud 将增量同步"
              && liveBody?["error"] as? String == "账户需要重新登录" && liveBody?["busy"] as? Bool == false,
              "cloud status 的 live 读到 App 报告的同步状态、整理状态与错误")
        appPIDs = []
        let cloudStopped = clip("cloud", "status", "--json")
        let grantStale = grant()
        check(keyRow("search")?["registration"] as? String == "app_not_running" && cloudStopped.json["live"] is NSNull
              && (cloudStopped.json["live_status"] as? String)?.contains("未运行") == true
              && grantStale?["trusted"] as? Bool == false && grantStale?["live"] as? Bool == false && grantStale?["as_of"] is String,
              "Clip 未运行：全局键 app_not_running、iCloud live 为 null；辅助功能给出上次的值并标明不是实时")
        try? FileManager.default.removeItem(at: ClipRuntimeState.url(home: home))
        check(grant()?["trusted"] is NSNull && grant()?["as_of"] is NSNull, "没有 App 报告时 permissions.accessibility.trusted 为 null（不猜）")
        withExtendedLifetime(publisher) {}
        defaults.removeObject(forKey: ClipShortcuts.storageKey)

        // 配置与更新: export / import through the shared AppConfiguration; an isolated run keeps its configBackups in its own home.
        let configFile = tmp.appendingPathComponent("cli-config.json")
        let configState = clip("config", "--json")
        check(configState.code == 0 && configState.json["command"] as? String == "config status" && configState.json["sync_enabled"] as? Bool == false
              && configState.json["keys"] as? [String] == ClipPortableConfiguration.keys, "config status 只读报告开关与可迁移的偏好键")
        check(clip("config", "export", "-o", configFile.path, "--json").code == 0 && FileManager.default.fileExists(atPath: configFile.path)
              && clip("config", "export", "-o", configFile.path).code == 2 && clip("config", "export", "-o", configFile.path, "--force").code == 0,
              "config export 写出配置文件；已存在时要 --force")
        _ = clip("settings", "set", "maxItems", "900")
        let configUnconfirmed = clip("config", "import", configFile.path, "--json")
        check(configUnconfirmed.code == 2 && configUnconfirmed.json["error"] as? String == "confirmation_required" && defaults.integer(forKey: "maxItems") == 900
              && clip("config", "import", tmp.appendingPathComponent("no-such.json").path, "--yes").code == 3,
              "config import 没有 --yes 不动配置；文件不存在退出 3")
        let configImported = clip("config", "import", configFile.path, "--yes", "--json")
        let configBackups = home.appendingPathComponent("Configuration/\(ClipPortableConfiguration.productID)/Backups")
        check(configImported.code == 0 && defaults.integer(forKey: "maxItems") == 700
              && ((try? FileManager.default.contentsOfDirectory(atPath: configBackups.path))?.count ?? 0) == 1,
              "config import 恢复导出时的配置，原配置备份在隔离数据目录里")
        try? Data("not a configuration".utf8).write(to: configFile)
        check(clip("config", "import", configFile.path, "--yes").code == 2 && defaults.integer(forKey: "maxItems") == 700, "config import 拒绝无法识别的文件，配置不变")
        let configSyncDry = clip("config", "sync", "on", "--dry-run", "--json")
        let configSyncStopped = clip("config", "sync", "on", "--yes", "--json")
        check(configSyncDry.code == 0 && configSyncDry.json["would_change"] as? Bool == true && clip("config", "sync", "on").code == 2
              && configSyncStopped.code == 4 && configSyncStopped.json["error"] as? String == "app_not_running"
              && !defaults.bool(forKey: "appLifecycle.configuration.enabled"), "config sync 要 --yes 与运行中的 Clip；命令行自己不拨开关")

        // 检查更新: the shared command layer on an isolated release feed; never the user's iCloud Drive, never the network.
        #if !CLIP_LOCAL_DISTRIBUTION
        let noFeed = clip("update", "check", "--json")
        check(noFeed.code == 1 && noFeed.json["ok"] as? Bool == false && noFeed.json["error"] as? String == "check_incomplete"
              && noFeed.json["command"] as? String == "update check" && noFeed.json["exit_code"] as? Int == 1
              && (noFeed.json["current"] as? [String: Any])?["version"] is String, "update check 读不到发行记录时退出 1、check_incomplete，仍给出当前版本")
        let feedRoot = tmp.appendingPathComponent("cli-update-feed", isDirectory: true)
        let feed = feedRoot.appendingPathComponent("TianliApps/Updates/\(ClipCLI.appBundleID)/cloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: feed, withIntermediateDirectories: true)
        func publish(_ version: String, _ build: String) -> Result {
            let release: [String: Any] = ["version": version, "build": build, "bundle_id": ClipCLI.appBundleID, "channel": "cloud",
                                          "filename": "Clip-\(version).zip", "sha256": String(repeating: "a", count: 64), "size_bytes": 10]
            try? JSONSerialization.data(withJSONObject: release).write(to: feed.appendingPathComponent("release.json"))
            setenv("APP_LIFECYCLE_CLOUD_DIR", feedRoot.path, 1)
            defer { unsetenv("APP_LIFECYCLE_CLOUD_DIR") }
            return clip("update", "check", "--json")
        }
        let newer = publish("99.0", "1")
        let newerUpgrade = newer.json["upgrade"] as? [String: Any]
        check(newer.code == 0 && newer.json["ok"] as? Bool == true && newer.json["update_available"] as? Bool == true
              && newer.json["state"] as? String == "update_available" && (newer.json["latest"] as? [String: Any])?["version"] as? String == "99.0"
              && (newer.json["source"] as? [String: Any])?["kind"] as? String == "private_cloud"
              && (newerUpgrade?["how"] as? String)?.contains("配置与更新") == true, "update check 报出此渠道的新版与升级办法（与窗口同一渠道）")
        let host = ClipCLI.hostInfo()
        let current = publish(host.version, host.build)
        check(current.code == 0 && current.json["state"] as? String == "up_to_date" && current.json["update_available"] as? Bool == false
              && (current.json["upgrade"] as? [String: Any])?["button"] is NSNull, "update check 已是最新时如实报告")
        check(((try? FileManager.default.contentsOfDirectory(atPath: feed.path)) ?? []) == ["release.json"], "update check 不下载、不安装")
        #endif
        let badUpdate = clip("update", "--json"), badUpdateFlag = clip("update", "check", "--definitely-not-a-flag", "--json")
        check(badUpdate.code == 2 && badUpdate.json["error"] as? String == "usage" && badUpdateFlag.code == 2
              && badUpdateFlag.json["command"] as? String == "update check" && clip("update", "--help").code == 0, "update 用法错误退出 2，--help 退出 0")

        // Deck import through the production importer, with the cross-process lock.
        let deck = tmp.appendingPathComponent("cli-deck", isDirectory: true)
        try? FileManager.default.createDirectory(at: deck, withIntermediateDirectories: true)
        var ddb: OpaquePointer?
        sqlite3_open(deck.appendingPathComponent("Deck.sqlite3").path, &ddb)
        sqlite3_exec(ddb, """
        CREATE TABLE ClipboardHistory(id INTEGER PRIMARY KEY, unique_id TEXT, item_type TEXT, data BLOB, preview_data BLOB, timestamp INTEGER,
          app_path TEXT, app_name TEXT, custom_title TEXT, blob_path TEXT, is_temporary INTEGER DEFAULT 0, is_encrypted INTEGER DEFAULT 0);
        INSERT INTO ClipboardHistory(unique_id,item_type,data,timestamp,app_path,app_name) VALUES
          ('d1','text',CAST('deck one' AS BLOB),1700000000,'/System/Applications/TextEdit.app','TextEdit'),
          ('d2','url',CAST('https://deck.example/y' AS BLOB),1700000001,'/System/Applications/TextEdit.app','TextEdit');
        """, nil, nil, nil)
        sqlite3_close(ddb)
        let lockFD = open(home.appendingPathComponent(".deck-import.lock").path, O_CREAT | O_RDWR, 0o644)
        let held = flock(lockFD, LOCK_EX | LOCK_NB) == 0
        let busy = clip("import-deck", "--deck-home", deck.path, "--json")
        flock(lockFD, LOCK_UN); close(lockFD)
        check(held && busy.code == 5 && busy.json["error"] as? String == "busy", "另一个 Deck 导入进行中 → 退出 5")
        let imp = clip("import-deck", "--deck-home", deck.path, "--json")
        let imp2 = clip("import-deck", "--deck-home", deck.path, "--json")
        check(imp.code == 0 && imp.json["imported"] as? Int == 2 && imp2.json["total"] as? Int == imp.json["total"] as? Int, "import-deck 导入并幂等")
        check(clip("import-deck", "--deck-home", tmp.appendingPathComponent("nothing").path).code == 3, "没有 Deck 库退出 3")

        // iCloud: changes are requests to the running app (which owns the sync); reads use the phone's list rule.
        let cs = clip("cloud", "status", "--json")
        check(cs.code == 0 && cs.json["archive_cache"] is NSNull && (cs.json["markers"] as? [String: Any]) != nil && cs.json["command"] as? String == "cloud status",
              "cloud status 只读（无归档缓存时为 null）")
        let noCache = clip("cloud", "list", "--json")
        check(noCache.code == (ProductIdentity.cloudSupported ? 3 : 4) && noCache.json["command"] as? String == "cloud list", "没有归档缓存时 cloud list 退出 3（本地版 4）；失败的 command 仍是 cloud list")
        check(clip("cloud", "frobnicate").code == 2, "cloud 未知子命令退出 2")
        if ProductIdentity.cloudSupported {
            check(clip("cloud", "push", "--yes").code == 2 && clip("cloud", "off", "--yes", "--json").json["changed"] as? Bool == false,
                  "归档未开：push 退出 2；off 无变化不发请求")
            check(clip("cloud", "on").code == 2 && clip("cloud", "on", "--dry-run", "--json").json["would_change"] as? Bool == true,
                  "cloud on 需 --yes；--dry-run 只报告")
            appPIDs = []
            let offline = clip("cloud", "on", "--yes", "--json")
            appPIDs = [99999]
            let asked = clip("cloud", "on", "--yes", "--json")
            check(offline.code == 4 && offline.json["error"] as? String == "app_not_running" && asked.code == 0 && asked.json["requested"] as? Bool == true
                  && !defaults.bool(forKey: "cloudEnabled"), "cloud on：Clip 未运行退出 4；运行中则请 App 拨开关（命令行不改 iCloud 状态）")
            defaults.set(true, forKey: "cloudEnabled")
            let storeNow = try? ClipStore(home: home, readOnly: true)
            let pending = (try? storeNow?.list(pageSize: MacClipSync.recentLimit).filter { try MacClipSync.needsArchive($0, store: storeNow!, scope: MacClipSync.markerScope) }.count) ?? -1
            let pushDry = clip("cloud", "push", "--dry-run", "--json")
            check(pushDry.code == 0 && pushDry.json["would_send"] as? Int == pending && pending > 0 && clip("cloud", "push", "--yes", "--json").json["requested"] as? Bool == true,
                  "cloud push --dry-run 报告待归档条数（MacClipSync 同一标记规则）；--yes 请 App 补充最近历史")
            defaults.removeObject(forKey: "cloudEnabled")
            appPIDs = []

            // Archive cache fixture written by the production ClipLibrary; the CLI must list it with the same rule.
            let lib = ClipLibrary(home: MacClipSync.archiveHome(store: home), preferences: defaults, cloudAccountKey: "cli-selftest")
            let ready = AcceptanceReport.wait(15) { await lib.start(localOnly: true); return lib.ready }.value == true
            var keys: [String] = []
            if ready {
                keys.append((try? lib.save(text: "https://example.com/phone", at: Date(timeIntervalSince1970: 10))) ?? "")
                keys.append((try? lib.save(text: "phone note", at: Date(timeIntervalSince1970: 20))) ?? "")
                keys.append((try? lib.save(text: "removed on phone", at: Date(timeIntervalSince1970: 30))) ?? "")
                try? lib.mutate(keys[1], favorite: true)
                try? lib.mutate(keys[2], remove: true)
            }
            func cloudKeys(_ args: String...) -> [String] {
                (clipArgs(["cloud", "list", "--json"] + args).json["items"] as? [[String: Any]] ?? []).compactMap { $0["key"] as? String }
            }
            let phone = { (search: String, filter: String) in (try? lib.list(search: search, filter: filter).map(\.id)) ?? ["?"] }
            check(ready && cloudKeys() == phone("", "all") && cloudKeys() == [keys[1], keys[0]]
                  && cloudKeys("--favorites") == phone("", "favorites") && cloudKeys("--kind", "link") == phone("", "link")
                  && cloudKeys("--query", "NOTE") == phone("NOTE", "all") && cloudKeys("--query", "NOTE") == [keys[1]],
                  "cloud list 与手机 ClipLibrary.list 结果逐项相同（删除隐藏、收藏、类型、搜索）")
            let cache = clip("cloud", "status", "--json").json["archive_cache"] as? [String: Any]
            check(cache?["visible"] as? Int == 2 && cache?["rows"] as? Int == 3 && cache?["tombstones"] as? Int == 1 && cache?["favorites"] as? Int == 1
                  && clip("cloud", "list", "--favorites", "--kind", "text").code == 2, "cloud status 归档缓存统计；--favorites 与 --kind 互斥")
            // 手机详情页 = cloud show：全文、来源、收藏；图片导出只写指定的文件；local_id 指回 Mac 库里的同一条。
            let long = String(repeating: "长文 ", count: 120)
            let longKey = ready ? ((try? lib.save(text: long, title: "长文标题", source: "iPhone", at: Date(timeIntervalSince1970: 40))) ?? "") : ""
            let picture = png()
            let imageKey = ready ? ((try? lib.save(text: "", image: picture, at: Date(timeIntervalSince1970: 50))) ?? "") : ""
            let shown = clip("cloud", "show", longKey, "--json").json["item"] as? [String: Any]
            let listed = (clip("cloud", "list", "--json").json["items"] as? [[String: Any]])?.first { $0["key"] as? String == longKey }
            check(!longKey.isEmpty && shown?["text"] as? String == long && shown?["title"] as? String == "长文标题" && shown?["source"] as? String == "iPhone"
                  && (listed?["preview"] as? String)?.count == 200 && listed?["local_id"] is NSNull && shown?["local_id"] is NSNull,
                  "cloud show 给出全文、标题与来源（cloud list 只有 200 字预览）；Mac 库里没有对应记录时 local_id 为 null")
            let mirrored = id(clip("add", "--text", "mirrored on this Mac", "--json"))
            try? ClipStore(home: home).setMeta("cloudReceived.\(MacClipSync.markerScope).\(longKey)", String(mirrored))
            let prefixed = clip("cloud", "show", String(longKey.prefix(16)), "--json").json["item"] as? [String: Any]
            check(mirrored > 0 && (prefixed?["local_id"] as? NSNumber)?.int64Value == mirrored && prefixed?["key"] as? String == longKey,
                  "cloud show 接受唯一的 key 前缀；local_id 读 MacClipSync 写下的对应标记")
            let imageOut = tmp.appendingPathComponent("cloud-show.png")
            let exported = clip("cloud", "show", imageKey, "-o", imageOut.path, "--json")
            check(!imageKey.isEmpty && exported.code == 0 && (exported.json["item"] as? [String: Any])?["image_bytes"] as? Int == picture.count
                  && (try? Data(contentsOf: imageOut)) == picture && clip("cloud", "show", imageKey, "-o", imageOut.path).code == 2
                  && clip("cloud", "show", longKey, "-o", tmp.appendingPathComponent("no.png").path).code == 2,
                  "cloud show -o 导出归档原图；已存在要 --force；文本记录没有图片可导出")
            check(clip("cloud", "show", "no-such-key", "--json").code == 3 && clip("cloud", "show", keys[2]).code == 3 && clip("cloud", "show").code == 2,
                  "cloud show：不存在或已在手机上删除的记录退出 3；缺 key 退出 2")
        }

        // The read-only store refuses writes at the SQLite level.
        if let ro = try? ClipStore(home: home, readOnly: true) {
            check((try? ro.setPinned(id(s), false)) == nil && ro.readOnly, "只读打开的库拒绝写入")
        } else { check(false, "只读打开已有库") }
        return checks
    }

    private static func png() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }
}

/// A key backend that registers nothing and refuses one key code, to stand in for the system refusing a global key.
@MainActor private final class RefusingKeys: ClipKeyRegistration {
    var onPress: ((UInt32) -> Void)?
    let refusedCode: UInt32
    init(refusedCode: UInt32) { self.refusedCode = refusedCode }
    func register(_ chord: ClipKey, id: UInt32) -> OSStatus { chord.code == refusedCode ? -9878 : noErr }
    func unregister(_ id: UInt32) {}
}
