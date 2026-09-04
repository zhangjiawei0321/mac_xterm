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
        // 用「登录 shell」启动（同 Terminal.app）：应用经 open 启动时继承的精简 PATH 不含
        // /usr/local/bin、/opt/homebrew/bin 等，只有登录 shell 才会读取 /etc/paths 与
        // ~/.zprofile 从而把这些目录加进 PATH（否则 npx/node 等会 “command not found”）。
        start(executable: shell, args: ["-l"], environment: nil, currentDirectory: NSHomeDirectory())
    }

    override var logDefaultName: String { "本地终端.log" }
}
