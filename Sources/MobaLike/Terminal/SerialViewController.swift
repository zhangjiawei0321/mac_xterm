import AppKit
import SwiftTerm

/// 串口会话：TerminalView + 串口桥接
@MainActor
final class SerialViewController: TermSessionController, TerminalViewDelegate {
    let session: SessionConfig
    var terminal: TerminalView!
    private var port: SerialPort?
    private let feedQueue = DispatchQueue(label: "mobalike.serial.feed")

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
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        startSession()
    }

    func startSession() {
        guard port == nil else { return }
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
        sp.startReading { [weak self] data in
            // feed 本身线程安全，这里直接在读线程喂给终端
            self?.terminal.feed(byteArray: Array(data)[...])
        }
        onStateChange?(true)
        terminal.feed(text: "已连接到 \(session.serial.device)（\(session.serial.baudRate) 波特）\r\n")
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
}
