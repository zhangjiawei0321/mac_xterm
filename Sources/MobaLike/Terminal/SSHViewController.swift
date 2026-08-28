import AppKit
import SwiftTerm

/// SSH 会话：自建 TerminalView + LocalProcess（PTY），输出流经过装饰器（IP 着色等）。
/// - 保存了密码 → SSH_ASKPASS 自动登录；
/// - 密码留空 → 终端内交互输入，登录稳定后询问是否保存；
/// - 用户名缺失 → 先弹窗手动输入，不默认用 Mac 用户名；
/// - 自动登录失败 → 弹窗重输密码。
@MainActor
final class SSHViewController: PTYSessionController {
    let session: SessionConfig
    private var didRequestUsername = false
    private var didOfferSavePassword = false
    /// 本次是否启用了密码自动登录
    private(set) var usedAutoLogin = false

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

    override func viewDidAppear() {
        super.viewDidAppear()
        startSession()
        focusTerminal()
    }

    func startSession() {
        guard !didAttemptStart else { return }

        // 未填用户名：不默认用 Mac 用户名，先弹窗让用户手动输入
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
        args.append("\(session.username)@\(session.host)")

        start(executable: "/usr/bin/ssh", args: args, environment: autoFill)

        // 密码留空（终端内手动输入）时：持续运行说明登录成功，询问是否保存
        if session.password.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self, !self.didOfferSavePassword, self.isOpen else { return }
                self.didOfferSavePassword = true
                self.onOfferSavePassword?(self)
            }
        }
    }

    /// 密码自动登录环境：通过 SSH_ASKPASS 让系统 ssh 直接读取保存的密码。
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

    override func handleProcessTerminated(exitCode: Int32?) {
        super.handleProcessTerminated(exitCode: exitCode)
        // 自动登录 + 很快失败（密码错/认证失败/不可达）→ 弹窗重输密码
        if usedAutoLogin, exitCode != 0,
           Date().timeIntervalSince(sessionStart) < 10 {
            onAuthFailed?(self)
        }
    }

    override var logDefaultName: String {
        session.defaultTabTitle.replacingOccurrences(of: "/", with: "_") + ".log"
    }
}
