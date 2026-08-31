import SwiftUI

/// 主区域：标签条 + 选中标签页的终端内容（或空状态）
struct TerminalAreaView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if !model.tabs.isEmpty {
                TabBarView()
                Divider()
            }

            if model.paneLayout == .single {
                if let tab = model.selectedTab {
                    TermHostController(controller: model.controller(for: tab))
                        .id("single-\(model.hostEpoch)-\(tab.id.uuidString)-\(tab.revision)")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // 右键菜单由终端的原生 rightMouseDown 即时构建（状态最新），无需 SwiftUI contextMenu
                } else {
                    EmptyStateView()
                }
            } else {
                // 分屏平铺：2 格 / 4 格
                PaneSplitView()
                    .environmentObject(model)
            }

            if model.searchPanelVisible {
                Divider()
                SearchResultsPanel()
                    .environmentObject(model)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSearch)) { _ in
            if !model.searchPanelVisible {
                model.searchPanelVisible = true
                model.recentlySearched = false
            }
            // 通知搜索面板聚焦输入框
            NotificationCenter.default.post(name: .focusSearchField, object: nil)
        }
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 46))
                .foregroundColor(.secondary)
            Text("开始你的会话")
                .font(.title3)
                .fontWeight(.medium)
            Text("双击左侧会话，或点击上方 ＋ 新建 SSH / 串口会话")
                .font(.callout)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button {
                    model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
                } label: {
                    Label("SSH 会话", systemImage: "network")
                }
                Button {
                    model.showNewSessionSheet(kind: .serial, inFolder: model.folderID(containing: model.selectedNodeID))
                } label: {
                    Label("串口会话", systemImage: "dot.radiowaves.left.and.right")
                }
                Button {
                    model.showNewSessionSheet(kind: .telnet, inFolder: model.folderID(containing: model.selectedNodeID))
                } label: {
                    Label("Telnet 会话", systemImage: "terminal")
                }
                Button {
                    model.openLocalTerminal()
                } label: {
                    Label("本地终端", systemImage: "terminal")
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}
