import Foundation
import Darwin

enum SerialError: LocalizedError {
    case cannotOpen(String, Int32)
    case configure(String)
    case readFailure(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let msg, let code):
            return "无法打开串口设备：\(msg) (errno=\(code))"
        case .configure(let msg):
            return "串口参数配置失败：\(msg)"
        case .readFailure(let msg):
            return "串口读取失败：\(msg)"
        }
    }
}

/// 极简串口封装：POSIX open/termios/poll
final class SerialPort {
    private var fd: Int32 = -1
    private var stopReading = false
    private var readThread: Thread?
    private var onData: ((Data) -> Void)?
    private let lock = NSLock()

    var isOpen: Bool { lock.withLock { fd >= 0 } }

    /// 打开并配置串口
    func open(path: String,
              baudRate: Int,
              dataBits: Int,
              parity: Parity,
              stopBits: Int,
              flowControl: FlowControl) throws {
        close()

        let newFd = Darwin.open(path, O_RDWR | O_NOCTTY | O_EXLOCK)
        guard newFd >= 0 else {
            throw SerialError.cannotOpen(String(cString: strerror(errno)), errno)
        }
        fd = newFd

        var t = termios()
        guard tcgetattr(fd, &t) == 0 else {
            throw SerialError.configure(String(cString: strerror(errno)))
        }

        cfmakeraw(&t)
        t.c_cflag |= tcflag_t(CLOCAL | CREAD)

        // 数据位
        t.c_cflag &= ~tcflag_t(CSIZE)
        switch dataBits {
        case 5: t.c_cflag |= tcflag_t(CS5)
        case 6: t.c_cflag |= tcflag_t(CS6)
        case 7: t.c_cflag |= tcflag_t(CS7)
        default: t.c_cflag |= tcflag_t(CS8)
        }

        // 校验位
        t.c_cflag &= ~tcflag_t(PARENB | PARODD)
        switch parity {
        case .even: t.c_cflag |= tcflag_t(PARENB)
        case .odd: t.c_cflag |= tcflag_t(PARENB | PARODD)
        case .none: break
        }

        // 停止位
        t.c_cflag &= ~tcflag_t(CSTOPB)
        if stopBits == 2 { t.c_cflag |= tcflag_t(CSTOPB) }

        // 流控
        t.c_cflag &= ~tcflag_t(CRTSCTS)
        t.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        switch flowControl {
        case .hardware: t.c_cflag |= tcflag_t(CRTSCTS)
        case .software: t.c_iflag |= tcflag_t(IXON | IXOFF)
        case .none: break
        }

        guard cfsetspeed(&t, baudFlag(for: baudRate)) == 0 else {
            throw SerialError.configure(String(cString: strerror(errno)))
        }

        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            throw SerialError.configure(String(cString: strerror(errno)))
        }
        tcflush(fd, TCIOFLUSH)
    }

    /// 后台线程持续读取，回调在主线程外调用（feed 是线程安全的）
    func startReading(_ onData: @escaping (Data) -> Void) {
        stopReading = false
        self.onData = onData
        let t = Thread { [weak self] in self?.readLoop() }
        readThread = t
        t.start()
    }

    /// 写入串口
    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        let fd = lock.withLock { self.fd }
        guard fd >= 0 else { return }
        data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: UInt8.self).baseAddress!
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(fd, ptr.advanced(by: offset), data.count - offset)
                if n > 0 { offset += n }
                else { break }  // EAGAIN（无流控时满缓冲）则丢弃本次
            }
        }
    }

    func close() {
        stopReading = true
        lock.withLock {
            if fd >= 0 {
                Darwin.close(fd)
                fd = -1
            }
        }
        onData = nil
    }

    // MARK: - private

    private func readLoop() {
        var buf = [UInt8](repeating: 0, count: 4096)
        while !stopReading {
            var pfd = pollfd()
            pfd.fd = fd
            pfd.events = Int16(POLLIN)
            pfd.revents = 0
            let ret = poll(&pfd, 1, 200)   // 200ms 超时，保证能及时退出
            if ret < 0 || stopReading { break }
            if ret > 0 && (pfd.revents & Int16(POLLIN)) != 0 {
                let n = read(fd, &buf, buf.count)
                if n > 0 {
                    onData?(Data(bytes: buf, count: n))
                } else if n < 0 {
                    break
                }
            }
        }
    }

    private func baudFlag(for baud: Int) -> speed_t {
        switch baud {
        case 1200: return speed_t(B1200)
        case 2400: return speed_t(B2400)
        case 4800: return speed_t(B4800)
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        case 460800: return speed_t(B460800)
        case 921600: return speed_t(B921600)
        default: return speed_t(B115200)
        }
    }

    /// 枚举系统可用串口 /dev/cu.*
    static func listDevices() -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else { return [] }
        return items.filter { $0.hasPrefix("cu.") }.sorted().map { "/dev/\($0)" }
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
