import SwiftUI
import AppKit

@main
struct MobaLikeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(model)
                .frame(minWidth: 940, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建会话…") {
                    NotificationCenter.default.post(name: .openNewSession, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("新建本地终端") {
                    NotificationCenter.default.post(name: .openLocalTerminal, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) {}
        }

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 非 .app 包直接运行二进制时也保持正常窗口/焦点行为
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        SessionRegistry.shared.terminateAll()
    }
}

extension Notification.Name {
    static let openNewSession = Notification.Name("MobaLike.openNewSession")
    static let openLocalTerminal = Notification.Name("MobaLike.openLocalTerminal")
}
