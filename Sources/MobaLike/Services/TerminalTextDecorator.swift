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

    /// 给每一整行加前缀时间戳（用于“显示时加入时间戳”）。
    /// 要点：交互式 shell 在打完命令/按下回车后，readline 会先用 `\r` 把光标移回行首
    /// 再重绘提示符。若时间戳插在 `\r` 之前，重绘就会从行首把它盖掉（残留 `.xxx]` 尾巴）。
    /// 因此：处于行首时放行前导 `\r`（保持行首状态），等真正的内容字节到达后再插时间戳。
    static func prefixLines(_ data: Data, lineStart: inout Bool) -> Data {
        var out = Data()
        let bytes = [UInt8](data)
        var i = 0
        let n = bytes.count
        while i < n {
            let b = bytes[i]
            if b == 10 {            // \n：本行结束
                out.append(b)
                i += 1
                lineStart = true
            } else if lineStart && b == 13 {   // 行首的 \r：仅定位（重绘前的回行首），先放行
                out.append(b)
                i += 1
            } else if lineStart {   // 真正的新行内容：先插时间戳
                lineStart = false
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
