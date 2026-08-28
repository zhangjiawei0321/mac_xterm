import Foundation

/// 终端输出流的装饰器：向进入终端的字节流中插入颜色转义（如把 IPv4 地址染成青蓝色）。
/// 只做字节级操作，不破坏多字节 UTF-8；跨数据块的安全通过保留尾部字节实现。
enum TerminalTextDecorator {
    /// IP 符号用颜色（标准青色，MobaXterm 常用）
    private static let ipEscape = "\u{1b}[36m"
    private static let resetEscape = "\u{1b}[0m"

    /// 处理一块新数据。`pending` 是跨块保留的尾部（调用方维护），返回可送入终端的字节后，
    /// 把未处理完的尾部写回 `pending`。
    ///
    /// 采用低延迟的流式策略：只保留“可能是还没写完的 IP”的尾部片段（这样跨数据块被拆开的
    /// IP 也能正确着色），其余字节立即处理并返回，避免短输出被长时间压在缓冲区里导致
    /// 交互式终端“卡住不显示”。
    /// - Parameters:
    ///   - tailKeep: 尾部保留长度的上限（IP 最长 ~15 字节，给 32 足够）
    @discardableResult
    static func decorate(_ data: Data, pending: inout [UInt8], colorizeIP: Bool, tailKeep: Int = 32) -> Data {
        pending.append(contentsOf: data)
        guard !pending.isEmpty else { return Data() }

        let n = pending.count
        // 从尾部往回找开放的 [0-9.] 片段（真正的 IP 只会由数字和点组成）
        var runStart = n
        while runStart > 0, isDigitOrDot(pending[runStart - 1]) { runStart -= 1 }

        var hold = 0
        if runStart < n {
            let runLen = n - runStart
            if runLen > tailKeep {
                hold = tailKeep          // 太长的连续数字/点，只保留可能是 IP 的尾部
            } else if runLen > 15 {
                hold = 15                // 超过 IP 最大长度，不可能是单个未完 IP
            } else if runLen <= 15 {
                if runLen > 1 && pending[runStart..<n].contains(0x2E) {
                    hold = runLen        // 含点、未超 IP 长度 → 可能是未完 IP，整体保留
                } else if runLen <= 3 {
                    hold = runLen        // 纯数字且 ≤3 位 → 可能是未完的 octet
                } else {
                    hold = 0             // 纯数字且 >3 位 → 绝不可能是 IP，立即处理
                }
            }
        }

        let processable = n - hold
        let out = transform(Array(pending[0..<processable]), colorizeIP: colorizeIP)
        if hold > 0 {
            pending.removeFirst(processable)
        } else {
            pending.removeAll()
        }
        return out
    }

    private static func isDigitOrDot(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || b == 0x2E
    }

    /// 处理完最后一块后调用：把遗留尾部处理出来并清空 pending
    static func flush(pending: inout [UInt8], colorizeIP: Bool) -> Data {
        guard !pending.isEmpty else { return Data() }
        let out = transform(pending, colorizeIP: colorizeIP)
        pending.removeAll()
        return out
    }

    // MARK: - 显示时间戳

    /// 时间戳前缀（逐行加）所需的跨块状态
    struct TimestampPrefixState {
        /// 是否正处于行首（上一个输出的是 \n，或刚被 \r 重绘定位）
        var lineStart = true
        /// 当前光标所在行是否已由我们插入过时间戳
        var stampOnLine = false
    }

    /// 给每一整行加前缀时间戳（用于“显示时加入时间戳”）。
    ///
    /// 要点：交互式 shell（bash/readline）打命令或按回车后，可能用单独 `\r` 在同一行
    /// 从行首**重绘**（其文本常比我们的“时间戳+内容”短，盖不完就残留 `.xxx]` 尾巴）。
    /// 对策：
    ///  - `\r\n`：正常结束一行；
    ///  - 单独 `\r`（同行覆盖重绘）：若本行已插过时间戳，就接着发 `\e[2K`（整行清除），
    ///    让重绘文本整体盖在干净行上 → 要么不覆盖、要么全覆盖，绝不留尾巴。
    static func prefixLines(_ data: Data, state: inout TimestampPrefixState) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        let elClear = [UInt8]("\u{1b}[2K".utf8)   // EL=2：整行清除
        var i = 0
        let n = bytes.count
        while i < n {
            let b = bytes[i]
            if b == 10 {                         // \n：本行结束
                out.append(b)
                i += 1
                state.lineStart = true
                state.stampOnLine = false
            } else if b == 13 {                  // \r
                let isCRLF = (i + 1 < n) && bytes[i + 1] == 10
                out.append(b)                    // 光标回行首
                i += 1
                if !isCRLF {
                    // 单独 \r：同行覆盖重绘。若本行插过时间戳，清空整行防残留尾巴
                    if state.stampOnLine {
                        out.append(contentsOf: elClear)
                    }
                    state.lineStart = true       // 重绘的内容会从行首开始
                }
            } else if state.lineStart {          // 真正的新行内容：先插时间戳
                state.lineStart = false
                state.stampOnLine = true
                out.append(Data("[\(LogExport.timestampString(Date()))] ".utf8))
            } else {
                out.append(b)
                i += 1
            }
        }
        return out
    }

    private static func transform(_ bytes: [UInt8], colorizeIP: Bool) -> Data {
        guard colorizeIP else { return Data(bytes) }
        var out = [UInt8]()
        out.reserveCapacity(bytes.count + 16)
        let esc = [UInt8](ipEscape.utf8)
        let reset = [UInt8](resetEscape.utf8)

        var i = 0
        let n = bytes.count
        while i < n {
            // 仅当是数字时才尝试匹配 IP
            if bytes[i] >= 0x30, bytes[i] <= 0x39, let ipLen = matchIPv4(bytes, from: i) {
                out.append(contentsOf: esc)
                out.append(contentsOf: bytes[i..<(i + ipLen)])
                out.append(contentsOf: reset)
                i += ipLen
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return Data(out)
    }

    /// 在 bytes[from..] 处匹配一个 IPv4（1-3 位数字 + . + ...），要求前后都不是合法组成部分。
    private static func matchIPv4(_ bytes: [UInt8], from: Int) -> Int? {
        var count = 0
        var p = from

        func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
        func boundary(_ idx: Int) -> Bool {
            guard idx >= 0, idx < bytes.count else { return true }
            let b = bytes[idx]
            return !(isDigit(b) || b == 0x2E)   // 非数字/非点
        }

        // 前面的边界
        guard boundary(from - 1) else { return nil }

        for _ in 0..<4 {
            let start = p
            var len = 0
            while p < bytes.count, isDigit(bytes[p]), len < 3 {
                p += 1
                len += 1
            }
            guard len >= 1 else { return nil }
            if len == 3 {
                let a = Int(bytes[start] - 0x30) * 100 + Int(bytes[start + 1] - 0x30) * 10 + Int(bytes[start + 2] - 0x30)
                if a > 255 { return nil }
            }
            if count < 3 {
                guard p < bytes.count, bytes[p] == 0x2E else { return nil }
                p += 1
            }
            count += 1
        }
        // 后面的边界
        guard boundary(p) else { return nil }
        return p - from
    }
}
