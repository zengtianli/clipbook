import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: AppModel
    @State private var newCollection = false
    @State private var editing: Collection?

    var body: some View {
        List(selection: Binding(get: { Optional(model.sidebar) }, set: { if let v = $0 { model.sidebar = v } })) {
            Section {
                row("全部", "tray.full", model.totalAll, .all)
                row("置顶", "pin", model.kindCounts.values.reduce(0, +) > 0 ? (try? model.store.count(.init(pinnedOnly: true))) ?? 0 : 0, .pinned)
            }
            Section("类型") {
                ForEach(ClipItem.Kind.allCases) { k in
                    if let n = model.kindCounts[k], n > 0 { row(k.label, k.symbol, n, .kind(k)) }
                }
            }
            Section("来源") {
                ForEach(model.appCounts.prefix(12)) { a in
                    HStack(spacing: 6) {
                        Image(nsImage: model.appIcon(bundle: a.bundle)).resizable().frame(width: 16, height: 16)
                        Text(a.name).lineLimit(1)
                        Spacer()
                        Text("\(a.count)").foregroundStyle(.secondary).font(.caption).monospacedDigit()
                    }
                    .tag(SidebarSelection.app(a.bundle))
                }
            }
            Section {
                ForEach(model.collections) { c in
                    HStack(spacing: 6) {
                        Image(systemName: c.icon).foregroundStyle(Color(hex: c.color)).frame(width: 16)
                        Text(c.name).lineLimit(1)
                        Spacer()
                        Text("\(model.collectionCounts[c.id] ?? 0)").foregroundStyle(.secondary).font(.caption).monospacedDigit()
                    }
                    .tag(SidebarSelection.collection(c.id))
                    .contextMenu {
                        Button("编辑…") { editing = c }
                        Button("上移") { model.moveCollection(c.id, by: -1) }
                        Button("下移") { model.moveCollection(c.id, by: 1) }
                        Divider()
                        Button("删除收藏夹", role: .destructive) { model.deleteCollection(c.id) }
                    }
                }
                Button { newCollection = true } label: { Label("新建收藏夹", systemImage: "plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier("newCollection")
            } header: { Text("收藏夹") }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $newCollection) { CollectionEditor(model: model, collection: nil) }
        .sheet(item: $editing) { c in CollectionEditor(model: model, collection: c) }
    }

    private func row(_ label: String, _ symbol: String, _ count: Int, _ sel: SidebarSelection) -> some View {
        HStack {
            Label(label, systemImage: symbol)
            Spacer()
            Text("\(count)").foregroundStyle(.secondary).font(.caption).monospacedDigit()
        }
        .tag(sel)
    }
}

/// 新建 / 编辑收藏夹：名字、图标、颜色
struct CollectionEditor: View {
    @ObservedObject var model: AppModel
    let collection: Collection?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var icon = "folder"
    @State private var color = "#2563eb"

    static let icons = ["folder", "star", "tag", "bookmark", "heart", "flag", "bolt", "briefcase", "book", "terminal", "doc.text", "link", "photo", "person", "cart", "globe"]
    static let colors = ["#2563eb", "#dc2626", "#ea580c", "#ca8a04", "#16a34a", "#0d9488", "#7c3aed", "#db2777", "#6b7280"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(collection == nil ? "新建收藏夹" : "编辑收藏夹").font(.headline)
            TextField("名字", text: $name).accessibilityIdentifier("collectionName")
            // 16 个图标一行放不下 440 宽；HStack 会撑破 frame 再被居中裁掉（2026-09-05 实测左边被切）—— 用自适应网格换行
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 6)], spacing: 6) {
                ForEach(Self.icons, id: \.self) { i in
                    Image(systemName: i).frame(width: 30, height: 26)
                        .background(i == icon ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .onTapGesture { icon = i }
                }
            }
            HStack(spacing: 8) {
                ForEach(Self.colors, id: \.self) { c in
                    Circle().fill(Color(hex: c)).frame(width: 18, height: 18)
                        .overlay(Circle().stroke(Color.primary, lineWidth: c == color ? 2 : 0))
                        .onTapGesture { color = c }
                }
            }
            HStack {
                Spacer()
                Button(collection == nil ? "新建" : "保存") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    if var c = collection { c.name = n; c.icon = icon; c.color = color; model.updateCollection(c) }
                    else { _ = model.createCollection(name: n, color: color, icon: icon) }
                    dismiss()
                }
                .accessibilityIdentifier("createCollection")
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(18).frame(width: 460)
        .onAppear { if let c = collection { name = c.name; icon = c.icon; color = c.color } }
    }
}
