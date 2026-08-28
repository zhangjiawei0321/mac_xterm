import AppKit
import SwiftTerm

/// 本地终端会话：自建 TerminalView + LocalProcess，输出流过装饰器（IP 着色）。
@MainActor
final class LocalShellViewController: PTYSessionController {

    override func viewDidAppear() {
        super.viewDidAppear()
        startSession()
        focusTerminal()
    }

    func startSession() {
        guard !didAttemptStart else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        start(executable: shell, args: [], environment: nil)
    }

    override var logDefaultName: String { "本地终端.log" }
}
