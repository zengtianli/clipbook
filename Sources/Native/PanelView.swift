import SwiftUI
import AppKit

/// 面板：左列表 + 右预览。键盘：↑↓ 选、↩ 粘贴、⌘P 置顶、⌘⌫ 删除、esc 关。
struct PanelView: View {
    @ObservedObject var model: AppModel
    let controller: PanelController
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HSplitView {
                list.frame(minWidth: 300, idealWidth: 340)
                preview.frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 620, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: .clipbookPanelShown)) { _ in
            searchFocused = true
        }
        .onAppear { searchFocused = true }
    }

    /// 搜索框的 field editor 里有 marked text = 输入法正在组字
    private var composing: Bool {
        (controller.panel.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    // MARK: 顶部搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索剪贴板历史（\(model.total) 条）", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
                // 输入法组字期间（搜狗拼音等），↑↓↩esc 属于候选框，不能截 —— 否则回车会把
                // 「确认拼音」变成「粘贴当前选中项」（2026-09-05 实测踩到）。
                .onKeyPress(.upArrow)   { composing ? .ignored : { model.moveSelection(-1); return .handled }() }
                .onKeyPress(.downArrow) { composing ? .ignored : { model.moveSelection(+1); return .handled }() }
                .onKeyPress(.return)    { composing ? .ignored : { controller.pasteSelected(); return .handled }() }
                .onKeyPress(.escape)    { composing ? .ignored : { controller.hide(); return .handled }() }
                .onKeyPress(characters: .init(charactersIn: "p"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let it = model.selected else { return .ignored }
                    model.togglePin(it); return .handled
                }
                .onKeyPress(.delete, phases: .down) { press in
                    guard press.modifiers.contains(.command), let it = model.selected else { return .ignored }
                    model.delete(it); return .handled
                }
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    // MARK: 列表

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.items) { item in
                        Row(item: item, model: model, selected: item.id == model.selectedID)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.selectedID = item.id; controller.pasteSelected() }
                            .onTapGesture { model.selectedID = item.id }
                            .contextMenu {
                                Button("粘贴") { model.selectedID = item.id; controller.pasteSelected() }
                                Button(item.pinned ? "取消置顶" : "置顶") { model.togglePin(item) }
                                Divider()
                                Button("删除", role: .destructive) { model.delete(item) }
                            }
                    }
                }
                .padding(6)
            }
            .overlay {
                if model.items.isEmpty {
                    ContentUnavailableView(model.query.isEmpty ? "还没有记录" : "没有匹配",
                                           systemImage: "doc.on.clipboard",
                                           description: Text(model.query.isEmpty ? "复制点什么，它就会出现在这里" : "换个词试试"))
                }
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    // MARK: 预览

    @ViewBuilder
    private var preview: some View {
        if let item = model.selected {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(nsImage: model.appIcon(item)).resizable().frame(width: 18, height: 18)
                    Text(item.appName.isEmpty ? "未知来源" : item.appName).font(.callout.weight(.medium))
                    Text("·").foregroundStyle(.tertiary)
                    Text(Self.when(item.createdAt)).foregroundStyle(.secondary).font(.callout)
                    Spacer()
                    if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                    Text(meta(item)).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider()
                Group {
                    switch item.kind {
                    case .image:
                        if let img = model.thumbnail(item) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
                        } else {
                            ContentUnavailableView("图片文件不见了", systemImage: "photo.badge.exclamationmark")
                        }
                    case .file:
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(item.filePaths, id: \.self) { p in
                                    HStack(spacing: 8) {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: p)).resizable().frame(width: 20, height: 20)
                                        Text(p).font(.callout).textSelection(.enabled).lineLimit(2)
                                    }
                                }
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    default:
                        ScrollView {
                            Text(item.text)
                                .font(.system(size: 13, design: item.kind == .link ? .default : .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView("选一条看看", systemImage: "cursorarrow.click")
        }
    }

    private func meta(_ item: ClipItem) -> String {
        switch item.kind {
        case .image: return "\(item.width)×\(item.height) · \(bytes(item.bytes))"
        case .file:  return "\(item.filePaths.count) 项"
        default:     return "\(item.text.count) 字 · \(item.lineCount) 行"
        }
    }

    private func bytes(_ n: Int) -> String {
        n < 1024 ? "\(n) B" : n < 1024 * 1024 ? String(format: "%.0f KB", Double(n) / 1024) : String(format: "%.1f MB", Double(n) / 1048576)
    }

    // MARK: 底栏

    private var footer: some View {
        HStack(spacing: 14) {
            key("↩", "粘贴"); key("⌘P", "置顶"); key("⌘⌫", "删除"); key("esc", "关闭")
            Spacer()
            if let n = model.notice {
                Text(n).font(.caption).foregroundStyle(.red).lineLimit(1)
            } else if model.deckRunning {
                Label("Deck 还在跑，\(HotKeyCenter.shared.label) 可能被它抢走", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).lineLimit(1)
            } else if !Paster.accessibilityTrusted {
                Label("未授权辅助功能：回车只复制不自动粘贴", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else if model.paused {
                Label("已暂停记录", systemImage: "pause.circle").font(.caption).foregroundStyle(.orange)
            } else {
                Text(HotKeyCenter.shared.status).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
    }

    private func key(_ k: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.caption.monospaced()).padding(.horizontal, 5).padding(.vertical, 1)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

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
}

private struct Row: View {
    let item: ClipItem
    @ObservedObject var model: AppModel
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if item.kind == .image, let img = model.thumbnail(item) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 14)).frame(width: 36, height: 36)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).lineLimit(1).font(.system(size: 13))
                HStack(spacing: 5) {
                    Image(nsImage: model.appIcon(item)).resizable().frame(width: 12, height: 12)
                    Text(item.appName).lineLimit(1)
                    Text("·")
                    Text(PanelView.when(item.createdAt))
                }
                .font(.caption).foregroundStyle(selected ? Color.primary.opacity(0.8) : Color.secondary)
            }
            Spacer(minLength: 0)
            if item.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}
