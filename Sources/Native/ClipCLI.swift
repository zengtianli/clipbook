import AppKit
import Foundation
import ServiceManagement

/// `clip` — the command line for agents and scripts. It is a mode of the same signed executable as the
/// window (Contents/Resources/bin/clip → ../../MacOS/Clipbook) and calls the same business layer:
/// ClipStore, Classifier, Paster, DeckImporter, AppSettings, ClipRules. It never creates an NSApplication,
/// never opens a window, never takes focus and never touches iCloud (read-only view of the archive cache).
///
/// Reads open the library read-only and never write. Writes reuse the window's validation and then post a
/// ClipSignal so a running Clip re-reads its list / preferences.
enum ClipCLI {
    enum Exit: Int32 { case ok = 0, failure = 1, usage = 2, notFound = 3, needsApp = 4, busy = 5 }

    struct Failure: Error {
        let exit: Exit
        let code: String
        let message: String
        /// Further JSON fields for the failure (the shared update check reports what it did read).
        var extra: [String: Any] = [:]
        static func usage(_ m: String) -> Failure { Failure(exit: .usage, code: "usage", message: m) }
        static func notFound(_ m: String) -> Failure { Failure(exit: .notFound, code: "not_found", message: m) }
        static func invalid(_ m: String) -> Failure { Failure(exit: .usage, code: "invalid", message: m) }
        static func confirm(_ m: String) -> Failure { Failure(exit: .usage, code: "confirmation_required", message: m) }
    }

    /// Where the command reads and writes. Production values come from the same environment overrides
    /// the app honours (CLIPBOOK_HOME, CLIPBOOK_PREFERENCES_SUITE, CLIPBOOK_BACKGROUND); the self-test
    /// passes an isolated context.
    struct Context {
        var home: URL
        var defaults: UserDefaults
        var domain: String
        var pasteboard: () -> NSPasteboard
        var stdin: () -> Data
        var out: (String) -> Void
        var err: (String) -> Void
        var notify: Bool
        var deckHome: URL
        /// True when the data dir or preferences are overridden (sandbox / self-test): system-wide settings
        /// such as the login item are then refused, so an isolated run never changes the user's Mac.
        var isolated = true
        /// Full command path ("collection create", "cloud list"); set by run(), echoed as JSON "command".
        var command = ""
        /// PIDs of a running Clip window app (the self-test injects a fixed answer).
        var runningApp: () -> [Int32] = { ClipCLI.runningApp() }

        @MainActor static func process() -> Context {
            Context(home: ClipStore.defaultHome(), defaults: AppPreferences.defaults, domain: AppPreferences.domain,
                    pasteboard: { ProductIdentity.pasteboard }, stdin: { FileHandle.standardInput.readDataToEndOfFile() },
                    out: { FileHandle.standardOutput.write(Data(($0 + "\n").utf8)) },
                    err: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) },
                    notify: true, deckHome: DeckImporter.defaultDeckHome,
                    isolated: ["CLIPBOOK_HOME", "CLIPBOOK_PREFERENCES_SUITE"].contains { ProcessInfo.processInfo.environment[$0]?.isEmpty == false })
        }
    }

    // MARK: - Entry

    static let commandNames: [String] = ["status", "stats", "list", "search", "show", "copy", "export", "add", "edit", "transform",
                                         "pin", "unpin", "delete", "merge", "clear", "collections", "collection", "settings", "ignore",
                                         "pause", "resume", "import-deck", "cloud", "shortcut", "config", "update", "help", "version"]

    /// True when the process was started as `clip` (the in-bundle link) or with a CLI verb / --help / --version.
    /// LaunchServices launches (-psn_…, -NS…) and the test flags never match.
    static func requested(_ arguments: [String]) -> Bool {
        if let first = arguments.first, (first as NSString).lastPathComponent == "clip" { return true }
        guard arguments.count > 1 else { return false }
        return commandNames.contains(arguments[1]) || ["--help", "-h", "--version"].contains(arguments[1])
    }

    static func main(_ arguments: [String]) -> Int32 {
        reexecThroughRealPath()
        return MainActor.assumeIsolated { run(Array(arguments.dropFirst()), context: .process()) }
    }

    /// Started through a symlink (~/.local/bin/clip → …/Resources/bin/clip → ../../MacOS/Clipbook), Foundation
    /// takes the link's directory as the main bundle, so Info.plist, the version and the app's preferences
    /// domain would be missing. Re-exec the real executable with the same argv (argv[0] stays `clip`).
    private static func reexecThroughRealPath() {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size) + 1)
        guard _NSGetExecutablePath(&buffer, &size) == 0, let resolved = realpath(buffer, nil) else { return }
        let real = String(cString: resolved)
        free(resolved)
        guard real != String(cString: buffer) else { return }
        execv(real, CommandLine.unsafeArgv)
        // execv returns only on failure; carry on in this process.
    }

    /// "collection create", "cloud list", "settings set", "ignore add" … — the same string for success and failure.
    static func commandPath(_ verb: String, _ rest: [String]) -> String {
        let sub = rest.first.flatMap { $0.hasPrefix("-") ? nil : $0 }
        switch verb {
        case "collection": return sub.map { "collection \($0)" } ?? verb
        case "cloud": return "cloud \(sub ?? "status")"
        case "settings": return sub == "set" ? "settings set" : verb
        case "ignore": return "ignore \(sub ?? "list")"
        case "shortcut": return "shortcut \(sub ?? "list")"
        case "config": return "config \(sub ?? "status")"
        case "update": return sub.map { "update \($0)" } ?? verb
        case "--version": return "version"
        default: return verb
        }
    }

    @MainActor
    static func run(_ args: [String], context: Context) -> Int32 {
        var args = args
        var c = context
        let wantsJSON = args.contains("--json")
        guard let verb = args.first else { c.out(usage()); return Exit.ok.rawValue }
        c.command = commandPath(verb, Array(args.dropFirst()))
        if ["--help", "-h", "help"].contains(verb) {
            if args.count > 1, let text = help[args[1]] { c.out(text) } else { c.out(usage()) }
            return Exit.ok.rawValue
        }
        if ["--version", "version"].contains(verb) {
            let extra = args.dropFirst().filter { $0 != "--json" }
            if extra.contains("--help") || extra.contains("-h") { c.out(help["version"] ?? usage()); return Exit.ok.rawValue }
            if let bad = extra.first { return fail(c, .usage("version 不接受参数 \(bad)"), json: wantsJSON) }
            let info = hostInfo()
            if wantsJSON { emitJSON(c, ["name": info.name, "version": info.version, "build": info.build, "edition": info.edition]) }
            else { c.out("\(info.name) \(info.version) (\(info.build))") }
            return Exit.ok.rawValue
        }
        args.removeFirst()
        if args.contains("--help") || args.contains("-h") {
            c.out(help[verb] ?? usage())
            return help[verb] == nil ? Exit.usage.rawValue : Exit.ok.rawValue
        }
        do {
            switch verb {
            case "status": try status(args, c)
            case "stats": try stats(args, c)
            case "list": try list(args, c, verb: "list")
            case "search": try list(args, c, verb: "search")
            case "show": try show(args, c)
            case "copy": try copy(args, c)
            case "export": try export(args, c)
            case "add": try add(args, c)
            case "edit": try edit(args, c)
            case "transform": try transform(args, c)
            case "pin", "unpin": try pin(args, c, pinned: verb == "pin")
            case "delete": try delete(args, c)
            case "merge": try merge(args, c)
            case "clear": try clear(args, c)
            case "collections": try collections(args, c)
            case "collection": try collection(args, c)
            case "settings": try settings(args, c)
            case "ignore": try ignore(args, c)
            case "pause", "resume": try setPreference(["paused", verb == "pause" ? "true" : "false"] + args, c)
            case "import-deck": try importDeck(args, c)
            case "cloud": try cloud(args, c)
            case "shortcut": try shortcut(args, c)
            case "config": try config(args, c)
            case "update": try update(args, c)
            default: throw Failure.usage("未知命令 \(verb)；用 clip --help 查看")
            }
            return Exit.ok.rawValue
        } catch let f as Failure {
            return fail(c, f, json: wantsJSON)
        } catch let e as ClipStore.StoreError {
            if case .missing = e { return fail(c, .notFound(e.description), json: wantsJSON) }
            if e.isBusy { return fail(c, Failure(exit: .busy, code: "busy", message: "剪贴板库正被占用，请稍后重试：\(e)"), json: wantsJSON) }
            return fail(c, Failure(exit: .failure, code: "store", message: e.description), json: wantsJSON)
        } catch let e as DeckImporter.ImportError {
            return fail(c, Failure(exit: .busy, code: "busy", message: e.description), json: wantsJSON)
        } catch let e as ClipRules.ActionError {
            return fail(c, .invalid(e.description), json: wantsJSON)
        } catch let e as CloudArchiveReader.ReaderError {
            return fail(c, .notFound(e.description), json: wantsJSON)
        } catch {
            return fail(c, Failure(exit: .failure, code: "error", message: "\(error)"), json: wantsJSON)
        }
    }

    private static func fail(_ c: Context, _ f: Failure, json: Bool) -> Int32 {
        if json {
            emitJSON(c, f.extra.merging(["error": f.code, "message": f.message, "exit_code": Int(f.exit.rawValue)]) { _, own in own }, ok: false)
        } else {
            c.err("clip \(c.command): \(f.message)")
        }
        return f.exit.rawValue
    }

    // MARK: - Help

    static func usage() -> String {
        """
        usage: clip <command> [options]   （Clip 剪贴板库的命令行；与 Clip.app 同一程序、同一数据、同一份设置）

        读（只读打开库，不写入任何状态）:
          status                     版本、运行状态、数据目录、记录数、记录偏好、Deck、iCloud 开关、辅助功能授权（读回入口）
          stats                      侧栏计数：全部 / 置顶 / 类型 / 来源 app / 收藏夹
          list [筛选]                 与网格相同的顺序（置顶在前、新的在上）与分页
          search <文本> [筛选]        list --query <文本>
          show <id>                  详情：全文、标题、链接标题、文件路径、收藏夹、可用转换
          export <id> -o <file.png>  导出图片原图（--force 覆盖；只写你指定的文件）
          collections                收藏夹及条数
          settings                   记录偏好、复制声音、忽略的 app、已录制的快捷键
          ignore list                忽略名单
          shortcut list              每个动作的快捷键、作用范围与状态（全局键是否注册成功由运行中的 Clip 报告）
          config status              「使用 iCloud 记住配置」开关与可迁移的偏好键
          config export -o <file>    导出配置（--force 覆盖；只写你指定的文件）
        \(AppLifecycleCLI.helpUpdate)
          cloud status               iCloud 归档开关、账户是否绑定、同步状态与错误（Clip 运行时）、归档计数与本机缓存统计
          cloud list [筛选]           本机归档缓存里 iPhone / iPad 可见的历史（与手机列表同一规则；local_id = Mac 库里的同一条）
          cloud show <key>           归档里一条的全文、来源、日期；-o <file> 导出图片（只写你指定的文件）
          version                    版本

        写（沿用窗口里的校验；运行中的 Clip 会重新读取）:
          add (--text <s> | --stdin | --image <file>) [--title <t>] [--from <id>] [--no-fetch-title]
          edit <id> [--text <s> | --stdin] [--title <t>]
          transform <id> <plain|trim|upper|lower|capitalize|one-line|json> [--copy]
          pin <id>                                   置顶
          unpin <id>                                 取消置顶
          merge <id> <id> [<id>...]
          delete <id>... --yes [--dry-run]
          clear --yes [--dry-run]                    清空历史，保留置顶与收藏夹里的
          collection create|edit|move|delete|add|remove …
          settings set <key> <value>                 记录偏好与复制声音
          settings set launchAtLogin true|false [--dry-run]   系统登录项（只对已安装的 Clip，隔离运行时拒绝）
          pause                                      暂停记录
          resume                                     恢复记录
          ignore add <bundle-id>                     加入忽略名单
          ignore remove <bundle-id>                  移出忽略名单
          shortcut scope <动作> application|global    改已录制组合键的作用范围
          shortcut clear <动作>|--all                 清除绑定
          config import <file> --yes                 导入配置（原配置自动备份）
          import-deck [--deck-home <dir>]

        外部动作（只在用户明确要求时用）:
          copy <id>... [--dry-run]                   改写系统剪贴板；单条同时顶到最上
          cloud push|on|off --yes [--dry-run]        请运行中的 Clip「补充最近历史」/ 开关 iCloud 历史归档（上传到你的 iCloud）
          config sync on|off --yes [--dry-run]       请运行中的 Clip 开关「使用 iCloud 记住配置」

        --json（每个命令都支持；另有 --help）:
          成功  {"ok": true,  "command": "<完整命令路径>", …该命令的字段}
          失败  {"ok": false, "command": "<完整命令路径>", "error": "<稳定短码>", "message": "<原因>", "exit_code": N}
          短码：usage · invalid · confirmation_required · not_found · busy · store · app_not_running · system_setting ·
                not_installed · unsupported_edition · sync_enabled · check_incomplete · error

        退出码:
          0  成功（查无结果也算成功）
          1  运行错误
          2  参数错误，或缺少 --yes
          3  记录 / 收藏夹 / 库 / 文件不存在
          4  需要运行中的 Clip 或已安装的 App（本地版无 iCloud 也是 4）
          5  库或导入正被占用

        环境：CLIPBOOK_HOME（数据目录）· CLIPBOOK_PREFERENCES_SUITE（偏好域）· CLIPBOOK_BACKGROUND=1（配合前两者时改用隔离剪贴板）
        仅在窗口中（要真人，或只在窗口里有意义）：
          粘贴到前一个 App（切回它并合成 ⌘V）· 录制快捷键（要真人按键）· 辅助功能「去授权…」（系统授权弹窗）· 试听音效 ·
          网格里的选择（单击、⌘/⇧ 多选、方向键、全选、取消）· 显示 / 隐藏主窗口 · 打开设置窗口与「配置与更新…」窗口 ·
          聚焦搜索 · 编辑菜单（撤销、重做、剪切、粘贴、全选）· 在 Finder 中显示 · 在浏览器打开 · 打开数据目录 ·
          关于 / 隐藏 / 最小化 / 关闭窗口 / 退出。
        仅在 iPhone / iPad 上（手机端要真人，或只在手机里有意义）：
          前往 App Store · 使用方式与隐私支持页 · 链接入口与外接键盘方向键选取 · 打开设置页与「配置与更新」页。
        暂无命令（窗口里看得到，命令还读不到或做不了）：
          升级到新版 / 下载新版：命令不做静默安装；update check 给出新版、按钮名、安装包地址与步骤，替换并重启仍在
            「配置与更新…」窗口里确认。
          只有运行中的 Clip 知道的三样：辅助功能是否已授权（status 的 permissions.accessibility）、全局快捷键是否注册成功
            （shortcut list 的 registration）、iCloud 实时同步状态与错误（cloud status 的 live）。App 把它们写进数据目录的
            runtime-state.json、命令照读的通道已做好，但还没在运行中的 Clip 上核过，没核过之前读到的是 null / app_not_running。
        命令不弹窗、不抢焦点、不申请权限、不合成按键。
        """
    }

    static let filterHelp = """
          --query <文本>      搜索正文、标题、链接标题、来源 app
          --kind <类型>       text | richText | link | image | file | code | color
          --app <bundle-id>   来源 app（stats 列出）
          --collection <id|名字>
          --pinned            只看置顶
          --page N            第 N 页（从 1 开始）  --limit N  每页条数（默认 50，最多 1000）
          --no-text           只输出元数据，不输出正文、标题与路径
          --json
        """

    static let help: [String: String] = [
        "status": "usage: clip status [--json]\n版本、App 是否在运行、数据目录与库大小、记录数、最近记录时间、记录偏好、开机自启状态、Deck 导入、iCloud 开关。只读。\npermissions.accessibility：Clip.app 的辅助功能授权（只用于窗口里的自动粘贴），由运行中的 App 报告；trusted 为 true | false | null（这一版还没运行过），live = 报告它的 App 仍在运行，as_of = 报告时间。",
        "stats": "usage: clip stats [--json]\n与左栏一致的计数：全部、置顶、各类型、来源 app（全部，按条数）、各收藏夹。只读。",
        "list": "usage: clip list [选项]\n与网格相同的排序与筛选。只读。\n" + filterHelp,
        "search": "usage: clip search <文本> [选项]\n等同 clip list --query <文本>。只读。\n" + filterHelp,
        "show": "usage: clip show <id> [--no-text] [--json]\n右栏详情：全文、标题、链接页面标题、来源、时间、大小、文件路径（含是否存在）、原图/RTF 文件路径、收藏夹、可用转换。只读。",
        "export": "usage: clip export <id> -o <file.png> [--force] [--json]\n把图片记录的原图（PNG）复制到指定路径；目标已存在时需 --force。非图片记录退出码 2。",
        "copy": "usage: clip copy <id>... [--dry-run] [--json]\n把记录写入系统剪贴板（改写用户当前剪贴板，仅在用户明确要求时使用）。单条：与「复制」按钮相同并顶到最上；多条：按给出的顺序，文本以空行连接，文件和图片保留原生载荷。--dry-run 只检查不写入。\nClip 的写入带 org.nspasteboard.source 标记，运行中的 Clip 不会把它当成新复制再记录一次。",
        "add": "usage: clip add (--text <s> | --stdin | --image <file>) [--title <t>] [--from <id>] [--no-fetch-title] [--json]\n新增一条记录（与复制入库同一路径：自动识别类型；同内容已存在时顶到最上，来源也像再次复制一样改记为这次的来源，JSON 的 previous_source 给出原来源）。来源记为 Clip CLI（cyou.tianli.clipbook.cli）；--from <id> 与「另存」相同，沿用那条记录的来源和标题。链接会按设置抓取页面标题（--no-fetch-title 跳过）。不受「暂停记录」影响（与「另存」一致）。按「最多保留 / 保留时长」淘汰旧的无保护记录。",
        "edit": "usage: clip edit <id> [--text <s> | --stdin] [--title <t>] [--json]\n与右栏「保存」相同，只写有变化的部分：改标题；正文与原来不同时才重写——重新识别类型、富文本降为纯文本（RTF 删除）、与另一条重复时删掉另一条；正文相同则保持原样（富文本不降级）。先校验全部参数再写，被拒绝时记录不变。图片、文件只能改标题。",
        "transform": "usage: clip transform <id> <plain|trim|upper|lower|capitalize|one-line|json> [--copy] [--json]\n「转换」菜单：结果保存到这条记录。plain 只用于富文本；图片、文件不能转换。默认不动剪贴板，--copy 同时写入剪贴板（窗口里的行为）。",
        "pin": "usage: clip pin <id> [--json]\n置顶（置顶的不会被淘汰或清空）。",
        "unpin": "usage: clip unpin <id> [--json]\n取消置顶。",
        "version": "usage: clip version [--json]\n版本、构建号与版本类型（icloud / local）。只读，不接受其他参数。",
        "delete": "usage: clip delete <id>... --yes [--dry-run] [--json]\n删除记录及其图片/RTF 文件，不可撤销；必须带 --yes。--dry-run 只报告将删除的条数。不删除 iCloud 归档（与 App 相同）。",
        "merge": "usage: clip merge <id> <id> [<id>...] [--json]\n按给出的顺序以空行合并成一条新文本（原条目保留）。至少两条；图片、文件不能合并。",
        "clear": "usage: clip clear --yes [--dry-run] [--json]\n清空历史，保留置顶和收藏夹里的，不可撤销；必须带 --yes。--dry-run 只报告将删除的条数。",
        "collections": "usage: clip collections [--json]\n收藏夹（顺序、名字、图标、颜色、条数）。只读。",
        "collection": """
            usage: clip collection <子命令> … [--json]
              create <名字> [--icon <图标>] [--color <#hex>]
              edit <id|名字> [--name <名字>] [--icon <图标>] [--color <#hex>]
              move <id|名字> up|down
              delete <id|名字> --yes            删除收藏夹（记录保留）；App 里不确认，命令行要求 --yes
              add <id|名字> <记录id>...
              remove <id|名字> <记录id>...
            图标：\(CollectionStyle.icons.joined(separator: " "))
            颜色：\(CollectionStyle.colors.joined(separator: " "))
            """,
        "settings": """
            usage: clip settings [--json]
                   clip settings set <key> <value> [--json]
            key：paused | plainTextOnly | fetchLinkTitles | copySound（true/false）
                 maxItems（100–100000）| retentionDays（0 7 30 90 365，0 = 不限）
                 copySoundName（/System/Library/Sounds 里的名字）| copySoundVolume（0–1）
                 launchAtLogin（true/false，[--dry-run]）：系统登录项，与设置页开关同一代码；只对安装在 Applications 的 Clip，
                 隔离运行（CLIPBOOK_HOME / CLIPBOOK_PREFERENCES_SUITE）时退出码 4
            与设置页相同的取值范围；写入后通知运行中的 Clip 重新读取。快捷键只在 App 里录制（范围与清除见 clip shortcut）。
            """,
        "shortcut": """
            usage: clip shortcut [list] [--json]
                   clip shortcut scope <动作> application|global [--json]
                   clip shortcut clear <动作> [--json]
                   clip shortcut clear --all [--json]
            设置 → 快捷键。动作：\(ClipAction.allCases.map(\.rawValue).joined(separator: " "))
            list：每个动作已保存的组合键与作用范围（application = 仅 Clip 内，global = 全局）。只读。
                  全局键由运行中的 Clip 注册并报告结果：registration 为 registered | failed（status 是窗口里那句话）；
                  Clip 未运行为 app_not_running，还没报告为 unknown，这两种 status 写「已保存」而不是「已启用」；仅 Clip 内的键为 not_needed。
            scope：改已录制组合键的作用范围，沿用窗口里的校验（保留组合、重复绑定会被拒绝，退出码 2）。
            clear：清除一个动作的绑定；--all =「清除所有快捷键」。
            组合键本身要真人按下，只在窗口里录制；默认不绑定任何键，命令也不会替你新增组合键。
            """,
        "config": """
            usage: clip config [status] [--json]
                   clip config export -o <file.json> [--force] [--json]
                   clip config import <file.json> --yes [--json]
                   clip config sync on|off --yes [--dry-run] [--json]
            「配置与更新」窗口。可迁移的偏好：\(ClipPortableConfiguration.keys.joined(separator: " "))
            status：「使用 iCloud 记住配置」是否开启、可迁移的偏好键。只读。
            export：与「导出配置…」相同的文件；目标已存在时需 --force。
            import：与「导入配置…」相同：先备份原配置再覆盖，必须 --yes；运行中的 Clip 随后重新读取。
                    「使用 iCloud 记住配置」开着时退出码 4（同步由运行中的 App 负责：在窗口里导入，或先 sync off）。
            sync：请运行中的 Clip 拨动「使用 iCloud 记住配置」；必须 --yes，Clip 未运行时退出码 4，结果用 config status 回读。
            检查更新见 clip update check；升级到新版仍在窗口里确认。
            """,
        "update": """
            usage: clip update check [--json]
            「配置与更新」窗口的「检查更新」，走共享的命令层（与窗口同一个发行渠道、同一套版本比较）。只读，不下载、不安装。
            --json：current{version, build}、source{kind, …}、latest{version, build, channel, download_url, release_url, sha256, size_bytes}、
                    update_available、state（update_available | up_to_date | ahead_of_channel）、message（窗口里那句话）、
                    upgrade{in_app, button, how, download_url}。
            读不到发行记录时退出码 1、短码 check_incomplete（JSON 仍带 current 与 source）。
            iCloud 版读本人 iCloud Drive 里的发行记录：启动它的终端没有 iCloud Drive 访问权限时，系统可能向那个终端询问一次；
            公开本地版联网读 GitHub 发行记录。隔离运行（CLIPBOOK_HOME / CLIPBOOK_PREFERENCES_SUITE）不读本人的 iCloud Drive。
            升级到新版 / 下载新版没有命令：upgrade.how 给出步骤，替换并重启 App 仍要在窗口里确认。
            """,
        "ignore": "usage: clip ignore [list] | clip ignore add <bundle-id> | clip ignore remove <bundle-id> [--json]\n「忽略这些 app 的复制」名单。",
        "pause": "usage: clip pause [--json]\n暂停记录（= clip settings set paused true）。",
        "resume": "usage: clip resume [--json]\n恢复记录（= clip settings set paused false）。",
        "import-deck": "usage: clip import-deck [--deck-home <dir>] [--json]\n与设置页「导入 Deck 历史」相同：只读复制 Deck 的库再导入，同内容合并，可重复执行。同一时间只允许一个导入（App 或命令行），另一个在跑时退出码 5。",
        "cloud": """
            usage: clip cloud status [--json]
                   clip cloud list [--favorites | --kind text|link|image] [--query <文本>] [--limit N] [--no-text] [--json]
                   clip cloud show <key> [-o <file>] [--force] [--no-text] [--json]
                   clip cloud push --yes [--dry-run] [--json]
                   clip cloud on|off --yes [--dry-run] [--json]
            status：iCloud 历史归档开关、是否已绑定账户（只给是否）、归档标记计数、最近 500 条里待归档条数、来自 iPhone 的记录数、本机归档缓存统计。
            status 读的是这台 Mac 的开关与归档缓存；live 是运行中的 Clip 报告的同步状态文字、整理状态与错误（Clip 未运行或还没打开归档时为 null，live_status 写明原因）。手机那一侧的开关与状态读不到。
            list：本机归档缓存里 iPhone/iPad 可见的历史。只读打开，列表规则就是手机端 ClipLibrary.list（同一份代码：每个内容取最新一行、删除标记隐藏、新的在上），新鲜度取决于 App 上次同步。
                  JSON 每条带 local_id：Mac 库里对应的记录 id（没有或已清理为 null），可接 clip copy / clip show。
            show：手机详情页的内容——全文、标题、来源、日期、是否收藏；图片给出字节数，-o <file> 导出原图（已存在要 --force）。key 可只给前缀（唯一即可）。只读。
            push：请运行中的 Clip 执行 设置 → iCloud「补充最近历史」（归档未开时退出码 2）。
            on / off：请运行中的 Clip 拨动「iCloud 历史归档」开关（App 做账户检查）。
            push/on/off 会上传或停止同步你的 iCloud：必须 --yes；--dry-run 只报告；Clip 未运行时退出码 4；结果用 cloud status 回读。
            手机端收藏/删除只在 iPhone/iPad 上做。
            """,
    ]

    // MARK: - Output

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    static func iso(_ d: Date?) -> Any { d.map { isoFormatter.string(from: $0) } ?? NSNull() }

    /// `command` is the full command path computed once in run() (e.g. "collection create"), identical on success and failure.
    static func emitJSON(_ c: Context, _ body: [String: Any], ok: Bool = true) {
        var object = body
        object["ok"] = ok
        object["command"] = c.command
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        c.out(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Arguments

    struct Parsed {
        var positionals: [String] = []
        var flags: Set<String> = []
        var options: [String: String] = [:]
        var json: Bool { flags.contains("json") }
        func has(_ flag: String) -> Bool { flags.contains(flag) }
        func int(_ name: String) throws -> Int? {
            guard let v = options[name] else { return nil }
            guard let n = Int(v) else { throw Failure.usage("--\(name) 需要整数，收到 \(v)") }
            return n
        }
    }

    static func parse(_ args: [String], flags: Set<String> = [], options: Set<String> = [], positionals: ClosedRange<Int>) throws -> Parsed {
        var p = Parsed()
        let flags = flags.union(["json"])
        var i = 0
        var literal = false
        while i < args.count {
            let a = args[i]
            if literal || !a.hasPrefix("-") || a == "-" || Int(a) != nil { p.positionals.append(a); i += 1; continue }
            if a == "--" { literal = true; i += 1; continue }
            var name = a == "-o" ? "output" : String(a.drop(while: { $0 == "-" }))
            var inline: String?
            if let eq = name.firstIndex(of: "=") { inline = String(name[name.index(after: eq)...]); name = String(name[..<eq]) }
            if flags.contains(name), inline == nil { p.flags.insert(name); i += 1; continue }
            if options.contains(name) {
                if let inline { p.options[name] = inline; i += 1; continue }
                guard i + 1 < args.count else { throw Failure.usage("--\(name) 缺少取值") }
                p.options[name] = args[i + 1]; i += 2; continue
            }
            throw Failure.usage("不认识的选项 \(a)")
        }
        guard positionals.contains(p.positionals.count) else {
            throw Failure.usage(positionals.lowerBound == positionals.upperBound
                                ? "需要 \(positionals.lowerBound) 个参数，收到 \(p.positionals.count) 个"
                                : "参数个数应在 \(positionals.lowerBound)–\(positionals.upperBound == Int.max ? "∞" : String(positionals.upperBound)) 之间，收到 \(p.positionals.count) 个")
        }
        return p
    }

    static func recordID(_ s: String) throws -> Int64 {
        guard let id = Int64(s), id > 0 else { throw Failure.usage("记录 id 应为正整数，收到 \(s)") }
        return id
    }

    // MARK: - Shared helpers

    struct HostInfo { let name: String, version: String, build: String, bundleID: String, path: String, edition: String }

    static func hostInfo() -> HostInfo {
        let b = Bundle.main
        return HostInfo(name: ProductIdentity.name == "clip" ? "Clip" : ProductIdentity.name,
                        version: b.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                        build: b.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                        bundleID: b.bundleIdentifier ?? "", path: b.bundlePath,
                        edition: ProductIdentity.cloudSupported ? "icloud" : "local")
    }

    static let appBundleID = "cyou.tianli.clipbook"

    static func runningApp() -> [Int32] {
        NSRunningApplication.runningApplications(withBundleIdentifier: appBundleID)
            .map(\.processIdentifier).filter { $0 != getpid() }
    }

    static func readStore(_ c: Context) throws -> ClipStore { try ClipStore(home: c.home, readOnly: true) }

    /// Read-write store with the recording limits the window applies (最多保留 / 保留时长).
    @MainActor static func writeStore(_ c: Context) throws -> ClipStore {
        let store = try ClipStore(home: c.home)
        let s = AppSettings.Stored(c.defaults)
        store.maxItems = RecordingLimits.clampMaxItems(s.maxItems)
        store.retentionDays = s.retentionDays
        return store
    }

    static func item(_ store: ClipStore, _ raw: String) throws -> ClipItem {
        let id = try recordID(raw)
        guard let it = try store.item(id: id) else { throw Failure.notFound("没有 id 为 \(id) 的记录") }
        return it
    }

    static func items(_ store: ClipStore, _ raws: [String]) throws -> [ClipItem] {
        var found: [ClipItem] = [], missing: [Int64] = []
        for raw in raws {
            let id = try recordID(raw)
            if let it = try store.item(id: id) { found.append(it) } else { missing.append(id) }
        }
        guard missing.isEmpty else { throw Failure.notFound("没有这些 id 的记录：\(missing.map(String.init).joined(separator: ", "))") }
        return found
    }

    static func changed(_ c: Context) {
        guard c.notify else { return }
        ClipSignal.post(ClipSignal.storeChanged, scope: c.home.path)
    }

    static func kind(_ raw: String) throws -> ClipItem.Kind {
        if let k = ClipItem.Kind.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() || $0.rawValue.lowercased() == raw.replacingOccurrences(of: "-", with: "").lowercased() }) { return k }
        throw Failure.usage("类型应为 \(ClipItem.Kind.allCases.map(\.rawValue).joined(separator: " | "))，收到 \(raw)")
    }

    static func collection(_ store: ClipStore, _ ref: String) throws -> Collection {
        let all = try store.collections()
        if let id = Int64(ref), let c = all.first(where: { $0.id == id }) { return c }
        let named = all.filter { $0.name == ref }
        if named.count == 1 { return named[0] }
        if named.count > 1 { throw Failure.usage("有 \(named.count) 个收藏夹叫「\(ref)」，请用 id") }
        throw Failure.notFound("没有收藏夹 \(ref)")
    }

    static func row(_ it: ClipItem, collections: [Int64], text: Bool) -> [String: Any] {
        var r: [String: Any] = ["id": it.id, "kind": it.kind.rawValue, "app_name": it.appName, "app_bundle": it.appBundle,
                                "created_at": iso(it.createdAt), "pinned": it.pinned, "bytes": it.bytes,
                                "collections": collections, "chars": it.text.count, "lines": it.lineCount]
        if it.kind == .image { r["width"] = it.width; r["height"] = it.height }
        if text {
            r["title"] = it.title
            r["display_title"] = it.displayTitle
            r["preview"] = it.kind == .image ? "" : String(it.text.prefix(200))
            if it.kind == .link { r["link_title"] = it.extra }
        }
        return r
    }

    static func line(_ it: ClipItem, text: Bool) -> String {
        let when = DateFormatter.localizedString(from: it.createdAt, dateStyle: .short, timeStyle: .short)
        let pin = it.pinned ? "📌 " : ""
        let head = "\(it.id)\t\(it.kind.rawValue)\t\(when)\t\(it.appName.isEmpty ? "-" : it.appName)"
        return text ? "\(head)\t\(pin)\(it.displayTitle.prefix(80))" : "\(head)\(it.pinned ? "\tpinned" : "")"
    }

    // MARK: - Reads

    @MainActor static func status(_ args: [String], _ c: Context) throws {
        let p = try parse(args, positionals: 0...0)
        let info = hostInfo()
        let s = AppSettings.Stored(c.defaults)
        let dbURL = ClipStore.databaseURL(home: c.home)
        let fm = FileManager.default
        let bytes = ["", "-wal"].compactMap { (try? fm.attributesOfItem(atPath: dbURL.path + $0))?[.size] as? Int }.reduce(0, +)
        var data: [String: Any] = ["home": c.home.path, "database_exists": fm.fileExists(atPath: dbURL.path), "database_bytes": bytes]
        var total = 0
        if fm.fileExists(atPath: dbURL.path) {
            let store = try readStore(c)
            total = try store.count()
            data["total"] = total
            data["pinned"] = try store.count(.init(pinnedOnly: true))
            data["newest_at"] = iso(try store.newestCreatedAt())
            data["collections"] = try store.collections().count
        } else {
            data["total"] = 0; data["pinned"] = 0; data["newest_at"] = NSNull(); data["collections"] = 0
        }
        let pids = c.runningApp()
        let login: String = {
            switch SMAppService.mainApp.status {
            case .enabled: return "enabled"
            case .requiresApproval: return "requires_approval"
            case .notRegistered: return "not_registered"
            default: return "not_found"
            }
        }()
        let deckAt = fm.fileExists(atPath: dbURL.path) ? (try? readStore(c).meta("deck_imported")) ?? nil : nil
        // Accessibility is granted to Clip.app, and only the app can ask the system about its own grant (this process
        // would be answered for its terminal). It reports what the running app last published, with the time.
        let runtime = ClipRuntimeState.read(home: c.home)
        let live = runtime.map { pids.contains($0.pid) } ?? false
        let accessibility: [String: Any] = ["trusted": runtime.map { $0.accessibilityTrusted as Any } ?? NSNull(), "as_of": iso(runtime?.updatedAt),
                                            "live": live, "reported_by": "running_app",
                                            "used_for": "窗口里的「粘贴到前一个 app」；clip 的命令本身不需要任何系统权限"]
        let body: [String: Any] = [
            "app": ["name": info.name, "version": info.version, "build": info.build, "bundle_id": info.bundleID,
                    "path": info.path, "edition": info.edition],
            "gui": ["running": !pids.isEmpty, "pids": pids],
            "data": data,
            "recording": ["paused": s.paused, "plain_text_only": s.plainTextOnly, "fetch_link_titles": s.fetchLinkTitles,
                          "max_items": s.maxItems, "retention_days": s.retentionDays, "ignored_apps": s.ignoredBundles.count,
                          "copy_sound": s.copySound],
            "launch_at_login": login,
            "deck": ["available": DeckImporter.available(at: c.deckHome), "imported_at": deckAt as Any? ?? NSNull()],
            "icloud": ["supported": ProductIdentity.cloudSupported,
                       "enabled": ProductIdentity.cloudSupported && c.defaults.bool(forKey: "cloudEnabled")],
            "preferences_domain": c.domain,
            "permissions": ["accessibility": accessibility],
        ]
        if p.json { emitJSON(c, body); return }
        let grant = runtime.map { "\($0.accessibilityTrusted ? "已授权" : "未授权")（\(live ? "运行中的 App 报告" : "App 上次运行时报告")）" } ?? "未知（这一版 Clip 还没运行过）"
        c.out("""
        \(info.name) \(info.version) (\(info.build)) · \(info.edition == "icloud" ? "iCloud 版" : "本地版") · App \(pids.isEmpty ? "未运行" : "运行中 pid \(pids.map(String.init).joined(separator: ","))")
        数据：\(c.home.path)（\(total) 条，\(bytes / 1024) KB）
        记录：\(s.paused ? "已暂停" : "记录中") · 纯文本 \(s.plainTextOnly ? "开" : "关") · 链接标题 \(s.fetchLinkTitles ? "开" : "关") · 最多保留 \(s.maxItems) 条 · 保留时长 \(s.retentionDays == 0 ? "不限" : "\(s.retentionDays) 天") · 忽略 \(s.ignoredBundles.count) 个 app
        开机自启：\(login) · Deck：\(DeckImporter.available(at: c.deckHome) ? "可导入" : "未发现")\(deckAt.map { "（上次导入 \($0)）" } ?? "") · iCloud 归档：\(ProductIdentity.cloudSupported ? (c.defaults.bool(forKey: "cloudEnabled") ? "开" : "关") : "本版本不含") · 辅助功能（自动粘贴）：\(grant)
        """)
    }

    @MainActor static func stats(_ args: [String], _ c: Context) throws {
        let p = try parse(args, positionals: 0...0)
        let store = try readStore(c)
        let kinds = try store.kindCounts()
        let apps = try store.appCounts()
        let counts = try store.collectionCounts()
        let cols = try store.collections()
        let total = try store.count(), pinned = try store.count(.init(pinnedOnly: true))
        if p.json {
            emitJSON(c, ["total": total, "pinned": pinned,
                                  "kinds": Dictionary(uniqueKeysWithValues: ClipItem.Kind.allCases.map { ($0.rawValue, kinds[$0] ?? 0) }),
                                  "apps": apps.map { ["bundle": $0.bundle, "name": $0.name, "count": $0.count] },
                                  "collections": cols.map { ["id": $0.id, "name": $0.name, "icon": $0.icon, "color": $0.color, "count": counts[$0.id] ?? 0] }])
            return
        }
        var lines = ["全部 \(total) · 置顶 \(pinned)", "类型：" + ClipItem.Kind.allCases.compactMap { k in kinds[k].map { "\(k.rawValue) \($0)" } }.joined(separator: " · ")]
        lines.append("来源：" + apps.prefix(12).map { "\($0.name) \($0.count)" }.joined(separator: " · ") + (apps.count > 12 ? " …（共 \(apps.count) 个）" : ""))
        lines.append("收藏夹：" + (cols.isEmpty ? "无" : cols.map { "\($0.name)[\($0.id)] \(counts[$0.id] ?? 0)" }.joined(separator: " · ")))
        c.out(lines.joined(separator: "\n"))
    }

    @MainActor static func list(_ args: [String], _ c: Context, verb: String) throws {
        let p = try parse(args, flags: ["pinned", "no-text"], options: ["query", "kind", "app", "collection", "page", "limit"],
                          positionals: verb == "search" ? 1...1 : 0...0)
        let store = try readStore(c)
        var f = ClipStore.Filter(text: verb == "search" ? p.positionals[0] : (p.options["query"] ?? ""))
        if let k = p.options["kind"] { f.kind = try kind(k) }
        if let a = p.options["app"] { f.appBundle = a }
        if let ref = p.options["collection"] { f.collection = try collection(store, ref).id }
        f.pinnedOnly = p.has("pinned")
        let limit = try p.int("limit") ?? 50
        let page = try p.int("page") ?? 1
        guard (1...1000).contains(limit) else { throw Failure.usage("--limit 应在 1–1000") }
        guard page >= 1 else { throw Failure.usage("--page 从 1 开始") }
        let rows = try store.list(f, page: page - 1, pageSize: limit)
        let total = try store.count(f)
        let map = try store.collectionMap(for: rows.map(\.id))
        let text = !p.has("no-text")
        if p.json {
            emitJSON(c, ["total": total, "page": page, "limit": limit, "pages": max(1, (total + limit - 1) / limit),
                               "items": rows.map { row($0, collections: map[$0.id] ?? [], text: text) }])
            return
        }
        c.out(rows.map { line($0, text: text) }.joined(separator: "\n"))
        c.err("\(total) 条，第 \(page)/\(max(1, (total + limit - 1) / limit)) 页")
    }

    @MainActor static func show(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["no-text"], positionals: 1...1)
        let store = try readStore(c)
        let it = try item(store, p.positionals[0])
        let colIDs = try store.collectionIDs(of: it.id)
        let cols = try store.collections().filter { colIDs.contains($0.id) }
        let text = !p.has("no-text")
        var r = row(it, collections: cols.map(\.id), text: text)
        r["editable"] = it.kind.editable
        r["transforms"] = Transform.options(for: it.kind).map(\.cliName)
        r["collection_names"] = text ? cols.map(\.name) : []
        if text {
            r["text"] = it.kind == .image ? "" : it.text
            if it.kind == .file { r["files"] = it.filePaths.map { ["path": $0, "exists": FileManager.default.fileExists(atPath: $0)] } }
            if it.kind == .link { r["url"] = it.text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        if let blob = store.blobURL(it) { r["image_path"] = blob.path; r["image_exists"] = FileManager.default.fileExists(atPath: blob.path) }
        if let rtf = store.rtfURL(it) { r["rtf_path"] = rtf.path }
        if p.json { emitJSON(c, ["item": r]); return }
        var lines = [line(it, text: text)]
        if !it.title.isEmpty && text { lines.append("标题：\(it.title)") }
        if it.kind == .link && !it.extra.isEmpty && text { lines.append("页面标题：\(it.extra)") }
        if !cols.isEmpty { lines.append("收藏夹：" + cols.map { text ? "\($0.name)[\($0.id)]" : "[\($0.id)]" }.joined(separator: " ")) }
        if let blob = store.blobURL(it) { lines.append("原图：\(blob.path)") }
        if text && it.kind != .image { lines.append(""); lines.append(it.text) }
        c.out(lines.joined(separator: "\n"))
    }

    @MainActor static func export(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["force"], options: ["output"], positionals: 1...1)
        guard let out = p.options["output"] else { throw Failure.usage("需要 -o <file.png>") }
        let store = try readStore(c)
        let it = try item(store, p.positionals[0])
        guard it.kind == .image else { throw Failure.invalid("记录 \(it.id) 是 \(it.kind.rawValue)，只有图片可以导出") }
        let dest = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
        if FileManager.default.fileExists(atPath: dest.path) && !p.has("force") { throw Failure.invalid("目标已存在：\(dest.path)（--force 覆盖）") }
        try ClipRules.exportImage(it, store: store, to: dest, overwrite: p.has("force"))
        if p.json { emitJSON(c, ["id": it.id, "path": dest.path, "bytes": (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? 0]) }
        else { c.out(dest.path) }
    }

    // MARK: - External: pasteboard

    @MainActor static func copy(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["dry-run"], positionals: 1...Int.max)
        let dry = p.has("dry-run")
        let store = try (dry ? readStore(c) : writeStore(c))
        let list = try items(store, p.positionals)
        if dry {
            if p.json { emitJSON(c, ["dry_run": true, "would_copy": list.count, "kinds": list.map(\.kind.rawValue)]) }
            else { c.out("将复制 \(list.count) 条（未写入剪贴板）") }
            return
        }
        let board = c.pasteboard()
        let change = Paster.write(list, store: store, pasteboard: board)
        guard change >= 0 else { throw Failure(exit: .failure, code: "copy_failed", message: "复制失败：无法写入剪贴板或原文件不可读") }
        if list.count == 1 { try store.touch(list[0].id); changed(c) }
        if p.json { emitJSON(c, ["copied": list.count, "ids": list.map(\.id), "moved_to_top": list.count == 1]) }
        else { c.out("已复制 \(list.count) 条到剪贴板") }
    }

    // MARK: - Writes

    @MainActor static func add(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["stdin", "no-fetch-title"], options: ["text", "image", "title", "from"], positionals: 0...0)
        let sources = [p.options["text"] != nil, p.has("stdin"), p.options["image"] != nil].filter { $0 }.count
        guard sources == 1 else { throw Failure.usage("需要且只能给一个内容来源：--text、--stdin 或 --image") }
        let store = try writeStore(c)
        var capture: Capture
        if let path = p.options["image"] {
            guard p.options["from"] == nil else { throw Failure.usage("--from 只用于文本（另存）") }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard let data = try? Data(contentsOf: url) else { throw Failure.notFound("读不到图片文件 \(url.path)") }
            guard let cap = ClipRules.imageCapture(data, appName: ClipRules.cliAppName, appBundle: ClipRules.cliBundle,
                                                   title: p.options["title"] ?? "") else { throw Failure.invalid("\(url.path) 不是可读的图片") }
            guard data.count <= 50 * 1024 * 1024 else { throw Failure.invalid("图片超过 50 MB") }
            capture = cap
        } else {
            let text = p.options["text"] ?? String(decoding: c.stdin(), as: UTF8.self)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid("内容为空（与复制一样，纯空白不记录）") }
            if let from = p.options["from"] {
                capture = ClipRules.saveAsNew(from: try item(store, from), text: text)
            } else {
                capture = Capture(kind: Classifier.kind(of: text), text: text, appName: ClipRules.cliAppName, appBundle: ClipRules.cliBundle)
            }
            if let title = p.options["title"] { capture.title = title.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        let previous = try store.existing(capture)
        let existed = previous != nil
        var it = try store.ingest(capture)
        if existed, let title = p.options["title"] { try store.setTitle(it.id, title); it = try store.item(id: it.id) ?? it }
        var fetched: String?
        if it.kind == .link, it.extra.isEmpty, AppSettings.Stored(c.defaults).fetchLinkTitles, !p.has("no-fetch-title") {
            fetched = fetchTitle(it.text)
            if let fetched { try store.setExtra(it.id, fetched) }
        }
        changed(c)
        if p.json {
            // A dedupe is a new copy of the same content (ClipStore.ingest): the record moves to the top and its
            // source becomes this one. previous_source is what it was before.
            emitJSON(c, ["id": it.id, "kind": it.kind.rawValue, "deduplicated": existed, "link_title": fetched as Any? ?? NSNull(),
                         "source": ["app_name": it.appName, "app_bundle": it.appBundle],
                         "previous_source": previous.map { ["app_name": $0.appName, "app_bundle": $0.appBundle] as Any } ?? NSNull(),
                         "total": try store.count()])
        } else {
            c.out("\(it.id)")
            c.err(existed ? "已存在相同内容：顶到最上，来源改记为 \(it.appName)（原为 \(previous?.appName ?? "")；id \(it.id)）"
                          : "已新增 \(it.kind.rawValue) 记录 \(it.id)")
        }
    }

    /// The watcher's link-title fetch (LinkTitle, 256 KiB / 5 s cap), awaited synchronously.
    private static func fetchTitle(_ url: String) -> String? {
        final class Box: @unchecked Sendable { var value: String? }
        let box = Box(), done = DispatchSemaphore(value: 0)
        Task.detached { box.value = await LinkTitle.fetch(url); done.signal() }
        return done.wait(timeout: .now() + 8) == .success ? box.value : nil
    }

    @MainActor static func edit(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["stdin"], options: ["text", "title"], positionals: 1...1)
        let wantsText = p.options["text"] != nil || p.has("stdin")
        guard wantsText || p.options["title"] != nil else { throw Failure.usage("至少给 --text/--stdin 或 --title 之一") }
        guard !(p.options["text"] != nil && p.has("stdin")) else { throw Failure.usage("--text 与 --stdin 只能选一个") }
        let store = try writeStore(c)
        let it = try item(store, p.positionals[0])
        // Validate everything before the first write: a refused edit leaves the record untouched.
        var newText: String?
        if wantsText {
            guard it.kind.editable else { throw Failure.invalid("\(it.kind.rawValue) 记录的正文不能编辑（只能改标题）") }
            let text = p.options["text"] ?? String(decoding: c.stdin(), as: UTF8.self)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid("正文不能为空") }
            newText = text
        }
        // Like the window's 保存: only what differs is written. An unchanged body is not rewritten, so a
        // `show` → `edit --title … --text <same>` round trip keeps rich text (and its RTF) as it is.
        let newTitle = p.options["title"].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let titleChanged = newTitle != nil && newTitle != it.title
        let textChanged = newText != nil && newText != it.text
        var removedDuplicate = false
        defer { if titleChanged || textChanged { changed(c) } }
        if textChanged, let newText {
            let before = try store.count()
            _ = try store.updateText(it.id, text: newText)
            removedDuplicate = try store.count() < before
        }
        if titleChanged, let newTitle { try store.setTitle(it.id, newTitle) }
        guard let updated = try store.item(id: it.id) else { throw Failure.notFound("记录 \(it.id) 已不存在") }
        if p.json {
            emitJSON(c, ["id": updated.id, "kind": updated.kind.rawValue, "title": updated.title, "changed": titleChanged || textChanged,
                         "text_changed": textChanged, "title_changed": titleChanged, "removed_duplicate": removedDuplicate])
        } else {
            c.out((titleChanged || textChanged ? "已保存 " : "未变化 ") + "\(updated.id)（\(updated.kind.rawValue)）" + (removedDuplicate ? "；与之重复的另一条已删除" : ""))
        }
    }

    @MainActor static func transform(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["copy"], positionals: 2...2)
        guard let t = Transform(cliName: p.positionals[1]) else {
            throw Failure.usage("转换应为 \(Transform.allCases.map(\.cliName).joined(separator: " | "))，收到 \(p.positionals[1])")
        }
        let store = try writeStore(c)
        let it = try item(store, p.positionals[0])
        let allowed = Transform.options(for: it.kind)
        guard allowed.contains(t) else {
            throw Failure.invalid(allowed.isEmpty ? "\(it.kind.rawValue) 记录不能转换" : "\(it.kind.rawValue) 记录可用：\(allowed.map(\.cliName).joined(separator: " "))")
        }
        let out = t.apply(it.text)
        let updated = try store.updateText(it.id, text: out)
        var copied = false
        if p.has("copy") {
            guard Paster.write(updated, store: store, pasteboard: c.pasteboard()) >= 0 else {
                changed(c); throw Failure(exit: .failure, code: "copy_failed", message: "已保存，但复制失败")
            }
            copied = true
        }
        changed(c)
        if p.json { emitJSON(c, ["id": updated.id, "transform": t.cliName, "kind": updated.kind.rawValue, "changed": out != it.text, "copied": copied]) }
        else { c.out("\(t.label)：已保存\(copied ? "并写入剪贴板" : "")（\(updated.id)）") }
    }

    @MainActor static func pin(_ args: [String], _ c: Context, pinned: Bool) throws {
        let p = try parse(args, positionals: 1...1)
        let store = try writeStore(c)
        let it = try item(store, p.positionals[0])
        try store.setPinned(it.id, pinned)
        changed(c)
        if p.json { emitJSON(c, ["id": it.id, "pinned": pinned, "changed": it.pinned != pinned]) }
        else { c.out("\(it.id) \(pinned ? "已置顶" : "已取消置顶")") }
    }

    @MainActor static func delete(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["yes", "dry-run"], positionals: 1...Int.max)
        let dry = p.has("dry-run")
        guard dry || p.has("yes") else { throw Failure.confirm("删除不可撤销：确认请加 --yes（或先用 --dry-run 查看）") }
        let store = try (dry ? readStore(c) : writeStore(c))
        let list = try items(store, p.positionals)
        let before = try store.count()
        if dry {
            if p.json { emitJSON(c, ["dry_run": true, "would_delete": list.count, "total": before]) }
            else { c.out("将删除 \(list.count) 条（未执行）") }
            return
        }
        try store.delete(list.map(\.id))
        changed(c)
        let after = try store.count()
        if p.json { emitJSON(c, ["deleted": before - after, "total_before": before, "total_after": after]) }
        else { c.out("已删除 \(before - after) 条，剩 \(after) 条") }
    }

    @MainActor static func merge(_ args: [String], _ c: Context) throws {
        let p = try parse(args, positionals: 2...Int.max)
        let store = try writeStore(c)
        let list = try items(store, p.positionals)
        if let refusal = ClipRules.mergeRefusal(list) { throw Failure.invalid(refusal) }
        let merged = try store.merge(list.map(\.id))
        changed(c)
        if p.json { emitJSON(c, ["id": merged.id, "kind": merged.kind.rawValue, "parts": list.count]) }
        else { c.out("\(merged.id)") }
    }

    @MainActor static func clear(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["yes", "dry-run"], positionals: 0...0)
        let dry = p.has("dry-run")
        guard dry || p.has("yes") else { throw Failure.confirm("清空不可撤销（置顶与收藏夹里的保留）：确认请加 --yes（或先用 --dry-run 查看）") }
        let store = try (dry ? readStore(c) : writeStore(c))
        let before = try store.count(), clearable = try store.clearableCount()
        if dry {
            if p.json { emitJSON(c, ["dry_run": true, "would_delete": clearable, "would_keep": before - clearable]) }
            else { c.out("将删除 \(clearable) 条，保留 \(before - clearable) 条（未执行）") }
            return
        }
        try store.clear(keepPinned: true)
        changed(c)
        let after = try store.count()
        if p.json { emitJSON(c, ["deleted": before - after, "kept": after]) }
        else { c.out("已清空 \(before - after) 条，保留 \(after) 条") }
    }

    // MARK: - Collections

    @MainActor static func collections(_ args: [String], _ c: Context) throws {
        let p = try parse(args, positionals: 0...0)
        let store = try readStore(c)
        let counts = try store.collectionCounts()
        let cols = try store.collections()
        if p.json {
            emitJSON(c, ["collections": cols.map { ["id": $0.id, "name": $0.name, "icon": $0.icon, "color": $0.color, "order": $0.sortOrder, "count": counts[$0.id] ?? 0] }])
        } else {
            c.out(cols.isEmpty ? "（没有收藏夹）" : cols.map { "\($0.id)\t\($0.name)\t\($0.icon)\t\($0.color)\t\(counts[$0.id] ?? 0)" }.joined(separator: "\n"))
        }
    }

    static func validateStyle(icon: String?, color: String?) throws {
        if let icon, !CollectionStyle.icons.contains(icon) { throw Failure.invalid("图标应为 \(CollectionStyle.icons.joined(separator: " "))") }
        if let color, !CollectionStyle.colors.contains(color.lowercased()) { throw Failure.invalid("颜色应为 \(CollectionStyle.colors.joined(separator: " "))") }
    }

    @MainActor static func collection(_ args: [String], _ c: Context) throws {
        guard let sub = args.first else { throw Failure.usage("需要子命令：create | edit | move | delete | add | remove") }
        let rest = Array(args.dropFirst())
        switch sub {
        case "create":
            let p = try parse(rest, options: ["icon", "color"], positionals: 1...1)
            let name = p.positionals[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw Failure.invalid("名字不能为空") }
            try validateStyle(icon: p.options["icon"], color: p.options["color"])
            let store = try writeStore(c)
            let col = try store.createCollection(name: name, color: p.options["color"]?.lowercased() ?? CollectionStyle.defaultColor,
                                                 icon: p.options["icon"] ?? CollectionStyle.defaultIcon)
            changed(c)
            if p.json { emitJSON(c, ["id": col.id, "name": col.name, "icon": col.icon, "color": col.color]) } else { c.out("\(col.id)") }
        case "edit":
            let p = try parse(rest, options: ["name", "icon", "color"], positionals: 1...1)
            guard !p.options.isEmpty else { throw Failure.usage("至少给 --name、--icon 或 --color 之一") }
            try validateStyle(icon: p.options["icon"], color: p.options["color"])
            let store = try writeStore(c)
            var col = try collection(store, p.positionals[0])
            if let name = p.options["name"] {
                let n = name.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty else { throw Failure.invalid("名字不能为空") }
                col.name = n
            }
            if let icon = p.options["icon"] { col.icon = icon }
            if let color = p.options["color"] { col.color = color.lowercased() }
            try store.updateCollection(col)
            changed(c)
            if p.json { emitJSON(c, ["id": col.id, "name": col.name, "icon": col.icon, "color": col.color]) } else { c.out("已保存收藏夹 \(col.id)") }
        case "move":
            let p = try parse(rest, positionals: 2...2)
            guard let delta = ["up": -1, "down": 1][p.positionals[1]] else { throw Failure.usage("方向应为 up 或 down") }
            let store = try writeStore(c)
            let col = try collection(store, p.positionals[0])
            guard let order = ClipRules.reorder(try store.collections().map(\.id), moving: col.id, by: delta) else {
                throw Failure.invalid(delta < 0 ? "已经是第一个" : "已经是最后一个")
            }
            try store.reorderCollections(order)
            changed(c)
            if p.json { emitJSON(c, ["id": col.id, "order": order]) } else { c.out(order.map(String.init).joined(separator: " ")) }
        case "delete":
            let p = try parse(rest, flags: ["yes", "dry-run"], positionals: 1...1)
            let dry = p.has("dry-run")
            guard dry || p.has("yes") else { throw Failure.confirm("删除收藏夹（记录保留）：确认请加 --yes") }
            let store = try (dry ? readStore(c) : writeStore(c))
            let col = try collection(store, p.positionals[0])
            let members = try store.collectionCounts()[col.id] ?? 0
            if !dry { try store.deleteCollection(col.id); changed(c) }
            if p.json { emitJSON(c, ["id": col.id, "dry_run": dry, "released_items": members]) }
            else { c.out(dry ? "将删除收藏夹 \(col.id)（\(members) 条记录移出，记录保留）" : "已删除收藏夹 \(col.id)，\(members) 条记录移出") }
        case "add", "remove":
            let p = try parse(rest, positionals: 2...Int.max)
            let store = try writeStore(c)
            let col = try collection(store, p.positionals[0])
            let list = try items(store, Array(p.positionals.dropFirst()))
            if sub == "add" { try store.add(list.map(\.id), to: col.id) } else { for it in list { try store.remove(it.id, from: col.id) } }
            changed(c)
            let count = try store.collectionCounts()[col.id] ?? 0
            if p.json { emitJSON(c, ["id": col.id, "items": list.map(\.id), "count": count]) }
            else { c.out("收藏夹 \(col.id) 现有 \(count) 条") }
        default:
            throw Failure.usage("未知子命令 \(sub)：create | edit | move | delete | add | remove")
        }
    }

    // MARK: - Settings

    static let settingKeys: [String: String] = [
        "paused": "paused", "plaintextonly": "plainTextOnly", "plain-text-only": "plainTextOnly",
        "fetchlinktitles": "fetchLinkTitles", "fetch-link-titles": "fetchLinkTitles",
        "maxitems": "maxItems", "max-items": "maxItems", "retentiondays": "retentionDays", "retention-days": "retentionDays",
        "copysound": "copySound", "copy-sound": "copySound", "copysoundname": "copySoundName", "copy-sound-name": "copySoundName",
        "copysoundvolume": "copySoundVolume", "copy-sound-volume": "copySoundVolume",
        "launchatlogin": "launchAtLogin", "launch-at-login": "launchAtLogin",
    ]

    @MainActor static func settingsBody(_ c: Context) -> [String: Any] {
        let s = AppSettings.Stored(c.defaults)
        var shortcuts: [[String: Any]] = []
        if let data = c.defaults.data(forKey: ClipShortcuts.storageKey),
           let bindings = try? JSONDecoder().decode([String: ClipBinding].self, from: data) {
            shortcuts = bindings.sorted { $0.key < $1.key }.map { ["action": $0.key, "keys": $0.value.chord.label, "scope": $0.value.scope.rawValue] }
        }
        return ["paused": s.paused, "plainTextOnly": s.plainTextOnly, "fetchLinkTitles": s.fetchLinkTitles, "maxItems": s.maxItems,
                "retentionDays": s.retentionDays, "copySound": s.copySound, "copySoundName": s.copySoundName,
                "copySoundVolume": s.copySoundVolume, "ignoredBundles": s.ignoredBundles, "shortcuts": shortcuts,
                "launchAtLogin": [.enabled, .requiresApproval].contains(SMAppService.mainApp.status),
                "cloudEnabled": ProductIdentity.cloudSupported && c.defaults.bool(forKey: "cloudEnabled"), "domain": c.domain]
    }

    @MainActor static func settings(_ args: [String], _ c: Context) throws {
        if args.first == "set" { try setPreference(Array(args.dropFirst()), c); return }
        let p = try parse(args, positionals: 0...0)
        let body = settingsBody(c)
        if p.json { emitJSON(c, ["settings": body]); return }
        let s = AppSettings.Stored(c.defaults)
        let shortcuts = (body["shortcuts"] as? [[String: Any]]) ?? []
        c.out("""
        paused=\(s.paused) plainTextOnly=\(s.plainTextOnly) fetchLinkTitles=\(s.fetchLinkTitles)
        maxItems=\(s.maxItems) retentionDays=\(s.retentionDays)
        copySound=\(s.copySound) copySoundName=\(s.copySoundName) copySoundVolume=\(s.copySoundVolume)
        ignoredBundles=\(s.ignoredBundles.joined(separator: ","))
        shortcuts=\(shortcuts.isEmpty ? "（未绑定）" : shortcuts.map { "\($0["action"] ?? "")=\($0["keys"] ?? "")(\($0["scope"] ?? ""))" }.joined(separator: " "))
        """)
    }

    static func bool(_ raw: String) throws -> Bool {
        switch raw.lowercased() {
        case "true", "on", "yes", "1": return true
        case "false", "off", "no", "0": return false
        default: throw Failure.invalid("应为 true 或 false，收到 \(raw)")
        }
    }

    /// Writes through AppSettings, i.e. the same keys and didSet persistence as the Settings window,
    /// then asks a running Clip to re-read its preferences.
    @MainActor static func setPreference(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["dry-run"], positionals: 2...2)
        guard let key = settingKeys[p.positionals[0].lowercased()] else {
            throw Failure.usage("不认识的设置 \(p.positionals[0])；可用：paused plainTextOnly fetchLinkTitles maxItems retentionDays copySound copySoundName copySoundVolume launchAtLogin")
        }
        let raw = p.positionals[1]
        if key == "launchAtLogin" { try setLaunchAtLogin(try bool(raw), dry: p.has("dry-run"), c, json: p.json); return }
        guard !p.has("dry-run") else { throw Failure.usage("--dry-run 只用于 launchAtLogin（其他设置可随时改回）") }
        let s = AppSettings(defaults: c.defaults)
        let previous = settingsBody(c)[key] ?? NSNull()
        switch key {
        case "paused": s.paused = try bool(raw)
        case "plainTextOnly": s.plainTextOnly = try bool(raw)
        case "fetchLinkTitles": s.fetchLinkTitles = try bool(raw)
        case "copySound": s.copySound = try bool(raw)
        case "maxItems":
            guard let n = Int(raw), RecordingLimits.maxItemsRange.contains(n) else { throw Failure.invalid("maxItems 应为 \(RecordingLimits.maxItemsRange.lowerBound)–\(RecordingLimits.maxItemsRange.upperBound) 的整数") }
            s.maxItems = n
        case "retentionDays":
            guard let n = Int(raw), RecordingLimits.retentionChoices.contains(n) else { throw Failure.invalid("retentionDays 应为 \(RecordingLimits.retentionChoices.map(String.init).joined(separator: " "))（0 = 不限）") }
            s.retentionDays = n
        case "copySoundName":
            guard CopyFeedback.soundNames.contains(raw) else { throw Failure.invalid("copySoundName 应为 \(CopyFeedback.soundNames.joined(separator: " "))") }
            s.copySoundName = raw
        case "copySoundVolume":
            guard let v = Double(raw), (0...1).contains(v) else { throw Failure.invalid("copySoundVolume 应为 0–1") }
            s.copySoundVolume = v
        default: break
        }
        _ = c.defaults.synchronize()
        if c.notify { ClipSignal.post(ClipSignal.preferencesChanged, scope: c.domain) }
        let value = settingsBody(c)[key] ?? NSNull()
        if p.json { emitJSON(c, ["key": key, "value": value, "previous": previous, "app_running": !c.runningApp().isEmpty]) }
        else { c.out("\(key)=\(value)") }
    }

    /// 设置 → 开机自启: AppSettings.setLaunchAtLogin, the toggle's own code (SMAppService.mainApp for this bundle).
    /// It is a system login item, so an isolated run and a copy outside Applications are refused.
    @MainActor static func setLaunchAtLogin(_ on: Bool, dry: Bool, _ c: Context, json: Bool) throws {
        let settings = AppSettings(defaults: c.defaults)
        let before = settings.launchAtLogin
        let bundle = Bundle.main.bundlePath
        let installed = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
            .contains { bundle.hasPrefix($0) }
        var body: [String: Any] = ["key": "launchAtLogin", "previous": before, "app_path": bundle, "status": settings.launchStatus]
        if dry {
            body["dry_run"] = true; body["would_change"] = before != on; body["installed_copy"] = installed; body["isolated"] = c.isolated
            if json { emitJSON(c, body) } else { c.out("launchAtLogin \(before) → \(on)（未执行）") }
            return
        }
        guard !c.isolated else {
            throw Failure(exit: .needsApp, code: "system_setting", message: "开机自启是系统登录项：隔离运行（CLIPBOOK_HOME / CLIPBOOK_PREFERENCES_SUITE）时不改")
        }
        guard installed else {
            throw Failure(exit: .needsApp, code: "not_installed", message: "开机自启登记的是这份 App 的路径：请用安装在 Applications 里的 Clip 运行 clip（当前 \(bundle)）")
        }
        if before != on {
            settings.setLaunchAtLogin(on)
            if let error = settings.launchError { throw Failure(exit: .failure, code: "launch_at_login", message: error) }
            if c.notify { ClipSignal.post(ClipSignal.preferencesChanged, scope: c.domain) }
        }
        body["value"] = settings.launchAtLogin; body["changed"] = before != settings.launchAtLogin; body["status"] = settings.launchStatus
        if json { emitJSON(c, body) } else { c.out("launchAtLogin=\(settings.launchAtLogin)（\(settings.launchStatus)）") }
    }

    @MainActor static func ignore(_ args: [String], _ c: Context) throws {
        let p = try parse(args, positionals: 0...2)
        let s = AppSettings(defaults: c.defaults)
        let action = p.positionals.first ?? "list"
        if action == "list" {
            guard p.positionals.count <= 1 else { throw Failure.usage("用法：clip ignore list") }
            if p.json { emitJSON(c, ["ignored": s.ignoredBundles]) } else { c.out(s.ignoredBundles.joined(separator: "\n")) }
            return
        }
        guard p.positionals.count == 2, ["add", "remove"].contains(action) else { throw Failure.usage("用法：clip ignore add|remove <bundle-id>") }
        let bundle = p.positionals[1].trimmingCharacters(in: .whitespaces)
        guard !bundle.isEmpty, !bundle.contains(where: \.isWhitespace) else { throw Failure.invalid("bundle id 不能为空或含空白") }
        let before = s.ignoredBundles
        if action == "add", !s.ignoredBundles.contains(bundle) { s.ignoredBundles.append(bundle) }
        if action == "remove" { s.ignoredBundles.removeAll { $0 == bundle } }
        let changedList = before != s.ignoredBundles
        _ = c.defaults.synchronize()
        if changedList && c.notify { ClipSignal.post(ClipSignal.preferencesChanged, scope: c.domain) }
        if p.json { emitJSON(c, ["bundle": bundle, "changed": changedList, "ignored": s.ignoredBundles]) }
        else { c.out(changedList ? "已\(action == "add" ? "加入" : "移出")忽略名单：\(bundle)" : "未变化：\(bundle)") }
    }

    // MARK: - Shortcuts (设置 → 快捷键; recording needs a real key press and stays in the window)

    /// Registration belongs to the running app. This process validates and stores through ClipShortcuts only.
    @MainActor private final class StoredOnlyKeys: ClipKeyRegistration {
        var onPress: ((UInt32) -> Void)?
        func register(_ chord: ClipKey, id: UInt32) -> OSStatus { noErr }
        func unregister(_ id: UInt32) {}
    }

    @MainActor static func shortcut(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["all"], positionals: 0...3)
        let syntax = "用法：clip shortcut list | scope <动作> application|global | clear <动作> | clear --all"
        let center = ClipShortcuts(defaults: c.defaults, backend: StoredOnlyKeys(), monitorsEnabled: false) { _ in }
        func action(_ raw: String) throws -> ClipAction {
            guard let a = ClipAction.allCases.first(where: { $0.rawValue.lowercased() == raw.lowercased() }) else {
                throw Failure.usage("动作应为 \(ClipAction.allCases.map(\.rawValue).joined(separator: " | "))，收到 \(raw)")
            }
            return a
        }
        var changed = false
        switch p.positionals.first ?? "list" {
        case "list":
            guard p.positionals.count <= 1, !p.has("all") else { throw Failure.usage(syntax) }
        case "scope":
            guard p.positionals.count == 3, !p.has("all") else { throw Failure.usage(syntax) }
            let a = try action(p.positionals[1])
            guard let scope = ClipBinding.Scope(rawValue: p.positionals[2].lowercased()) else {
                throw Failure.usage("作用范围应为 application | global，收到 \(p.positionals[2])")
            }
            guard let binding = center.binding(a) else {
                throw Failure.invalid("「\(a.title)」还没有组合键：组合键要在 Clip 的 设置 → 快捷键 里由本人按下录制")
            }
            if binding.scope != scope {
                guard center.set(a, to: ClipBinding(chord: binding.chord, scope: scope)) else {
                    throw Failure.invalid(center.errors[a.rawValue] ?? "无法更改作用范围")
                }
                changed = true
            }
        case "clear":
            if p.has("all") {
                guard p.positionals.count == 1 else { throw Failure.usage(syntax) }
                changed = !center.bindings.isEmpty
                if changed { center.clearAll() }
            } else {
                guard p.positionals.count == 2 else { throw Failure.usage(syntax) }
                let a = try action(p.positionals[1])
                changed = center.binding(a) != nil
                if changed { _ = center.set(a, to: nil) }
            }
        default: throw Failure.usage(syntax)
        }
        if changed {
            _ = c.defaults.synchronize()
            if c.notify { ClipSignal.post(ClipSignal.preferencesChanged, scope: c.domain) }
        }
        // This process registers nothing (StoredOnlyKeys): whether a global key is live is known only to the running
        // app and shown in its 快捷键 page. Say "saved", not "enabled", and mark the registration unknown.
        // registered / failed come from the running app (ClipRuntimeState, same pid, same chord); without it, or right
        // after this command changed a binding (the app is still re-reading), the answer is app_not_running / unknown.
        let pids = c.runningApp()
        let runtime = changed ? nil : ClipRuntimeState.read(home: c.home).flatMap { pids.contains($0.pid) ? $0 : nil }
        let rows: [[String: Any]] = ClipAction.allCases.map { a in
            let b = center.binding(a)
            var registration: Any = NSNull()
            var status = center.status(a)
            if let b, b.scope == .global, center.errors[a.rawValue] == nil {
                if let known = runtime?.shortcuts[a.rawValue], known.keys == b.chord.label {
                    registration = known.registered ? "registered" : "failed"; status = known.status
                } else if pids.isEmpty {
                    registration = "app_not_running"; status = "已保存 · 全局（Clip 未运行，全局键未注册）"
                } else {
                    registration = "unknown"; status = "已保存 · 全局（运行中的 Clip 还没报告注册结果）"
                }
            } else if b != nil { registration = "not_needed" }
            return ["action": a.rawValue, "title": a.title, "keys": b.map { $0.chord.label as Any } ?? NSNull(),
                    "scope": b.map { $0.scope.rawValue as Any } ?? NSNull(), "status": status, "registration": registration]
        }
        if p.json { emitJSON(c, ["shortcuts": rows, "changed": changed, "app_running": !pids.isEmpty]); return }
        c.out(rows.map { "\($0["action"] ?? "")\t\(($0["keys"] as? String) ?? "-")\t\(($0["scope"] as? String) ?? "-")\t\($0["status"] ?? "")" }.joined(separator: "\n"))
    }

    // MARK: - 配置与更新 (the shared AppConfiguration behind the window's export / import / iCloud checkbox)

    /// An isolated run keeps the import marker and the backups inside its own data dir, never the user's.
    @MainActor static func portableConfiguration(_ c: Context) -> AppConfiguration {
        let key = "APP_LIFECYCLE_SUPPORT_DIR"
        let redirect = c.isolated && (ProcessInfo.processInfo.environment[key] ?? "").isEmpty
        if redirect { setenv(key, c.home.appendingPathComponent("Configuration", isDirectory: true).path, 1) }
        defer { if redirect { unsetenv(key) } }
        return ClipPortableConfiguration.make(defaults: c.defaults)
    }

    @MainActor static func config(_ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["yes", "dry-run", "force"], options: ["output"], positionals: 0...2)
        let syntax = "用法：clip config status | export -o <file> [--force] | import <file> --yes | sync on|off --yes [--dry-run]"
        let configuration = portableConfiguration(c)
        let running = !c.runningApp().isEmpty
        func path(_ raw: String) -> URL { URL(fileURLWithPath: (raw as NSString).expandingTildeInPath) }
        switch p.positionals.first ?? "status" {
        case "status":
            guard p.positionals.count <= 1 else { throw Failure.usage(syntax) }
            if p.json { emitJSON(c, ["sync_enabled": configuration.enabled, "keys": ClipPortableConfiguration.keys, "app_running": running]) }
            else { c.out("使用 iCloud 记住配置：\(configuration.enabled ? "开" : "关") · 可迁移的偏好：\(ClipPortableConfiguration.keys.joined(separator: " "))") }
        case "export":
            guard p.positionals.count == 1, let raw = p.options["output"] else { throw Failure.usage(syntax) }
            let url = path(raw)
            guard p.has("force") || !FileManager.default.fileExists(atPath: url.path) else { throw Failure.invalid("\(url.path) 已存在；加 --force 覆盖") }
            let data = try configuration.exportData()
            try data.write(to: url, options: .atomic)
            if p.json { emitJSON(c, ["path": url.path, "bytes": data.count]) } else { c.out("已导出配置：\(url.path)") }
        case "import":
            guard p.positionals.count == 2 else { throw Failure.usage(syntax) }
            let url = path(p.positionals[1])
            guard let data = FileManager.default.contents(atPath: url.path) else { throw Failure.notFound("没有文件 \(url.path)") }
            guard p.has("yes") else { throw Failure.confirm("导入会覆盖当前的记录偏好与快捷键（原配置自动备份）：确认请加 --yes") }
            guard !configuration.enabled else {
                throw Failure(exit: .needsApp, code: "sync_enabled", message: "「使用 iCloud 记住配置」开着，同步由运行中的 Clip 负责：请在「配置与更新」窗口里导入，或先 clip config sync off --yes")
            }
            do { try configuration.importData(data) }
            catch { throw Failure.invalid("导入未完成，原配置不变：\(error.localizedDescription)") }
            _ = c.defaults.synchronize()
            if c.notify { ClipSignal.post(ClipSignal.preferencesChanged, scope: c.domain) }
            if p.json { emitJSON(c, ["imported": true, "path": url.path, "settings": settingsBody(c), "app_running": running]) }
            else { c.out("已导入配置；原配置已备份") }
        case "sync":
            guard p.positionals.count == 2 else { throw Failure.usage(syntax) }
            let target = try bool(p.positionals[1])
            let noop = configuration.enabled == target
            var body: [String: Any] = ["action": target ? "on" : "off", "sync_enabled": configuration.enabled, "app_running": running, "check_with": "clip config status"]
            if p.has("dry-run") {
                body["dry_run"] = true; body["would_change"] = !noop
                if p.json { emitJSON(c, body) } else { c.out(noop ? "已是\(target ? "开" : "关")，不会发请求" : "将请 Clip \(target ? "打开" : "关闭")「使用 iCloud 记住配置」（未执行）") }
                return
            }
            if noop {
                body["requested"] = false; body["changed"] = false
                if p.json { emitJSON(c, body) } else { c.out("「使用 iCloud 记住配置」已是\(target ? "开" : "关")") }
                return
            }
            guard p.has("yes") else { throw Failure.confirm("会\(target ? "开始把配置同步到" : "停止同步配置到")你的 iCloud：确认请加 --yes（或先 --dry-run）") }
            guard running else { throw Failure(exit: .needsApp, code: "app_not_running", message: "配置同步由运行中的 Clip 负责：请先打开 Clip 再重试") }
            if c.notify { ClipSignal.post(target ? ClipSignal.configSyncEnableRequested : ClipSignal.configSyncDisableRequested, scope: c.domain) }
            body["requested"] = true
            if p.json { emitJSON(c, body) } else { c.out("已请 Clip \(target ? "打开" : "关闭")「使用 iCloud 记住配置」；用 clip config status 查看结果") }
        default: throw Failure.usage(syntax)
        }
    }

    // MARK: - 检查更新 (the shared command layer behind the window's 检查更新 button)

    /// `clip update check` runs AppLifecycleCLI with the window's own update source and re-wraps its answer in clip's
    /// envelope (flat "error" code plus "exit_code"), so every clip command answers in one shape.
    @MainActor static func update(_ args: [String], _ c: Context) throws {
        // An isolated run never reads the user's iCloud Drive: the shared layer then accepts only a test feed (APP_LIFECYCLE_CLOUD_DIR).
        let key = "APP_LIFECYCLE_SUPPORT_DIR"
        let redirect = c.isolated && (ProcessInfo.processInfo.environment[key] ?? "").isEmpty
        if redirect { setenv(key, c.home.appendingPathComponent("Configuration", isDirectory: true).path, 1) }
        defer { if redirect { unsetenv(key) } }
        let json = args.contains("--json")
        var printed: [String] = [], complaints: [String] = []
        var product = AppLifecycleCLI.Product(command: "clip", name: hostInfo().name, configuration: nil, updateSource: ClipUpdates.source)
        product.out = { printed.append($0) }
        product.err = { complaints.append($0) }
        product.runningApp = c.runningApp
        let code = AppLifecycleCLI.run(["update"] + args.filter { $0 != "--json" } + ["--json"], product: product)
        var body = (try? JSONSerialization.jsonObject(with: Data(printed.joined(separator: "\n").utf8))) as? [String: Any] ?? [:]
        body.removeValue(forKey: "ok"); body.removeValue(forKey: "command")
        if code == 0 {
            if json { emitJSON(c, body) }
            else { c.out([body["message"] as? String, body["update_available"] as? Bool == true ? (body["upgrade"] as? [String: Any])?["how"] as? String : nil].compactMap { $0 }.joined(separator: "\n")) }
            return
        }
        let error = body.removeValue(forKey: "error") as? [String: Any]
        throw Failure(exit: code == 2 ? .usage : .failure, code: error?["code"] as? String ?? "error",
                      message: error?["message"] as? String ?? complaints.joined(separator: " "), extra: body)
    }

    // MARK: - Deck

    @MainActor static func importDeck(_ args: [String], _ c: Context) throws {
        let p = try parse(args, options: ["deck-home"], positionals: 0...0)
        let deck = p.options["deck-home"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) } ?? c.deckHome
        guard DeckImporter.available(at: deck) else { throw Failure.notFound("没找到 Deck 的库：\(deck.appendingPathComponent("Deck.sqlite3").path)") }
        let store = try writeStore(c)
        let report = try DeckImporter.run(into: store, deckHome: deck)
        changed(c)
        if p.json {
            emitJSON(c, ["scanned": report.scanned, "imported": report.imported, "skipped": report.skipped, "failed": report.failed,
                                        "by_kind": Dictionary(uniqueKeysWithValues: report.byKind.map { ($0.key.rawValue, $0.value) }),
                                        "imported_at": (try store.meta("deck_imported")) as Any? ?? NSNull(), "total": try store.count()])
        } else { c.out(report.description) }
    }

    // MARK: - iCloud (reads here; changes are run by the app that owns the sync)

    @MainActor static func cloud(_ args: [String], _ c: Context) throws {
        let sub = args.first.flatMap { $0.hasPrefix("-") ? nil : $0 } ?? "status"
        let rest = sub == "status" && args.first != "status" ? args : Array(args.dropFirst())
        switch sub {
        case "status":
            let p = try parse(rest, positionals: 0...0)
            let production = MacClipSync.production
            var body: [String: Any] = ["supported": ProductIdentity.cloudSupported, "environment": production ? "Production" : "Development",
                                       "enabled": ProductIdentity.cloudSupported && c.defaults.bool(forKey: "cloudEnabled"),
                                       "account_bound": c.defaults.string(forKey: MacClipSync.accountKey) != nil]
            // 设置 → iCloud 的状态文字与错误：运行中的 App 发布（ClipRuntimeState），App 未运行就没有同步在进行。
            let pids = c.runningApp()
            let archive = ClipRuntimeState.read(home: c.home).flatMap { pids.contains($0.pid) ? $0 : nil }
            if let archive, let state = archive.cloud {
                body["live_status"] = state.syncStatus
                body["live"] = ["sync_status": state.syncStatus, "archive_status": state.archiveStatus, "error": state.error as Any? ?? NSNull(),
                                "busy": state.busy, "as_of": iso(archive.updatedAt)]
            } else {
                body["live_status"] = pids.isEmpty ? "Clip 未运行，没有同步在进行" : "运行中的 Clip 还没打开 iCloud 归档（归档未开启，或还没报告）"
                body["live"] = NSNull()
            }
            if FileManager.default.fileExists(atPath: ClipStore.databaseURL(home: c.home).path) {
                let store = try readStore(c)
                var markers: [String: Any] = [:]
                for scope in ["v2.Production", "v1"] {
                    markers[scope] = ["archived": try store.metaCount(prefix: "cloudArchive.\(scope)."),
                                      "known_cloud_records": try store.metaCount(prefix: "cloudReceived.\(scope).")]
                }
                body["markers"] = markers
                body["iphone_records_in_history"] = try store.count(.init(appBundle: "cyou.tianli.clipmobile"))
                body["recent_pending"] = try pendingArchive(store)
            }
            if ProductIdentity.cloudSupported, let reader = try? CloudArchiveReader(home: MacClipSync.archiveHome(store: c.home)) {
                let s = try reader.stats()
                body["archive_cache"] = ["path": reader.url.path, "visible": s.visible, "rows": s.rows, "tombstones": s.tombstones,
                                         "favorites": s.favorites, "kinds": s.kinds]
            } else {
                body["archive_cache"] = NSNull()
            }
            if p.json { emitJSON(c, body); return }
            let cacheText = (body["archive_cache"] as? [String: Any]).map { "本机归档缓存 \($0["visible"] ?? 0) 条（收藏 \($0["favorites"] ?? 0)）" } ?? "本机没有归档缓存"
            c.out("iCloud 历史归档：\(ProductIdentity.cloudSupported ? ((body["enabled"] as? Bool ?? false) ? "开" : "关") : "本版本不含") · 账户\((body["account_bound"] as? Bool ?? false) ? "已绑定" : "未绑定") · \(cacheText) · 最近 \(MacClipSync.recentLimit) 条里待归档 \(body["recent_pending"] ?? 0) 条 · 历史里来自 iPhone \(body["iphone_records_in_history"] ?? 0) 条")
        case "list":
            let p = try parse(rest, flags: ["favorites", "no-text"], options: ["kind", "query", "limit"], positionals: 0...0)
            guard ProductIdentity.cloudSupported else { throw Failure(exit: .needsApp, code: "unsupported_edition", message: "本地版不含 iCloud 归档") }
            if let k = p.options["kind"], !["text", "link", "image"].contains(k) { throw Failure.usage("--kind 应为 text | link | image") }
            guard !(p.has("favorites") && p.options["kind"] != nil) else { throw Failure.usage("--favorites 与 --kind 只能选一个（与手机上的筛选相同）") }
            let limit = try p.int("limit") ?? 50
            guard (1...1000).contains(limit) else { throw Failure.usage("--limit 应在 1–1000") }
            let reader = try CloudArchiveReader(home: MacClipSync.archiveHome(store: c.home))
            let filter = p.has("favorites") ? "favorites" : p.options["kind"] ?? "all"
            let entries = try reader.list(search: p.options["query"] ?? "", filter: filter, limit: limit)
            let text = !p.has("no-text")
            let local = localRecords(c)
            if p.json {
                emitJSON(c, ["count": entries.count, "filter": filter, "items": entries.map { e -> [String: Any] in
                    var r: [String: Any] = ["key": e.id, "kind": e.kind, "created_at": iso(e.date == .distantPast ? nil : e.date),
                                            "favorite": e.favorite, "chars": e.text.count, "local_id": local(e.id).map { $0 as Any } ?? NSNull()]
                    if text { r["title"] = e.title; r["display_title"] = e.displayTitle; r["preview"] = String(e.text.prefix(200)); r["source"] = e.source }
                    return r
                }])
            } else {
                c.out(entries.map { e in
                    let when = e.date == .distantPast ? "-" : DateFormatter.localizedString(from: e.date, dateStyle: .short, timeStyle: .short)
                    return "\(e.id.prefix(12))\t\(e.kind)\t\(when)\(e.favorite ? "\t★" : "")" + (text ? "\t\(e.displayTitle.prefix(80))" : "")
                }.joined(separator: "\n"))
            }
        case "show":
            let p = try parse(rest, flags: ["no-text", "force"], options: ["output"], positionals: 1...1)
            guard ProductIdentity.cloudSupported else { throw Failure(exit: .needsApp, code: "unsupported_edition", message: "本地版不含 iCloud 归档") }
            let reader = try CloudArchiveReader(home: MacClipSync.archiveHome(store: c.home))
            let wanted = p.positionals[0]
            let matches = try reader.list(limit: .max).filter { $0.id == wanted || $0.id.hasPrefix(wanted) }
            guard let e = matches.first(where: { $0.id == wanted }) ?? (matches.count == 1 ? matches[0] : nil) else {
                throw matches.isEmpty ? Failure.notFound("归档里没有 key 为 \(wanted) 的可见记录（用 clip cloud list 查看）")
                                      : Failure.usage("有 \(matches.count) 条记录的 key 以 \(wanted) 开头，请给更长的前缀")
            }
            let image = try (e.kind == "image" ? reader.imageData(e) : nil)
            let text = !p.has("no-text")
            var r: [String: Any] = ["key": e.id, "kind": e.kind, "created_at": iso(e.date == .distantPast ? nil : e.date),
                                    "favorite": e.favorite, "chars": e.text.count, "image_bytes": image?.count ?? 0,
                                    "local_id": localRecords(c)(e.id).map { $0 as Any } ?? NSNull()]
            if text { r["title"] = e.title; r["display_title"] = e.displayTitle; r["text"] = e.text; r["source"] = e.source }
            if let out = p.options["output"] {
                guard let image else { throw Failure.invalid("这条归档记录是 \(e.kind)，没有图片可以导出") }
                let dest = URL(fileURLWithPath: (out as NSString).expandingTildeInPath)
                if FileManager.default.fileExists(atPath: dest.path) && !p.has("force") { throw Failure.invalid("目标已存在：\(dest.path)（--force 覆盖）") }
                try image.write(to: dest, options: .atomic)
                r["image_path"] = dest.path
            }
            if p.json { emitJSON(c, ["item": r]); return }
            let when = e.date == .distantPast ? "-" : DateFormatter.localizedString(from: e.date, dateStyle: .short, timeStyle: .short)
            var lines = ["\(e.id.prefix(12))\t\(e.kind)\t\(when)\(e.favorite ? "\t★" : "")" + (text ? "\t\(e.source)" : "")]
            if text, !e.title.isEmpty { lines.append("标题：\(e.title)") }
            if let image { lines.append("图片：\(image.count) 字节" + ((r["image_path"] as? String).map { "，已导出 \($0)" } ?? "（-o <file> 导出）")) }
            if text, e.kind != "image" { lines.append(""); lines.append(e.text) }
            c.out(lines.joined(separator: "\n"))
        case "push", "on", "off":
            try cloudRequest(sub, rest, c)
        default:
            throw Failure.usage("未知子命令 \(sub)：status | list | show | push | on | off")
        }
    }

    /// Archive key → the id of the same record in this Mac's library (MacClipSync writes `cloudReceived.<scope>.<key>`
    /// for what it sent and what it received). nil when there is no library, no marker, or the record is gone.
    @MainActor static func localRecords(_ c: Context) -> (String) -> Int64? {
        guard FileManager.default.fileExists(atPath: ClipStore.databaseURL(home: c.home).path), let store = try? readStore(c) else { return { _ in nil } }
        return { key in
            guard let raw = try? store.meta("cloudReceived.\(MacClipSync.markerScope).\(key)"), let id = Int64(raw),
                  (try? store.item(id: id)) != nil else { return nil }
            return id
        }
    }

    /// Records among the newest 「补充最近历史」 would upload (MacClipSync's own marker rule).
    @MainActor static func pendingArchive(_ store: ClipStore) throws -> Int {
        try store.list(pageSize: MacClipSync.recentLimit).filter { try MacClipSync.needsArchive($0, store: store, scope: MacClipSync.markerScope) }.count
    }

    /// `cloud push|on|off`: the Settings → iCloud button / toggle, run by the running Clip (it owns the sync and the
    /// iCloud account checks). The CLI only asks; the result is read back with `clip cloud status`.
    @MainActor static func cloudRequest(_ sub: String, _ args: [String], _ c: Context) throws {
        let p = try parse(args, flags: ["yes", "dry-run"], positionals: 0...0)
        guard ProductIdentity.cloudSupported else { throw Failure(exit: .needsApp, code: "unsupported_edition", message: "本地版不含 iCloud 归档") }
        let enabled = c.defaults.bool(forKey: "cloudEnabled")
        let pids = c.runningApp()
        var body: [String: Any] = ["action": sub, "icloud_enabled": enabled, "app_running": !pids.isEmpty, "check_with": "clip cloud status"]
        if sub == "push" {
            guard enabled else { throw Failure.invalid("iCloud 历史归档未开启（先 clip cloud on --yes，或在 App 的 设置 → iCloud 里打开）") }
            if FileManager.default.fileExists(atPath: ClipStore.databaseURL(home: c.home).path) { body["would_send"] = try pendingArchive(try readStore(c)) }
        }
        let target = sub == "on"
        let noop = sub != "push" && enabled == target
        if p.has("dry-run") {
            body["dry_run"] = true; body["would_change"] = !noop
            if p.json { emitJSON(c, body) } else { c.out(noop ? "iCloud 历史归档已是\(target ? "开" : "关")，不会发请求" : "将请 Clip \(sub == "push" ? "补充最近历史（\(body["would_send"] ?? 0) 条待归档）" : (target ? "打开" : "关闭") + " iCloud 历史归档")（未执行）") }
            return
        }
        if noop {
            body["requested"] = false; body["changed"] = false
            if p.json { emitJSON(c, body) } else { c.out("iCloud 历史归档已是\(target ? "开" : "关")") }
            return
        }
        guard p.has("yes") else {
            throw Failure.confirm(sub == "push" ? "会把最近的记录上传到你的 iCloud：确认请加 --yes（或先 --dry-run）"
                                  : "会\(target ? "开始把历史同步到" : "停止同步到")你的 iCloud：确认请加 --yes（或先 --dry-run）")
        }
        guard !pids.isEmpty else {
            throw Failure(exit: .needsApp, code: "app_not_running", message: "iCloud 由运行中的 Clip 同步：请先打开 Clip 再重试")
        }
        let name = sub == "push" ? ClipSignal.cloudPushRequested : target ? ClipSignal.cloudEnableRequested : ClipSignal.cloudDisableRequested
        if c.notify { ClipSignal.post(name, scope: c.home.path) }
        body["requested"] = true
        if p.json { emitJSON(c, body) }
        else { c.out("已请 Clip \(sub == "push" ? "补充最近历史" : (target ? "打开" : "关闭") + " iCloud 历史归档")；用 clip cloud status 查看结果") }
    }
}
