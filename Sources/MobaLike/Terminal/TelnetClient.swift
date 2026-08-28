import Foundation
import Network

/// 极简 Telnet 客户端：TCP + 基础 telnet 协商（常见选项反制），透传其余数据。
final class TelnetClient {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "mobalike.telnet")
    private var userClosed = false

    /// 收到服务器回显的处理后数据（协商已剥离）
    var onData: ((Data) -> Void)?
    /// 连接建立（服务器协商完成后进入数据阶段）
    var onConnected: (() -> Void)?
    /// 意外断开/失败（非主动关闭）
    var onError: ((Error?) -> Void)?

    func connect(host: String, port: Int) {
        userClosed = false
        guard let rawPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            onError?(nil)
            return
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: rawPort, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onConnected?()
                self.startReceive()
            case .failed(let err):
                if !self.userClosed { self.onError?(err) }
            case .cancelled:
                if !self.userClosed { self.onError?(nil) }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    func send(_ data: Data) {
        guard !data.isEmpty, let conn = connection else { return }
        conn.send(content: data, contentContext: .defaultMessage, isComplete: false,
                  completion: .contentProcessed { _ in })
    }

    func close() {
        userClosed = true
        connection?.cancel()
        connection = nil
    }

    private func startReceive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                let (payload, replies) = self.negotiate(data)
                if !replies.isEmpty {
                    self.connection?.send(content: replies, contentContext: .defaultMessage,
                                          isComplete: false, completion: .contentProcessed { _ in })
                }
                if !payload.isEmpty {
                    self.onData?(payload)
                }
            }
            if isComplete || error != nil {
                if !self.userClosed { self.onError?(error) }
                return
            }
            self.startReceive()
        }
    }

    // telnet 常量
    private let IAC: UInt8 = 255
    private let DONT: UInt8 = 254, DO: UInt8 = 253, WONT: UInt8 = 252, WILL: UInt8 = 251
    private let SB: UInt8 = 250, SE: UInt8 = 240

    /// 解析 telnet 字节流：返回 (透传给终端的数据, 需要回发给服务器的协商应答)
    private func negotiate(_ data: Data) -> (Data, Data) {
        var payload = Data()
        var replies = Data()
        let b = [UInt8](data)
        var i = 0
        while i < b.count {
            if b[i] == IAC {
                guard i + 1 < b.count else { break }
                let cmd = b[i + 1]
                switch cmd {
                case WILL, WONT, DO, DONT:
                    guard i + 2 < b.count else { break }
                    let opt = b[i + 2]
                    switch opt {
                    case 3:   // SUPPRESS_GO_AHEAD
                        replies.append(contentsOf: cmd == DO ? [IAC, WILL, 3] : [IAC, DO, 3])
                    case 1:   // ECHO：让服务器回显，本地不 ECHO
                        replies.append(contentsOf: cmd == DO ? [IAC, WONT, 1] : [IAC, DONT, 1])
                    case 24:  // TERMINAL_TYPE
                        replies.append(contentsOf: cmd == DO ? [IAC, WILL, 24] : [IAC, DO, 24])
                    case 31:  // NAWS
                        replies.append(contentsOf: cmd == DO ? [IAC, WILL, 31] : [IAC, DO, 31])
                    default:
                        replies.append(contentsOf: cmd == WILL || cmd == DO ? [IAC, DONT, opt] : [IAC, WONT, opt])
                    }
                    i += 3
                case SB:
                    var j = i + 2
                    while j + 1 < b.count, !(b[j] == IAC && b[j + 1] == SE) { j += 1 }
                    let end = min(j + 2, b.count)
                    let opt = b[min(i + 2, end - 1)]
                    if opt == 24 && j - (i + 3) >= 1 && b[min(i + 3, end - 1)] == 1 {
                        // SB TERMINAL_TYPE SEND → 回 IS "xterm-256color"
                        let type: [UInt8] = Array("xterm-256color".utf8)
                        replies.append(IAC); replies.append(SB); replies.append(24); replies.append(0); replies.append(contentsOf: type)
                        replies.append(IAC); replies.append(SE)
                    }
                    i = end
                case SE:
                    i += 2
                default:
                    i += 2
                }
            } else {
                payload.append(b[i])
                i += 1
            }
        }
        return (payload, replies)
    }
}
