import SwiftUI

/// 最左侧的竖向功能条（类似 MobaXterm 左侧按钮列）
struct RailView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 4) {
            RailButton(icon: "sidebar.left",
                       title: "会话",
                       isOn: model.sidebarVisible) {
                withAnimation(.easeOut(duration: 0.15)) {
                    model.sidebarVisible.toggle()
                }
            }

            Divider().padding(.vertical, 6)

            RailButton(icon: "network", title: "SSH") {
                model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
            }
            RailButton(icon: "terminal", title: "Telnet") {
                model.showNewSessionSheet(kind: .telnet, inFolder: model.folderID(containing: model.selectedNodeID))
            }
            RailButton(icon: "dot.radiowaves.left.and.right", title: "串口") {
                model.showNewSessionSheet(kind: .serial, inFolder: model.folderID(containing: model.selectedNodeID))
            }
            RailButton(icon: "terminal", title: "本地") {
                model.openLocalTerminal()
            }

            Spacer()

            Text("NblityTerm")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .frame(width: 58)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RailButton: View {
    let icon: String
    let title: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 9))
            }
            .frame(width: 48, height: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isOn ? Color.accentColor.opacity(0.18) : Color.clear)
        .cornerRadius(6)
        .foregroundColor(isOn ? .accentColor : .primary)
        .help(title)
    }
}
