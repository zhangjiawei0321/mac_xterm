import AppKit
import SwiftTerm

/// SSH 会话：PTY + 系统 /usr/bin/ssh，复用 SwiftTerm 的 LocalProcessTerminalView。
/// 密码、主机指纹确认、交互命令都在终端里直接进行（和 MobaXterm 交互方式一致）。
@MainActor
final class SSHViewController: TermSessionController, LocalProcessTerminalViewDelegate {
    let session: SessionConfig
    var terminal: LocalProcessTerminalView!
    private var started = false

    init(session: SessionConfig) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let tv = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.processDelegate = self
        self.view = tv
        self.terminal = tv
        SessionRegistry.shared.register(self)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startSession()
    }

    func startSession() {
        guard !started else { return }
        started = true

        var args: [String] = []
        args.append("-tt")                                   // 强制伪终端
        args.append(contentsOf: ["-p", String(session.port)])
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new"])
        args.append(contentsOf: ["-o", "ConnectTimeout=15"])
        args.append(contentsOf: ["-o", "ServerAliveInterval=30"])
        if session.useKey && !session.keyPath.isEmpty {
            args.append(contentsOf: ["-i", session.keyPath])
        }
        let userHost = session.username.isEmpty
            ? session.host
            : "\(session.username)@\(session.host)"
        args.append(userHost)

        terminal.startProcess(executable: "/usr/bin/ssh", args: args)
        onStateChange?(true)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
        // 无需处理窗口尺寸
    }

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // 预留：可在标题中展示当前目录
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        markTerminated()
    }

    override func closeSession() {
        guard isOpen else { return }
        terminal?.terminate()
        super.closeSession()
    }
}
