import Foundation

/// 会话日志的环形缓存：字节数超过上限时丢弃最早的部分并记录被截断，
/// 以便“保存日志到上限”时提示用户保存全部/部分。
final class LogCache {
    private(set) var buffer = Data()
    /// 因超限被丢弃的字节数
    private(set) var droppedBytes = 0
    /// 是否已发生过截断（丢过旧内容）
    private(set) var truncated = false
    /// 本次截断是否已提示过用户（每个会话只提示一次）
    var alerted = false
    /// 缓存上限（字节）；0 = 不限制（一直捕获，不截断）
    let capBytes: Int

    init(capBytes: Int) {
        self.capBytes = capBytes
    }

    var isEmpty: Bool { buffer.isEmpty }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        // capBytes==0 表示不限量：一直捕获、永不截断
        if capBytes > 0, buffer.count > capBytes {
            let over = buffer.count - capBytes
            buffer.removeFirst(over)
            droppedBytes += over
            truncated = true
        }
    }

    /// 取最近最多 bytes 字节（部分保存用）
    func lastBounded(_ bytes: Int) -> Data {
        let n = min(max(bytes, 0), buffer.count)
        return buffer.suffix(n)
    }

    func reset() {
        buffer.removeAll()
        droppedBytes = 0
        truncated = false
        alerted = false
    }
}
