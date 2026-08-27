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

    // MARK: - 会话菜单动作

    override func sendInput(_ text: String) {
        guard !text.isEmpty else { return }
        terminal.process.send(data: Array(text.utf8)[...])
    }

    override func clearLog() {
        let t = terminal.getTerminal()
        t.clearScrollback()
        terminal.feed(text: "\u{1b}[2J\u{1b}[H")
    }

    override func exportLogData(timestamped: Bool) -> Data? {
        let data = terminal.getTerminal().getBufferAsData(kind: .active)
        return timestamped ? LogExport.timestamped(data, start: sessionStart) : data
    }

    override var logDefaultName: String { "本地终端.log" }

    override func copySelection() {
        terminal.copy(self)
    }

    override func copyAll() {
        copyBufferToPasteboard(terminal.getTerminal().getBufferAsData(kind: .active))
    }

    override var hasSelection: Bool {
        !terminal.selection.getSelectedText().isEmpty
    }

    override func applyAppearance() {
        TerminalAppearance.apply(to: terminal)
    }
}
