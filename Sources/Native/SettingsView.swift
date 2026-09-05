import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("记录") {
                Toggle("暂停记录", isOn: $settings.paused)
                Toggle("纯文本模式（不保存富文本格式）", isOn: $settings.plainTextOnly)
                Toggle("抓取链接的页面标题（本 app 唯一的网络访问）", isOn: $settings.fetchLinkTitles)
                Stepper("最多保留 \(settings.maxItems) 条", value: $settings.maxItems, in: 100...100000, step: 100)
                Picker("保留时长", selection: $settings.retentionDays) {
                    Text("不限").tag(0); Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90); Text("365 天").tag(365)
                }
                Text("置顶的和收藏夹里的永不淘汰。").font(.caption).foregroundStyle(.secondary)
            }
            Section("忽略这些 app 的复制") {
                ForEach(settings.ignoredBundles, id: \.self) { b in
                    HStack {
                        Image(nsImage: model.appIcon(bundle: b)).resizable().frame(width: 16, height: 16)
                        Text(appName(b))
                        Text(b).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { settings.ignoredBundles.removeAll { $0 == b } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                    }
                }
                HStack {
                    Menu("从来源里选") {
                        ForEach(model.appCounts) { a in
                            Button(a.name) { if !settings.ignoredBundles.contains(a.bundle) { settings.ignoredBundles.append(a.bundle) } }
                        }
                    }.fixedSize()
                    Button("选择 app…") { pickApp() }
                }
                Text("密码管理器标记为敏感的内容无论如何都不会记录。").font(.caption).foregroundStyle(.secondary)
            }
            Section("从 Deck 导入") {
                if DeckImporter.available() {
                    HStack {
                        Button(model.importing ? "导入中…" : "导入 Deck 历史") { model.importDeck() }.disabled(model.importing)
                        if let at = model.deckImportedAt { Text("上次导入 \(at.prefix(16))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let r = model.importReport { Text(r).font(.caption) }
                    Text("只读 Deck 的库，不改不删；重复内容自动合并，可以重复导。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("没找到 Deck 的数据目录。").foregroundStyle(.secondary)
                }
            }
            Section("其他") {
                Toggle("开机自启", isOn: $settings.launchAtLogin)
                HStack {
                    Text("自动粘贴（辅助功能）")
                    Spacer()
                    if Paster.accessibilityTrusted { Label("已授权", systemImage: "checkmark.circle").foregroundStyle(.green) }
                    else { Button("去授权…") { Paster.promptAccessibility() } }
                }
                Button("打开数据目录") { NSWorkspace.shared.open(model.store.home) }
                Button("清空历史（保留置顶与收藏夹）…", role: .destructive) { AppDelegate.shared.confirmClear() }
                Text("快捷键：暂未设置。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .onChange(of: settings.paused) { _, _ in model.applySettings() }
        .onChange(of: settings.ignoredBundles) { _, _ in model.applySettings() }
        .onChange(of: settings.plainTextOnly) { _, _ in model.applySettings() }
        .onChange(of: settings.maxItems) { _, _ in model.applySettings() }
        .onChange(of: settings.retentionDays) { _, _ in model.applySettings() }
    }

    private func appName(_ bundle: String) -> String {
        if let a = model.appCounts.first(where: { $0.bundle == bundle }) { return a.name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return url.deletingPathExtension().lastPathComponent }
        return bundle
    }

    private func pickApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.applicationBundle]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        if p.runModal() == .OK, let u = p.url, let b = Bundle(url: u)?.bundleIdentifier, !settings.ignoredBundles.contains(b) {
            settings.ignoredBundles.append(b)
        }
    }
}
