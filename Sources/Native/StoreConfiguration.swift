#if APP_STORE
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// User-selected settings files use the shared envelope and validation, never a second schema.
@MainActor
enum StoreConfigurationTransfer {
    static func export(_ configuration: AppConfiguration, to url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try configuration.exportData().write(to: url, options: .atomic)
    }

    static func `import`(_ configuration: AppConfiguration, from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try configuration.importData(Data(contentsOf: url))
    }
}

struct StoreConfigurationPane: View {
    @State private var enabled = false
    @State private var status = ""
    private var configuration: AppConfiguration? { AppDelegate.shared?.configuration }

    var body: some View {
        Section("配置迁移与同步") {
            Toggle("使用 iCloud 记住配置", isOn: Binding(get: { enabled }, set: {
                configuration?.setEnabled($0); refresh()
            }))
            Text(status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("导出配置…") { exportSettings() }
                Button("导入配置…") { importSettings() }
            }
            Text("从下载版迁移：先在旧版导出配置，再在这里导入。剪贴板历史独立保存在商店版容器中，不随配置迁移。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AppConfigurationStatusChanged"))) { _ in refresh() }
    }

    private func refresh() {
        enabled = configuration?.enabled ?? false
        status = configuration?.status ?? "配置尚未初始化"
    }

    private func exportSettings() {
        guard let configuration else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Clip-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try StoreConfigurationTransfer.export(configuration, to: url); status = "配置已导出" }
        catch { status = "导出失败：\(error.localizedDescription)" }
    }

    private func importSettings() {
        guard let configuration else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try StoreConfigurationTransfer.import(configuration, from: url); status = "配置已导入，原配置已备份" }
        catch { status = "导入失败：\(error.localizedDescription)" }
    }
}
#endif
