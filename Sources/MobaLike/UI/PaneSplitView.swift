import SwiftUI
import AppKit

/// 分屏平铺：2 格（左右）或 4 格（2×2）。
/// - 每格有「窗口标题栏」，把会话标题拖到哪格就显示哪格；
/// - 点击格切换输入；拖动分隔条调大小；4 格可拖中心点自由调整。
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
                    .overlay(alignment: .center) {
                        // 中心把手：自由拖动同时调行高与列宽
                        PaneCenterGrip(totalW: geo.size.width, totalH: geo.size.height)
                    }
                case .single:
                    EmptyView()
                }
            }
        }
    }
}

/// 单个分屏格：窗口标题栏 + 终端（或空位）。
/// 标题栏/整格可接收从顶栏拖来的会话标题；标题本身也可拖去别的格（对调）。
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
        VStack(spacing: 0) {
            header
            Divider()
            contentArea
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { model.setActivePane(index) }
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        }
        .overlay(
            Rectangle()
                .stroke(isActive ? Color.accentColor : Color(nsColor: .separatorColor),
                        lineWidth: isActive ? 2 : 0.5)
        )
    }

    // MARK: - 窗口标题栏

    private var header: some View {
        HStack(spacing: 5) {
            if let tab {
                if let n = model.tabNumber(of: tab.id) {
                    Text("\(n)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(isActive ? .white : .secondary)
                        .frame(minWidth: 14, minHeight: 14)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(isActive ? Color.accentColor : Color.secondary.opacity(0.18)))
                        .help("窗口序号")
                }
                Image(systemName: tab.kind.iconName)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                Text(tab.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("拖到其它格可对调；把顶栏会话拖到这里显示")
                if tab.logRecording {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .help("正在记录日志")
                }
            } else {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text("空窗口")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            if isActive {
                // 激活格提醒：当前正在输入到哪个连接
                Label("输入中", systemImage: "keyboard")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .help("当前输入目标：\(tab?.title ?? "")")
            }
            if let tab {
                Button {
                    model.closeTab(id: tab.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭此会话")
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(isActive ? Color.accentColor.opacity(0.12)
                             : Color(nsColor: .underPageBackgroundColor))
        .draggable(tabID?.uuidString ?? "pane-empty-\(index)")
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items)
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        if let tab {
            TermHostController(controller: model.controller(for: tab))
                .id("\(tab.id.uuidString)-p\(index)-\(tab.revision)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Button {
                model.pendingPaneIndex = index
                model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "plus.square.on.square")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text("新建会话到此格")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 放置解析

    private func handleDrop(_ items: [String]) -> Bool {
        guard let s = items.first else { return false }
        if let tabID = UUID(uuidString: s) {
            model.assignPane(index, tabID: tabID)
            return true
        }
        return false
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

/// 四格中心把手：自由拖动，同时调整行高与列宽
struct PaneCenterGrip: View {
    @EnvironmentObject var model: AppModel
    let totalW: CGFloat
    let totalH: CGFloat

    @State private var dragging = false
    @State private var startRow: CGFloat = 0.5
    @State private var startCol: CGFloat = 0.5

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .frame(width: 18, height: 18)
            .background(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1))
            .clipShape(Circle())
            .contentShape(Circle())
            .onHover { h in
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging {
                            dragging = true
                            startRow = model.paneFourRowSplit
                            startCol = model.paneFourColSplit
                        }
                        model.paneFourColSplit = min(max(startCol + v.translation.width / max(totalW, 1), 0.2), 0.8)
                        model.paneFourRowSplit = min(max(startRow + v.translation.height / max(totalH, 1), 0.2), 0.8)
                    }
                    .onEnded { _ in dragging = false }
            )
            .help("拖动中心点自由调整四格位置")
    }
}
