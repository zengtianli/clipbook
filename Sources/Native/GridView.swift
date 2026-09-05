import SwiftUI
import AppKit

/// 中栏：批量操作条 + 自适应网格 + 底部搜索/分页
struct GridPane: View {
    @ObservedObject var model: AppModel
    let hideWindow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if model.selection.count > 1 { batchBar; Divider() }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 176, maximum: 260), spacing: 12)], spacing: 12) {
                    ForEach(model.items) { item in
                        CardView(item: item, model: model, selected: model.selection.contains(item.id))
                            // ⌘/⇧ 点选走 TapGesture.modifiers（不依赖 NSApp.currentEvent，2026-09-05 实测后者在窗口非 key 时拿不到修饰键）
                            .highPriorityGesture(TapGesture().modifiers(.command).onEnded { model.click(item.id, modifiers: .command) })
                            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { model.click(item.id, modifiers: .shift) })
                            .onTapGesture(count: 2) { model.copy(item) }
                            .onTapGesture { model.click(item.id, modifiers: []) }
                            .contextMenu { ItemMenu(item: item, model: model, hideWindow: hideWindow) }
                    }
                }
                .padding(14)
            }
            .overlay {
                if model.items.isEmpty {
                    ContentUnavailableView(model.search.isEmpty ? "这里还没有记录" : "没有匹配「\(model.search)」",
                                           systemImage: "doc.on.clipboard",
                                           description: Text(model.search.isEmpty ? "复制点什么，它就会出现在这里" : "换个词，或换个筛选"))
                }
            }
            Divider()
            bottomBar
        }
        .frame(minWidth: 440)
    }

    private var batchBar: some View {
        HStack(spacing: 12) {
            Text("已选 \(model.selection.count) 条").font(.callout.weight(.medium))
            Button("全选本页") { model.selectAll() }.accessibilityIdentifier("selectAll")
            Menu("加入收藏夹") {
                ForEach(model.collections) { c in Button(c.name) { model.add(model.selection, to: c.id) } }
                if model.collections.isEmpty { Text("还没有收藏夹") }
            }
            .accessibilityIdentifier("batchAddToCollection")
            Button("合并成一条") { model.merge(model.items.filter { model.selection.contains($0.id) }.map(\.id)) }
                .disabled(model.items.filter { model.selection.contains($0.id) }.contains { $0.kind == .image || $0.kind == .file })
                .accessibilityIdentifier("merge")
            Button("删除", role: .destructive) { model.delete(model.selection) }.accessibilityIdentifier("batchDelete")
            Spacer()
            Button("取消选择") { model.selection = [] }
        }
        .controlSize(.small)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索正文、标题、来源", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 360)
            Spacer()
            Text("\(model.total) 条").foregroundStyle(.secondary).font(.callout).monospacedDigit()
            if model.pageCount > 1 {
                HStack(spacing: 4) {
                    Button { model.setPage(model.page - 1) } label: { Image(systemName: "chevron.left") }.disabled(model.page == 0)
                    Text("\(model.page + 1) / \(model.pageCount)").font(.callout).monospacedDigit()
                    Button { model.setPage(model.page + 1) } label: { Image(systemName: "chevron.right") }.disabled(model.page >= model.pageCount - 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }
}

/// 右键菜单（网格卡片与详情共用）
struct ItemMenu: View {
    let item: ClipItem
    @ObservedObject var model: AppModel
    let hideWindow: () -> Void

    var body: some View {
        Button("复制") { model.copy(item) }
        Button("粘贴到 \(model.previousApp?.localizedName ?? "前一个 app")") { model.paste(item, hideWindow: hideWindow) }
        Button(item.pinned ? "取消置顶" : "置顶") { model.togglePin(item) }
        Menu("加入收藏夹") {
            ForEach(model.collections) { c in Button(c.name) { model.add([item.id], to: c.id) } }
            if model.collections.isEmpty { Text("还没有收藏夹") }
        }
        if item.kind == .file {
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) }) }
        }
        if item.kind == .link {
            Button("在浏览器打开") { if let u = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) { NSWorkspace.shared.open(u) } }
        }
        Divider()
        Button("删除", role: .destructive) { model.delete([item.id]) }
    }
}

struct CardView: View {
    let item: ClipItem
    @ObservedObject var model: AppModel
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(nsImage: model.appIcon(bundle: item.appBundle)).resizable().frame(width: 14, height: 14)
                Text(item.appName.isEmpty ? "未知来源" : item.appName).lineLimit(1)
                Spacer(minLength: 4)
                Text(Fmt.when(item.createdAt)).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary)

            if !item.title.isEmpty {
                Text(item.title).font(.callout.weight(.semibold)).lineLimit(1)
            }
            preview.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            HStack(spacing: 5) {
                Label(item.kind.label, systemImage: item.kind.symbol).labelStyle(.titleAndIcon)
                Text(Fmt.meta(item))
                Spacer(minLength: 4)
                ForEach(model.collectionMap[item.id] ?? [], id: \.self) { cid in
                    if let c = model.collections.first(where: { $0.id == cid }) {
                        Circle().fill(Color(hex: c.color)).frame(width: 7, height: 7)
                    }
                }
                if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(height: 150)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let img = model.thumbnail(item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 5))
            } else { Text("图片文件不见了").foregroundStyle(.secondary) }
        case .file:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(item.filePaths.prefix(4), id: \.self) { p in
                    HStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 14, height: 14)
                        Text(p.lastPathComponent).lineLimit(1).font(.callout)
                    }
                }
                if item.filePaths.count > 4 { Text("… 共 \(item.filePaths.count) 个").font(.caption).foregroundStyle(.secondary) }
            }
        case .color:
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Color.fromColorString(item.text) ?? .gray).frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines)).font(.system(.body, design: .monospaced))
            }
        case .link:
            VStack(alignment: .leading, spacing: 3) {
                if !item.extra.isEmpty { Text(item.extra).font(.callout).lineLimit(2) }
                Text(item.text.trimmingCharacters(in: .whitespacesAndNewlines)).font(.caption).foregroundStyle(.secondary).lineLimit(item.extra.isEmpty ? 4 : 2)
            }
        case .code:
            Text(item.text).font(.system(size: 11, design: .monospaced)).lineLimit(6)
        default:
            Text(item.text).font(.callout).lineLimit(5)
        }
    }
}

enum Fmt {
    static let rel: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f
    }()

    static func when(_ d: Date) -> String {
        let age = Date().timeIntervalSince(d)
        if age < 60 { return "刚刚" }
        if age < 86400 * 2 { return rel.localizedString(for: d, relativeTo: Date()) }
        return d.formatted(.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    static func full(_ d: Date) -> String {
        d.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN")))
    }

    static func bytes(_ n: Int) -> String {
        n < 1024 ? "\(n) B" : n < 1024 * 1024 ? String(format: "%.0f KB", Double(n) / 1024) : String(format: "%.1f MB", Double(n) / 1048576)
    }

    static func meta(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: return "\(item.width)×\(item.height) · \(bytes(item.bytes))"
        case .file:  return "\(item.filePaths.count) 项"
        default:     return "\(item.text.count) 字 · \(item.lineCount) 行"
        }
    }
}
