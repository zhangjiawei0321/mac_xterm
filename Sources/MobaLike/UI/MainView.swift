import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var model: AppModel
    /// 主内容区在屏幕(global)坐标系的 frame，用于把信息卡定位到窗口内
    @State private var mainGlobalFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                RailView()
                if model.sidebarVisible {
                    Divider()
                    SidebarView()
                        .frame(width: model.sidebarWidth)
                    SidebarResizer()
                }
                Divider()
                TerminalAreaView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(
                // 上报主内容区的 global frame，用于坐标换算
                GeometryReader { g2 in
                    Color.clear.preference(key: MainGlobalFrameKey.self, value: g2.frame(in: .global))
                }
            )
            .overlay(alignment: .topLeading) {
                // 窗口内悬浮信息卡：不单独成窗，不抢焦点、不挡点击
                if let info = model.hoverInfo, !mainGlobalFrame.isEmpty {
                    HoverInfoCard(session: info.session)
                        .position(
                            x: (info.globalFrame.maxX - mainGlobalFrame.minX) + 12 + 125,
                            y: info.globalFrame.midY - mainGlobalFrame.minY
                        )
                        .allowsHitTesting(false)
                }
            }
            .onPreferenceChange(MainGlobalFrameKey.self) { mainGlobalFrame = $0 }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .sheet(isPresented: $model.showNewSession) {
            NewSessionSheet()
                .environmentObject(model)
        }
        .sheet(item: $model.prompt) { prompt in
            SessionPromptSheet(prompt: prompt)
                .environmentObject(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewSession)) { _ in
            model.showNewSessionSheet(kind: .ssh, inFolder: model.folderID(containing: model.selectedNodeID))
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLocalTerminal)) { _ in
            model.openLocalTerminal()
        }
        .onAppear {
            // 裸二进制直接运行时，保证窗口能获得焦点和正常菜单栏
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct MainGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// 侧栏与终端区之间的拖拽把手，可左右调整侧栏宽度
struct SidebarResizer: View {
    @EnvironmentObject var model: AppModel
    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if startWidth == 0 { startWidth = model.sidebarWidth }
                        model.sidebarWidth = min(max(startWidth + value.translation.width, 90), 420)
                    }
                    .onEnded { _ in startWidth = 0 }
            )
    }
}
