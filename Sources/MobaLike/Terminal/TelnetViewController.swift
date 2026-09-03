import AppKit
import SwiftTerm

/// Telnet 会话：自建 TCP 客户端 + TerminalView，输出流过装饰器（IP 着色）。
/// 无用户名/密码流程（登录由远端交互式提示，直接在终端里输入）。
@MainActor
final class TelnetViewController: TermSessionController, TerminalViewDelegate {
    let session: SessionConfig
    var terminal: TerminalView!
    private var client: TelnetClient?
    /// 是否在终端显示时给每行加时间戳（设置项）
    private var displayTimestamp: Bool { UserDefaults.standard.bool(forKey: "displayTimestamp") }
    private var timestampState = TerminalTextDecorator.TimestampPrefixState()
    private var decoratorPending: [UInt8] = []

    init(session: SessionConfig) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let tv = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        tv.terminalDelegate = self
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
        guard client == nil else { return }
        sessionStart = Date()
        let c = TelnetClient()
        c.onConnected = { [weak self] in
            DispatchQueue.main.async {
                self?.onStateChange?(true)
                self?.terminal.feed(text: "已连接 \(self?.session.host ?? "") : \(self?.session.port ?? 0)\r\n")
            }
        }
        c.onData = { [weak self] data in
            // 网络队列回调不可直接喂终端/SwiftTerm（非线程安全），转主线程处理
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var out = TerminalTextDecorator.decorate(data, pending: &self.decoratorPending,
                                                         colorizeIP: true, tailKeep: 32)
                if self.displayTimestamp {
                    if self.timestampSwitchChangedToOn(true) {
                        self.timestampState = TerminalTextDecorator.TimestampPrefixState()
                    }
                    out = TerminalTextDecorator.prefixLines(out, state: &self.timestampState)
                } else {
                    _ = self.timestampSwitchChangedToOn(false)
                }
                if !out.isEmpty {
                    self.terminal.feed(byteArray: Array(out)[...])
                    self.afterFeed(out)
                }
            }
        }
        c.onError = { [weak self] err in
            DispatchQueue.main.async { self?.handleDisconnected(error: err) }
        }
        client = c
        c.connect(host: session.host, port: Int(session.port))
    }

    /// 意外断开/连接失败：提示 + 标记断开，按 R 重连
    private func handleDisconnected(error: Error?) {
        guard isOpen else { return }
        let tail = TerminalTextDecorator.flush(pending: &decoratorPending, colorizeIP: true)
        if !tail.isEmpty { terminal?.feed(byteArray: Array(tail)[...]) }
        client?.close()
        client = nil
        if let t = terminal {
            let why = error?.localizedDescription ?? ""
            t.feed(text: "\r\n（Telnet 已断开\(why.isEmpty ? "" : "：\(why)")，按 R 重新连接）\r\n")
        }
        markTerminated()
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: TerminalView, title: String) {
        onTitleChange?(title)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        client?.send(Data(data))
    }

    /// 从外部注入文本（粘贴 / 宏）：telnet 是裸 TCP，行尾统一转 \r\n 才有回车效果
    override func sendInput(_ text: String) {
        guard !text.isEmpty else { return }
        let crlf = text.replacingOccurrences(of: "\n", with: "\r\n")
        client?.send(Data(crlf.utf8))
    }

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

    override func closeSession() {
        guard isOpen else { return }
        client?.close()
        client = nil
        super.closeSession()
    }

    // MARK: - 会话菜单动作

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
        "\(session.host.replacingOccurrences(of: "/", with: "_"))_\(session.port).log"
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
}
