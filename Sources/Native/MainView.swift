import SwiftUI

/// 三栏：左筛 / 中挑 / 右改
struct MainView: View {
    @ObservedObject var model: AppModel
    let hideWindow: () -> Void
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } content: {
            GridPane(model: model, hideWindow: hideWindow)
                .navigationSplitViewColumnWidth(min: 440, ideal: 620)
        } detail: {
            DetailPane(model: model, hideWindow: hideWindow)
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if settingsPaused { Label("已暂停记录", systemImage: "pause.circle").foregroundStyle(.orange) }
            }
            ToolbarItem(placement: .automatic) {
                if let n = model.notice { Text(n).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
            }
            ToolbarItem(placement: .automatic) {
                Button { AppDelegate.shared.showSettings() } label: { Image(systemName: "gearshape") }.help("设置")
            }
        }
        .onChange(of: model.notice) { _, n in
            guard n != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if model.notice == n { model.notice = nil } }
        }
    }

    private var settingsPaused: Bool { AppSettings.shared.paused }
}
