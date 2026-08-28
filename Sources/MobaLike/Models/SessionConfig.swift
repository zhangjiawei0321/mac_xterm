import Foundation

/// 会话类型
enum SessionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case ssh
    case telnet
    case serial
    case local

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ssh: return "SSH"
        case .telnet: return "Telnet"
        case .serial: return "串口 (Serial)"
        case .local: return "本地终端"
        }
    }

    /// SF 符号图标名
    var iconName: String {
        switch self {
        case .ssh: return "network"
        case .telnet: return "terminal"
        case .serial: return "dot.radiowaves.left.and.right"
        case .local: return "terminal"
        }
    }

    /// 该类型会话的默认端口
    var defaultPort: UInt16 {
        switch self {
        case .ssh: return 22
        case .telnet: return 23
        case .serial, .local: return 0
        }
    }
}

enum Parity: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, even, odd

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无 (None)"
        case .even: return "偶 (Even)"
        case .odd: return "奇 (Odd)"
        }
    }
}

enum FlowControl: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, hardware, software

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "无 (None)"
        case .hardware: return "硬件 (RTS/CTS)"
        case .software: return "软件 (XON/XOFF)"
        }
    }
}

/// 串口连接参数
struct SerialSettings: Codable, Equatable, Sendable {
    var device: String = ""     // 例如 /dev/cu.usbserial-0001
    var baudRate: Int = 115200
    var dataBits: Int = 8
    var parity: Parity = .none
    var stopBits: Int = 1
    var flowControl: FlowControl = .none
}

/// 一条可保存的会话配置（SSH 或 串口）
struct SessionConfig: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var kind: SessionKind = .ssh
    var createTime: Date = Date()

    // SSH 相关
    var host: String = ""
    var port: UInt16 = 22
    var username: String = ""
    var password: String = ""          // 预留：后续做自动登录（当前为终端内交互输入）
    var useKey: Bool = false
    var keyPath: String = ""

    // 串口相关
    var serial: SerialSettings = SerialSettings()

    /// 会话在标签页上的默认标题
    var defaultTabTitle: String {
        switch kind {
        case .ssh:
            return name.isEmpty ? (host.isEmpty ? "SSH" : "\(username.isEmpty ? "" : "\(username)@")\(host)") : name
        case .telnet:
            return name.isEmpty ? (host.isEmpty ? "Telnet" : "\(host):\(port)") : name
        case .serial:
            let dev = serial.device.isEmpty ? "" : serial.device
            return name.isEmpty ? (dev.isEmpty ? "串口" : dev) : name
        case .local:
            return "本地终端"
        }
    }
}
