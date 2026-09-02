import AppKit
import SwiftTerm

/// 基于「自建 TerminalView + LocalProcess」的会话控制器：
/// 自己接管输出字节流（可做 IP 着色、显示时间戳），SSH / 本地终端共用。
@MainActor
class PTYSessionController: TermSessionController, TerminalViewDelegate, LocalProcessDelegate {
    var terminalView: TerminalView!
    /// 兼容旧代码名：terminal 即 TerminalView
    var terminal: TerminalView! { terminalView }
    private(set) var process: LocalProcess!
    /// 是否已尝试启动
    private(set) var didAttemptStart = false
    /// 给装饰器用的跨块尾部
    private var decoratorPending: [UInt8] = []
    private var timestampState = TerminalTextDecorator.TimestampPrefixState()

    override func loadView() {
        let tv = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.terminalDelegate = self
        self.view = tv
        self.terminalView = tv
        SessionRegistry.shared.register(self)
        applyAppearance()
    }

    /// 启动子进程（PTY 由 SwiftTerm LocalProcess 建立）
    func start(executable: String, args: [String], environment: [String]?, currentDirectory: String? = nil) {
        guard !didAttemptStart else { return }
        didAttemptStart = true
        sessionStart = Date()
        process = LocalProcess(delegate: self, dispatchQueue: .main)
        process.startProcess(executable: executable, args: args,
                             environment: Self.terminalEnvironment(environment),
                             currentDirectory: currentDirectory)
        onStateChange?(true)
    }

    /// 会话环境：确保 TERM（避免 git 等把终端当 dumb/非终端而抑制进度），并让 git 立即显示进度。
    /// 保留调用方环境无法覆盖我们注入的关键项。
    static func terminalEnvironment(_ given: [String]?) -> [String] {
        var dict: [String: String] = [:]
        if let given {
            for kv in given {
                let p = kv.split(separator: "=", maxSplits: 1)
                if p.count == 2 { dict[String(p[0])] = String(p[1]) }
            }
        } else {
            // 本地 shell：基于当前进程环境
            for (k, v) in ProcessInfo.processInfo.environment { dict[k] = v }
        }
        if dict["TERM"] == nil || dict["TERM"]?.isEmpty == true || dict["TERM"] == "dumb" {
            dict["TERM"] = "xterm-256color"
        }
        if dict["LANG"] == nil { dict["LANG"] = "C.UTF-8" }
        dict["GIT_PROGRESS_DELAY"] = "0"   // 让 git 进度条立即显示（tty 时为 0）
        return dict.map { "\($0.key)=\($0.value)" }
    }

    // MARK: - LocalProcessDelegate（输出流，先装饰再送入终端）

    func dataReceived(slice: ArraySlice<UInt8>) {
        var data = TerminalTextDecorator.decorate(Data(slice), pending: &decoratorPending,
                                                  colorizeIP: true, tailKeep: 32)
        if UserDefaults.standard.bool(forKey: "displayTimestamp") {
            data = TerminalTextDecorator.prefixLines(data, state: &self.timestampState)
        }
        if !data.isEmpty {
            terminalView.feed(byteArray: Array(data)[...])
            afterFeed(data)
        }
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        var tail = TerminalTextDecorator.flush(pending: &decoratorPending, colorizeIP: true)
        if !tail.isEmpty {
            terminalView.feed(byteArray: Array(tail)[...])
        }
        handleProcessTerminated(exitCode: exitCode)
    }

    func getWindowSize() -> winsize {
        let t = terminalView.getTerminal()
        return winsize(ws_row: UInt16(t.rows), ws_col: UInt16(t.cols), ws_xpixel: 0, ws_ypixel: 0)
    }

    /// 子类可覆写（提示“按 R 重连”、认证失败弹窗等）
    func handleProcessTerminated(exitCode: Int32?) {
        markTerminated()
        if let t = terminalView {
            let hint = exitCode == 0
                ? "\r\n（会话已结束，按 R 重新开始）\r\n"
                : "\r\n（连接中断，按 R 重新连接）\r\n"
            t.feed(text: hint)
        }
    }

    // MARK: - TerminalViewDelegate（输入 → 进程，尺寸 → PTY）

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process?.send(data: data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        // 防抖：拖拽分屏时频繁触发，合并为一次避免远端 SIGWINCH 重绘刷屏
        debouncedPtyResize { [weak self] in
            guard let self, let p = self.process, p.childfd >= 0 else { return }
            var size = self.getWindowSize()
            _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: p.childfd, windowSize: &size)
        }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        NSSound.beep()
    }

    func clipboardCopy(source: TerminalView, content: Data) {}

    func clipboardRead(source: TerminalView) -> Data? { nil }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    // MARK: - 会话菜单动作（TerminalView 版，与串口一致）

    override func sendInput(_ text: String) {
        guard !text.isEmpty else { return }
        process?.send(data: Array(Array(text.utf8))[...])
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
        _ = query; _ = hitIndex
        guard let t = terminal else { return }
        t.scrollTo(row: row)
        if let sel = t.selection as SelectionService? {
            sel.select(row: row)
        }
    }

    override func applyAppearance() {
        guard let t = terminal else { return }
        TerminalAppearance.apply(to: t)
    }

    override func closeSession() {
        guard isOpen else { return }
        process?.terminate()
        super.closeSession()
    }
}
