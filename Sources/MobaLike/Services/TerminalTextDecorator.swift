import Foundation

/// 终端输出流的装饰器：向进入终端的字节流中插入颜色转义（如把 IPv4 地址染成青蓝色）。
/// 只做字节级操作，不破坏多字节 UTF-8；跨数据块的安全通过保留尾部字节实现。
enum TerminalTextDecorator {
    /// IP 符号用颜色（标准青色，MobaXterm 常用）
    private static let ipEscape = "\u{1b}[36m"
    private static let resetEscape = "\u{1b}[0m"

    /// 处理一块新数据。返回可送入终端的字节。
    ///
    /// ⚠️ 这里的重点是「绝不扣留已到达的字节」：shell 会把我们逐键敲入的内容逐个回显到
    /// 这条流里，若为了给“可能还没写完的 IP”着色而把尾部数字/点扣在 pending 里（旧逻辑最多
    /// 扣 3 位），用户敲数字就会“每满 4 个字符才落屏”：`1`→扣、`12`→扣、`123`→扣，
    /// 敲第 4 个凑成 4 位才放行，连同前面的 4 个一起显示——字母不扣、数字扣，交互直接坏掉。
    ///
    /// 所以现在：所有字节立即处理并返回，不做跨块留存。IP 着色只对「完整出现在同一块数据
    /// 内」的 IP 生效；恰好被两块数据在 IP 中间截断的 IP 不再染色（低频、纯美观，可接受）。
    @discardableResult
    static func decorate(_ data: Data, pending: inout [UInt8], colorizeIP: Bool, tailKeep: Int = 32) -> Data {
        _ = tailKeep
        pending.removeAll()          // 不再使用尾部留存，保证逐键即时显示
        return transform([UInt8](data), colorizeIP: colorizeIP)
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
                if b != 0x1B {                   // ESC 开头的多为重绘/控制序列，跳过时间戳避免刷屏重叠
                    state.stampOnLine = true
                    out.append(Data("[\(LogExport.timestampString(Date()))] ".utf8))
                }
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
