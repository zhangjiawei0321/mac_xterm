import SwiftUI

/// 顶部标签页条
struct TabBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs) { tab in
                TabChipView(tab: tab,
                            isSelected: tab.id == model.selectedTabID,
                            onSelect: { model.selectTab(tab.id) },
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

            // 分屏平铺：单屏 / 2 格 / 4 格
            Picker("", selection: Binding(
                get: { model.paneLayout },
                set: { model.paneLayout = $0 }
            )) {
                ForEach([PaneLayout.single, .two, .four], id: \.self) { p in
                    Text(p.shortLabel).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 108)
            .help("分屏：同时显示 2 或 4 个终端，点击格切换输入，拖动分隔条调整大小")

            Button {
                model.toggleSearchPanel()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .padding(6)
            .help("搜索终端输出 (⌘F)")
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
        .draggable(tab.id.uuidString)   // 分屏：拖会话标题到某窗口格显示
        .onTapGesture {
            onSelect()
            model.focusSelectedTerminal()
        }
        .contextMenu {
            Button("复制全部") { model.copyAll(of: tab) }
            Divider()
            Button("清除日志") { model.clearLog(tab) }
            Button("保存日志…") { model.saveLog(tab) }
        }
    }
}
