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

            if let tab = model.selectedTab {
                TermHostController(controller: model.controller(for: tab))
                    .id("\(tab.id.uuidString)-\(tab.revision)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contextMenu { terminalContextMenu() }
            } else {
                EmptyStateView()
            }
        }
    }

    /// 终端区域右键菜单（输入/显示框任意位置）
    @ViewBuilder
    private func terminalContextMenu() -> some View {
        let hasSel = model.selectedTab?.controller?.hasSelection ?? false
        Button("拷贝选中文本") { model.copySelectedTerminalSelection() }
            .disabled(!hasSel)
        Button("复制全部") { model.copySelectedTerminalAll() }
        Divider()
        Button("清除日志") { model.clearLog() }
        Button("保存日志…") { model.saveLog() }
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
