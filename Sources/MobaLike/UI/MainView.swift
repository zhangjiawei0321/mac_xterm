import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            RailView()
            if model.sidebarVisible {
                Divider()
                SidebarView()
                    .frame(minWidth: 140, idealWidth: 158, maxWidth: 300)
            }
            Divider()
            TerminalAreaView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showNewSession) {
            NewSessionSheet()
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
