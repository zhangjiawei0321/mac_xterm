import Foundation
import Darwin

enum SerialError: LocalizedError {
    case cannotOpen(String, Int32)
    case configure(String)
    case readFailure(String)
    case portBusy(String, Int32)
    case alreadyInApp

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let msg, let code):
            return "无法打开串口设备：\(msg) (errno=\(code))"
        case .configure(let msg):
            return "串口参数配置失败：\(msg)"
        case .readFailure(let msg):
            return "串口读取失败：\(msg)"
        case .portBusy(let msg, let code):
            return "串口正被其他程序占用（\(msg)，errno=\(code)）。请先在占用它的工具（如 screen / cu / minicom / 其它串口软件）里关闭，再重新连接。"
        case .alreadyInApp:
            return "该串口已经在 NblityTerm 中打开了，请先关闭已有的该串口会话。"
        }
    }
}

/// 极简串口封装：POSIX open/termios/poll
final class SerialPort {
    private var fd: Int32 = -1
    private var path = ""
    private var stopReading = false
    private var readThread: Thread?
    private var onData: ((Data) -> Void)?
    private let lock = NSLock()
    /// 设备意外断开（拔出/掉线，非主动关闭）时回调
    var onDisconnect: (() -> Void)?

    var isOpen: Bool { lock.withLock { fd >= 0 } }

    /// 打开并配置串口
    func open(path: String,
              baudRate: Int,
              dataBits: Int,
              parity: Parity,
              stopBits: Int,
              flowControl: FlowControl) throws {
        close()

        // 用 O_NONBLOCK 打开（避免阻塞），随后用非阻塞 flock 检测端口是否被其他程序占用。
        // 不能用 O_EXLOCK：它会让 open() 在端口被占时无限阻塞，导致整个 App 卡死。
        let newFd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard newFd >= 0 else {
            throw SerialError.cannotOpen(String(cString: strerror(errno)), errno)
        }

        // 非阻塞独占记录锁：端口正被 screen/cu/minicom 等持有锁时立即失败，而不是阻塞卡死
        // （不能用 O_EXLOCK：它会让 open() 在端口被占时无限阻塞，导致整个 App 卡死）
        var fl = flock()
        fl.l_type = Int16(F_WRLCK)
        fl.l_whence = Int16(SEEK_SET)
        fl.l_start = 0
        fl.l_len = 0
        if fcntl(newFd, F_SETLK, &fl) == -1 {
            let e = errno
            Darwin.close(newFd)
            throw SerialError.portBusy(String(cString: strerror(e)), e)
        }

        guard SerialPort.claim(path) else {
            Darwin.close(newFd)
            throw SerialError.alreadyInApp
        }

        var t = termios()
        guard tcgetattr(newFd, &t) == 0 else {
            let e = errno
            Darwin.close(newFd)
            SerialPort.release(path)
            throw SerialError.configure(String(cString: strerror(e)))
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
            let e = errno
            Darwin.close(newFd)
            SerialPort.release(path)
            throw SerialError.configure(String(cString: strerror(e)))
        }

        guard tcsetattr(newFd, TCSANOW, &t) == 0 else {
            let e = errno
            Darwin.close(newFd)
            SerialPort.release(path)
            throw SerialError.configure(String(cString: strerror(e)))
        }
        tcflush(newFd, TCIOFLUSH)

        fd = newFd
        self.path = path
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
        if !path.isEmpty {
            SerialPort.release(path)
            path = ""
        }
        onData = nil
    }

    // MARK: - 本 App 内占用登记：同一串口只允许一个会话打开

    private static let occupiedLock = NSLock()
    private static var occupied = Set<String>()

    /// 登记占用；已被本 App 其他会话占用时返回 false
    static func claim(_ path: String) -> Bool {
        occupiedLock.lock()
        defer { occupiedLock.unlock() }
        guard !occupied.contains(path) else { return false }
        occupied.insert(path)
        return true
    }

    static func release(_ path: String) {
        occupiedLock.lock()
        defer { occupiedLock.unlock() }
        occupied.remove(path)
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
            if ret > 0 {
                let errMask = Int16(POLLHUP) | Int16(POLLERR) | Int16(POLLNVAL)
                if (pfd.revents & errMask) != 0 { break }   // 设备拔出/掉线
                if (pfd.revents & Int16(POLLIN)) != 0 {
                    let n = read(fd, &buf, buf.count)
                    if n > 0 {
                        onData?(Data(bytes: buf, count: n))
                    } else if n < 0 {
                        break   // 读取失败（如设备拔出）
                    }
                }
            }
        }
        // 非主动关闭导致的退出 = 设备意外断开
        if !stopReading {
            onDisconnect?()
        }
    }

    /// macOS 的 termios 直接以数值作为波特率（B115200==115200 等），
    /// 因此这里直接透传任意数字即可支持 921600 及各种自定义波特率。
    private func baudFlag(for baud: Int) -> speed_t {
        speed_t(max(baud, 1))
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
