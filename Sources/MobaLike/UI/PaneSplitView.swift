import SwiftUI
import AppKit

/// 分屏平铺：2 格（左右）或 4 格（2×2）。
/// 点击某个格 = 输入切到该格；拖动分隔条自由调节大小。
struct PaneSplitView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        GeometryReader { geo in
            Group {
                switch model.paneLayout {
                case .two:
                    HStack(spacing: 0) {
                        PaneCell(index: 0)
                            .frame(width: max(60, geo.size.width * model.paneTwoSplit))
                        PaneVDivider(total: geo.size.width, value: $model.paneTwoSplit)
                        PaneCell(index: 1)
                    }
                case .four:
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            PaneCell(index: 0)
                                .frame(width: max(60, geo.size.width * model.paneFourColSplit))
                            PaneVDivider(total: geo.size.width, value: $model.paneFourColSplit)
                            PaneCell(index: 1)
                        }
                        .frame(height: max(60, geo.size.height * model.paneFourRowSplit))

                        PaneHDivider(total: geo.size.height, value: $model.paneFourRowSplit)

                        HStack(spacing: 0) {
                            PaneCell(index: 2)
                                .frame(width: max(60, geo.size.width * model.paneFourColSplit))
                            PaneVDivider(total: geo.size.width, value: $model.paneFourColSplit)
                            PaneCell(index: 3)
                        }
                    }
                case .single:
                    EmptyView()
                }
            }
        }
    }
}

/// 单个分屏格：显示一个标签页的终端，或空位（＋ 新建会话）
struct PaneCell: View {
    @EnvironmentObject var model: AppModel
    let index: Int

    private var tabID: UUID? {
        guard model.paneTabIDs.indices.contains(index) else { return nil }
        return model.paneTabIDs[index]
    }
    private var tab: TerminalTab? {
        guard let id = tabID else { return nil }
        return model.tabs.first { $0.id == id }
    }
    private var isActive: Bool { model.activePaneIndex == index }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let tab {
                TermHostController(controller: model.controller(for: tab))
                    .id("\(tab.id.uuidString)-p\(index)-\(tab.revision)")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyPane
            }
            titleChip
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { model.setActivePane(index) }
        .overlay(
            Rectangle()
                .stroke(isActive ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isActive ? 2 : 0.5)
        )
    }

    /// 左上角标签：类型图标 + 标题（激活态高亮）
    @ViewBuilder
    private var titleChip: some View {
        if let tab {
            HStack(spacing: 4) {
                Image(systemName: tab.kind.iconName)
                    .font(.system(size: 9))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isActive ? Color.accentColor : Color(nsColor: .underPageBackgroundColor))
            .foregroundColor(isActive ? .white : .secondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .padding(6)
            .help(isActive ? "当前输入窗口" : "点击切换输入到此窗口")
        }
    }

    /// 空分屏格：点击新建会话（填入此格）
    private var emptyPane: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.square.on.square")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text("新建会话到此格")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onTapGesture {
            model.pendingPaneIndex = index
            model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
        }
    }
}

/// 竖向分隔条：左右拖动调整列宽
struct PaneVDivider: View {
    let total: CGFloat
    @Binding var value: CGFloat
    @State private var dragging = false
    @State private var startValue: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { h in
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragging = true; startValue = value }
                        value = min(max(startValue + v.translation.width / max(total, 1), 0.2), 0.8)
                    }
                    .onEnded { _ in dragging = false }
            )
    }
}

/// 横向分隔条：上下拖动调整行高
struct PaneHDivider: View {
    let total: CGFloat
    @Binding var value: CGFloat
    @State private var dragging = false
    @State private var startValue: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 5)
            .contentShape(Rectangle())
            .onHover { h in
                if h { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragging = true; startValue = value }
                        value = min(max(startValue + v.translation.height / max(total, 1), 0.2), 0.8)
                    }
                    .onEnded { _ in dragging = false }
            )
    }
}
