import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
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
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
            MacroBarView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showNewSession) {
            NewSessionSheet()
                .environmentObject(model)
        }
        .sheet(item: $model.prompt) { prompt in
            SessionPromptSheet(prompt: prompt)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.macroManagerPresented) {
            MacroManagerSheet()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.macroEditorPresented) {
            MacroEditorSheet()
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
