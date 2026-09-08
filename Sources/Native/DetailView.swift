import SwiftUI
import AppKit

/// 右栏：选中一条 → 看、改、存、转换、收藏、粘贴
struct DetailPane: View {
    @ObservedObject var model: AppModel
    let hideWindow: () -> Void
    @State private var draft = ""
    @State private var titleDraft = ""
    @State private var editingRich = false
    @State private var loadedID: Int64?

    var body: some View {
        Group {
            if let item = model.detail {
                content(item)
                    .onAppear { load(item) }
                    .onChange(of: item.id) { _, _ in load(item) }
                    .onChange(of: item.text) { _, new in if !dirty(item) { draft = new } }
            } else if model.selection.count > 1 {
                ContentUnavailableView("已选 \(model.selection.count) 条", systemImage: "square.stack.3d.up", description: Text("按 ⌘C 或点击上方「复制」可复制全部所选内容，也可删除、加入收藏夹或合并"))
            } else {
                ContentUnavailableView("选一条看看", systemImage: "cursorarrow.click", description: Text("单击选中，双击复制，右键更多"))
            }
        }
        .frame(minWidth: 320)
        .onDisappear {
            if let id = loadedID { model.savedDraft = .init(id: id, text: draft, title: titleDraft, rich: editingRich) }
        }
        .onChange(of: draft) { _, _ in rememberDraft() }
        .onChange(of: titleDraft) { _, _ in rememberDraft() }
        .onChange(of: editingRich) { _, _ in rememberDraft() }
        .onReceive(NotificationCenter.default.publisher(for: ClipAction.requested)) { note in
            if note.object as? ClipAction == .save, let item = model.detail, item.kind.editable { save(item) }
        }
    }

    private func load(_ item: ClipItem) {
        if let saved = model.savedDraft, saved.id == item.id {
            draft = saved.text; titleDraft = saved.title; editingRich = saved.rich; loadedID = item.id
            model.savedDraft = nil
            return
        }
        draft = item.text
        titleDraft = item.title
        editingRich = false
        loadedID = item.id
    }

    private func dirty(_ item: ClipItem) -> Bool { draft != item.text }

    private func rememberDraft() {
        if let id = loadedID { model.savedDraft = .init(id: id, text: draft, title: titleDraft, rich: editingRich) }
    }

    @ViewBuilder
    private func content(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(item)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                TextField("标题（留空用正文首行）", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setTitle(item, titleDraft) }
                body(item)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            actions(item)
        }
    }

    private func header(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: model.appIcon(bundle: item.appBundle)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.appName.isEmpty ? "未知来源" : item.appName).font(.callout.weight(.medium))
                Text("\(Fmt.full(item.createdAt)) · \(item.kind.label) · \(Fmt.meta(item))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
            ForEach(Array(model.detailCollections), id: \.self) { cid in
                if let c = model.collections.first(where: { $0.id == cid }) {
                    Label(c.name, systemImage: c.icon).font(.caption).foregroundStyle(Color(hex: c.color))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: c.color).opacity(0.12), in: Capsule())
                        .contextMenu { Button("移出「\(c.name)」") { model.remove(item.id, from: c.id) } }
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    @ViewBuilder
    private func body(_ item: ClipItem) -> some View {
        switch item.kind {
        case .image:
            if let img = model.thumbnail(item, maxPixels: 1600) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
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
                            if !FileManager.default.fileExists(atPath: p) { Text("已不存在").font(.caption).foregroundStyle(.red) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        case .richText where !editingRich:
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    if let a = model.richText(item) {
                        Text(AttributedString(a)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
                Button("编辑（保存后变纯文本）") { editingRich = true }.controlSize(.small)
            }
        case .color:
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(Color.fromColorString(draft) ?? .gray).frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                editor(item)
            }
        default:
            if item.kind == .link {
                if !item.extra.isEmpty { Text(item.extra).font(.callout.weight(.medium)).lineLimit(2) }
            }
            editor(item)
        }
    }

    private func editor(_ item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $draft)
                .font(.system(size: 13, design: item.kind == .code ? .monospaced : .default))
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(dirty(item) ? Color.accentColor : Color.primary.opacity(0.1)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text("\(draft.count) 字").font(.caption).foregroundStyle(.secondary)
                if dirty(item) { Text("· 有未保存的修改").font(.caption).foregroundStyle(Color.accentColor) }
                Spacer()
                Menu("转换") {
                    ForEach(Transform.allCases.filter { $0 != .plain || item.kind == .richText }) { t in
                        Button(t.label) { model.apply(t, to: item) }
                    }
                }
                .controlSize(.small).fixedSize()
            }
        }
    }

    private func actions(_ item: ClipItem) -> some View {
        HStack(spacing: 8) {
            if item.kind.editable {
                Button("保存") { save(item) }
                    .accessibilityIdentifier("save")
                    .disabled(!(dirty(item) || titleDraft != item.title || (item.kind == .richText && editingRich)))
                Button("另存") { model.saveAsNew(from: item, text: draft) }.accessibilityIdentifier("saveAsNew").help("保留原条目，把当前内容另存成一条新的").disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if item.kind == .image { Button("导出…") { model.exportImage(item) } }
            if item.kind == .file { Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting(item.filePaths.map { URL(fileURLWithPath: $0) }) } }
            if item.kind == .link { Button("打开") { if let u = URL(string: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) { NSWorkspace.shared.open(u) } } }
            Spacer()
            Button("复制") { model.copy(item) }.accessibilityIdentifier("copy")
            Button("粘贴") { model.paste(item, hideWindow: hideWindow) }.accessibilityIdentifier("paste")
                .help("粘贴到打开窗口前的 app：\(model.previousApp?.localizedName ?? "无")；需要「辅助功能」授权")
            Menu {
                Button(item.pinned ? "取消置顶" : "置顶") { model.togglePin(item) }
                Menu("加入收藏夹") {
                    ForEach(model.collections) { c in
                        Button(model.detailCollections.contains(c.id) ? "✓ \(c.name)" : c.name) {
                            if model.detailCollections.contains(c.id) { model.remove(item.id, from: c.id) } else { model.add([item.id], to: c.id) }
                        }
                    }
                    if model.collections.isEmpty { Text("还没有收藏夹，去左栏新建") }
                }
                Divider()
                Button("删除", role: .destructive) { AppDelegate.shared.confirmDelete([item.id]) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .controlSize(.regular)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func save(_ item: ClipItem) {
        if titleDraft != item.title { model.setTitle(item, titleDraft) }
        if dirty(item) || (item.kind == .richText && editingRich) { model.saveText(item, text: draft) }
        editingRich = false
    }
}
