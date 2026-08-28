import AppKit
import SwiftTerm

/// 串口会话：TerminalView + 串口桥接
@MainActor
final class SerialViewController: TermSessionController, TerminalViewDelegate {
    let session: SessionConfig
    var terminal: TerminalView!
    private var port: SerialPort?
    /// 是否在终端显示时给每行加时间戳（设置项）
    private var displayTimestamp: Bool { UserDefaults.standard.bool(forKey: "displayTimestamp") }
    /// 行状态：是否处于行首（跨数据块连续）
    private var lineStart = true

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
        guard port == nil else { return }
        sessionStart = Date()
        let sp = SerialPort()
        do {
            try sp.open(path: session.serial.device,
                        baudRate: session.serial.baudRate,
                        dataBits: session.serial.dataBits,
                        parity: session.serial.parity,
                        stopBits: session.serial.stopBits,
                        flowControl: session.serial.flowControl)
        } catch {
            let msg = "【错误】\(error.localizedDescription)\n\n请选择正确的串口设备后再连接。\r\n"
            terminal?.feed(text: msg)
            markTerminated()
            return
        }
        port = sp
        sp.onDisconnect = { [weak self] in
            DispatchQueue.main.async { self?.handlePortDisconnected() }
        }
        sp.startReading { [weak self] data in
            guard let self else { return }
            // feed 本身线程安全，这里直接在读线程喂给终端
            if self.displayTimestamp {
                let stamped = Self.prefixLines(data, lineStart: &self.lineStart)
                self.terminal.feed(byteArray: Array(stamped)[...])
            } else {
                self.terminal.feed(byteArray: Array(data)[...])
            }
        }
        onStateChange?(true)
        terminal.feed(text: "已连接到 \(session.serial.device)（\(session.serial.baudRate) 波特）\r\n")
    }

    /// 串口设备意外断开（拔出/掉线）：提示 + 标记断开，支持按 R 重连
    private func handlePortDisconnected() {
        guard isOpen else { return }
        port?.close()
        port = nil
        if let t = terminal {
            t.feed(text: "\r\n（串口已断开，请重新插好设备后按 R 重新连接）\r\n")
        }
        markTerminated()
    }

    /// 给接收的每一整行前加时间戳（yyyy-MM-dd HH:mm:ss.SSS）
    private static func prefixLines(_ data: Data, lineStart: inout Bool) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        var start = 0
        if lineStart {
            out.append(Data("[\(LogExport.timestampString(Date()))] ".utf8))
        }
        for i in 0..<bytes.count where bytes[i] == 10 {   // \n
            out.append(Data(bytes[start...i]))
            start = i + 1
            lineStart = true
            if start < bytes.count {
                out.append(Data("[\(LogExport.timestampString(Date()))] ".utf8))
            }
        }
        if start < bytes.count {
            out.append(Data(bytes[start...]))
            lineStart = false
        }
        return out
    }

    // MARK: TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: TerminalView, title: String) {}

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    /// 用户输入 -> 串口
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        port?.write(Data(data))
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

    func clipboardRead(source: TerminalView) -> Data? { return nil }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    override func closeSession() {
        guard isOpen else { return }
        port?.close()
        port = nil
        super.closeSession()
    }

    // MARK: - 会话菜单动作

    override func sendInput(_ text: String) {
        guard !text.isEmpty else { return }
        port?.write(Data(text.utf8))
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
        let dev = (session.serial.device as NSString).lastPathComponent
        return "\(dev.isEmpty ? "串口" : dev).log"
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
