import SwiftUI

/// 顶部标签页条
struct TabBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { tab in
                TabChipView(tab: tab,
                            isSelected: tab.id == model.selectedTabID,
                            onSelect: { model.selectedTabID = tab.id },
                            onClose: { model.closeTab(id: tab.id) })
            }

            Button {
                model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("新建会话")

            Spacer()
        }
        .padding(.leading, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

struct TabChipView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var tab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.kind.iconName)
                .font(.system(size: 11))
                .foregroundColor(tab.status == .disconnected ? .secondary : .accentColor)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("关闭标签页")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(isSelected ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .overlay(
            Rectangle()
                .fill(isSelected ? Color.accentColor : Color.clear)
                .frame(height: 2),
            alignment: .top
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
            model.focusSelectedTerminal()
        }
        .contextMenu {
            Button("粘贴") { model.pasteInto(tab) }
            Divider()
            Button("清除日志") { model.clearLog(tab) }
            Button("保存日志…") { model.saveLog(tab) }
            Divider()
            Button("断开连接") { tab.close(); model.focusSelectedTerminal() }
            Button("关闭标签页") { onClose() }
        }
    }
}
