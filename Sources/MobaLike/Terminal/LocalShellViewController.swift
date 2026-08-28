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
        if let t = terminal {
            t.feed(text: "\r\n（本地终端已退出，按 R 重新打开）\r\n")
        }
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
        guard let t = terminal else { return }
        t.getTerminal().clearScrollback()
        t.feed(text: "\u{1b}[2J\u{1b}[H")
    }

    override func exportLogData(timestamped: Bool) -> Data? {
        guard let t = terminal else { return nil }
        let data = t.getTerminal().getBufferAsData(kind: .active)
        return timestamped ? LogExport.timestamped(data, start: sessionStart) : data
    }

    override var logDefaultName: String { "本地终端.log" }

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

    override func searchLineHits(_ query: String) -> [TerminalSearchHit] {
        guard let t = terminal else { return [] }
        return TerminalSearch.hits(in: t, query: query)
    }

    override func jumpToSearchLine(_ query: String, hitIndex: Int, row: Int) {
        guard let t = terminal else { return }
        t.scrollTo(row: row)
        if !query.isEmpty {
            t.clearSearch()
            let steps = min(hitIndex + 1, 800)
            var k = 0
            while k < steps, t.findNext(query, scrollToResult: false) { k += 1 }
        }
        focusTerminal()
    }

    override func applyAppearance() {
        guard let t = terminal else { return }
        TerminalAppearance.apply(to: t)
    }
}
