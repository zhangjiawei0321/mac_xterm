import AppKit
import SwiftTerm

/// 本地终端会话（相当于 MobaXterm 里打开一个本地 Shell）
@MainActor
final class LocalShellViewController: TermSessionController, LocalProcessTerminalViewDelegate {
    var terminal: LocalProcessTerminalView!
    private var started = false

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
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
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminal.startProcess(executable: shell)
        onStateChange?(true)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        markTerminated()
    }

    override func closeSession() {
        guard isOpen else { return }
        terminal?.terminate()
        super.closeSession()
    }
}
