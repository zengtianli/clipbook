import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var shortcuts: ClipShortcuts
    @State private var accessibilityTrusted = Paster.accessibilityTrusted

    var body: some View {
        TabView {
            general.tabItem { Label("通用", systemImage: "gearshape") }
            ShortcutSettingsPane(center: shortcuts).tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .padding(10)
        .frame(minWidth: 560, minHeight: 420)
        .onAppear { refreshSystemStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshSystemStatus() }
    }

    private func refreshSystemStatus() {
        accessibilityTrusted = Paster.accessibilityTrusted
        settings.refreshLoginStatus()
    }

    private var general: some View {
        Form {
            Section("记录") {
                Toggle("暂停记录", isOn: $settings.paused).accessibilityIdentifier("pauseRecording")
                Toggle("纯文本模式（不保存富文本格式）", isOn: $settings.plainTextOnly)
                Toggle("自动获取链接标题", isOn: $settings.fetchLinkTitles)
                Text("开启后会访问所复制链接的网页。").font(.caption).foregroundStyle(.secondary)
                Stepper("最多保留 \(settings.maxItems) 条", value: $settings.maxItems, in: 100...100000, step: 100)
                Picker("保留时长", selection: $settings.retentionDays) {
                    Text("不限").tag(0); Text("7 天").tag(7); Text("30 天").tag(30); Text("90 天").tag(90); Text("365 天").tag(365)
                }
                Text("置顶与收藏夹内容不淘汰。保留规则会在下一次记录新内容时执行。").font(.caption).foregroundStyle(.secondary)
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
                        Button(model.importing ? "导入中…" : "导入 Deck 历史") { model.importDeck() }.disabled(model.importing).accessibilityIdentifier("importDeck")
                        if let at = model.deckImportedAt, let d = ISO8601DateFormatter().date(from: at) { Text("上次导入 \(Fmt.full(d))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if let r = model.importReport { Text(r).font(.caption) }
                    Text("只读 Deck 的库，不改不删；重复内容自动合并，可以重复导。").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("没找到 Deck 的数据目录。").foregroundStyle(.secondary)
                }
            }
            Section("复制声音") {
                Toggle("复制时播放声音（所有应用）", isOn: $settings.copySound).accessibilityIdentifier("copySound")
                HStack {
                    Picker("音效", selection: $settings.copySoundName) {
                        ForEach(CopyFeedback.soundNames, id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier("copySoundName")
                    Button("试听") { _ = CopyFeedback.playSystemSound() }.accessibilityIdentifier("previewCopySound")
                }
                HStack {
                    Text("音量")
                    Slider(value: $settings.copySoundVolume, in: 0...1).accessibilityIdentifier("copySoundVolume")
                    Text("\(Int(settings.copySoundVolume * 100))%").monospacedDigit().frame(width: 42)
                }
                Text("Clip 运行期间，在其他应用复制也会响；暂停记录不影响声音。一次复制只响一次。").font(.caption).foregroundStyle(.secondary)
            }
            Section("其他") {
                Toggle("开机自启", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
                Text(settings.launchStatus).font(.caption).foregroundStyle(.secondary)
                if let error = settings.launchError { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Text("自动粘贴（辅助功能）")
                    Spacer()
                    if accessibilityTrusted { Label("已授权", systemImage: "checkmark.circle").foregroundStyle(.green) }
                    else { Button("去授权…") { Paster.promptAccessibility() } }
                }
                Button("打开数据目录") { NSWorkspace.shared.open(model.store.home) }
                Button("清空历史（保留置顶与收藏夹）…", role: .destructive) { AppDelegate.shared.confirmClear() }
                Text("设置自动保存；关闭设置窗口后仍然生效。").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
