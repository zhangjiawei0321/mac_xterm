import Foundation

/// ANSI/控制转义序列剥离器：把原始终端字节流变成干净文本（去掉颜色码、括号粘贴标记、
/// 窗口标题 OSC 等），跨数据块安全（一段转义序列被两块数据拆开也能正确剥除）。
struct AnsiStripper {
    private enum Mode { case normal, esc, osc, csi }
    private var mode: Mode = .normal
    /// OSC 里刚读到 ESC：可能是 ST（ESC \）的起始
    private var oscEscaped = false

    mutating func strip(_ data: Data) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        for b in data {
            switch mode {
            case .normal:
                if b == 0x1B { mode = .esc }
                else if b == 0x9B { mode = .csi }        // 8-bit CSI
                else if b == 0x9D { mode = .osc }        // 8-bit OSC
                else { out.append(b) }                    // 普通可见字符原样保留
            case .esc:
                switch b {
                case 0x5B: mode = .csi                    // ESC [
                case 0x5D: mode = .osc                    // ESC ] OSC
                case 0x50, 0x58, 0x5E, 0x5F: mode = .osc  // DCS/PM/APC（同样到 BEL/ST 结束）
                default: mode = .normal                   // ESC + 单字符（如 '(' 'M' 等）
                }
            case .osc:
                if oscEscaped {
                    // 刚看到 ESC：若是 '\'（ST）或 BEL 则序列结束
                    _ = b
                    mode = .normal
                    oscEscaped = false
                } else if b == 0x07 {                     // BEL 结束
                    mode = .normal
                } else if b == 0x1B {                     // 可能是 ST(ESC \) 的起点
                    oscEscaped = true
                }
                // 其它字符都是 OSC 内容，丢弃
            case .csi:
                if b >= 0x40 && b <= 0x7E { mode = .normal }   // 终结字符
                else if b == 0x1B { mode = .esc }              // 罕见嵌套，回退
                // 参数/中间字节继续吞掉
            }
        }
        return Data(out)
    }
}

/// 会话「记录日志」写入器（SecureCRT 风格）：把开始记录之后的输出实时追加到指定文件。
/// 写入前会剥离 ANSI 控制转义，文件里保存干净文本。
/// 非主线程隔离（可能从读取线程调用），文件句柄只由单一调用路径写入。
final class LogRecorder {
    private let fileURL: URL
    private let handle: FileHandle
    private var stripper = AnsiStripper()
    private(set) var savedBytes = 0

    /// 打开（必要时创建）日志文件并从文件尾开始追加。
    init?(url: URL) {
        fileURL = url
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.createFile(atPath: url.path, contents: nil, attributes: nil) else { return nil }
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return nil }
        do { try h.seekToEnd() } catch { try? h.close(); return nil }
        handle = h
        // 写入一个带开始时间的文件头，便于区分多次记录
        let head = "\n====  \(LogExport.timestampString(Date()))  开始记录日志  ====\n\n"
        if let d = head.data(using: .utf8) {
            try? handle.write(contentsOf: d)
            savedBytes = d.count
        }
    }

    /// 追加一块输出（就是送入终端显示的那份数据）；写入前剥掉 ANSI 颜色/控制序列
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        let clean = stripper.strip(data)
        guard !clean.isEmpty else { return }
        try? handle.write(contentsOf: clean)
        savedBytes += clean.count
    }

    /// 结束记录，关闭文件
    func close() {
        try? handle.close()
    }

    var url: URL { fileURL }
}
