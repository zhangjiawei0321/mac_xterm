import AppKit
import SwiftTerm

/// SSH 会话：PTY + 系统 /usr/bin/ssh，复用 SwiftTerm 的 LocalProcessTerminalView。
/// - 保存了密码 → SSH_ASKPASS 自动登录；
/// - 密码留空 → 终端内交互输入，登录稳定后询问是否保存；
/// - 用户名缺失 → 先弹窗让用户手动输入，不再默认用 Mac 用户名。
/// - 自动登录失败 → 弹窗重输密码。
@MainActor
final class SSHViewController: TermSessionController, LocalProcessTerminalViewDelegate {
    let session: SessionConfig
    var terminal: LocalProcessTerminalView!
    private var started = false
    /// 本次是否启用了密码自动登录
    private(set) var usedAutoLogin = false
    private var didRequestUsername = false
    private var didOfferSavePassword = false

    // 上层钩子
    var onNeedUsername: ((SSHViewController) -> Void)?
    var onOfferSavePassword: ((SSHViewController) -> Void)?
    var onAuthFailed: ((SSHViewController) -> Void)?

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
        applyAppearance()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startSession()
        focusTerminal()
    }

    func startSession() {
        guard !started else { return }
        started = true
        sessionStart = Date()

        // 未填用户名：不默认用 Mac 用户名，先弹窗让用户手动输入（解决后重连）
        if session.username.isEmpty, !didRequestUsername {
            didRequestUsername = true
            onNeedUsername?(self)
            return
        }

        // 保存了密码就用 SSH_ASKPASS 自动登录（同时标记 usedAutoLogin）
        let autoFill = autofillEnvironment

        var args: [String] = []
        args.append("-tt")                                   // 强制伪终端
        args.append(contentsOf: ["-p", String(session.port)])
        args.append(contentsOf: ["-o", "StrictHostKeyChecking=accept-new"])
        args.append(contentsOf: ["-o", "ConnectTimeout=15"])
        args.append(contentsOf: ["-o", "ServerAliveInterval=30"])
        if session.useKey && !session.keyPath.isEmpty {
            args.append(contentsOf: ["-i", session.keyPath])
        }
        // 自动登录时只允许 1 次密码尝试：错了一次就尽快失败，便于弹出重输密码
        if autoFill != nil {
            args.append(contentsOf: ["-o", "NumberOfPasswordPrompts=1"])
        }
        let userHost = "\(session.username)@\(session.host)"
        args.append(userHost)

        terminal.startProcess(executable: "/usr/bin/ssh",
                              args: args,
                              environment: autoFill)
        onStateChange?(true)

        // 密码留空（终端内手动输入）时：若持续运行说明登录成功，询问是否保存以便下次自动登录
        if session.password.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, !self.didOfferSavePassword, self.isOpen else { return }
                // 6 秒后仍存活 = 大概率已登录成功
                self.didOfferSavePassword = true
                self.onOfferSavePassword?(self)
            }
        }
    }

    /// 密码自动登录环境：通过 SSH_ASKPASS 让系统 ssh 直接读取保存的密码。
    /// 空密码时不注入环境（保持交互输入），避免行为改变。
    private var autofillEnvironment: [String]? {
        guard !session.password.isEmpty else { return nil }
        usedAutoLogin = true
        let script = AskpassHelper.ensureScript()
        guard !script.isEmpty else { return nil }
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("SSH_ASKPASS=\(script)")
        env.append("SSH_ASKPASS_REQUIRE=force")
        env.append("ML_ASKPW=\(session.password)")
        return env
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
        // 自动登录 + 很快失败（通常=密码错误/认证失败/不可达）→ 通知上层让用户重输密码
        if usedAutoLogin, exitCode != 0,
           Date().timeIntervalSince(sessionStart) < 10 {
            onAuthFailed?(self)
        }
    }

    override func closeSession() {
        guard isOpen else { return }
        terminal?.terminate()
        super.closeSession()
    }

    // MARK: - 会话菜单动作

    override func sendInput(_ text: String) {
        guard !text.isEmpty, let p = terminal?.process else { return }
        p.send(data: Array(text.utf8)[...])
    }

    override func clearLog() {
        guard let t = terminal else { return }
        t.getTerminal().clearScrollback()
        t.feed(text: "\u{1b}[2J\u{1b}[H")
    }

    override func exportLogData(timestamped: Bool) -> Data? {
        guard let t = terminal else { return nil }
        let data = t.getTerminal().getBufferAsData(kind: .active)
        return timestamped ? LogExport.timestamped(data, start: sessionStart) : data
    }

    override var logDefaultName: String {
        session.defaultTabTitle.replacingOccurrences(of: "/", with: "_") + ".log"
    }

    override func copySelection() {
        terminal?.copy(self)
    }

    override func copyAll() {
        guard let t = terminal else { return }
        copyBufferToPasteboard(t.getTerminal().getBufferAsData(kind: .active))
    }

    override var hasSelection: Bool {
        guard let t = terminal else { return false }
        return !t.selection.getSelectedText().isEmpty
    }

    override func applyAppearance() {
        guard let t = terminal else { return }
        TerminalAppearance.apply(to: t)
    }
}
