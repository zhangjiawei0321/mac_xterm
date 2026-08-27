import Foundation

/// 日志导出工具：把终端缓冲文本写出，可选“带时间戳”格式
enum LogExport {
    /// 会话开始到写入时刻的真实时长，按行数均匀分布，给每行打上单调递增的时间戳。
    /// 说明：终端缓冲本身不记录每行的精确时间；这里用会话起止时间做均匀近似，
    /// 串口等自建接收路径可在实现里写入精确时间。
    static func timestamped(_ data: Data, start: Date) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return data }

        let duration = max(Date().timeIntervalSince(start), 0)
        let step = lines.count > 1 ? duration / Double(lines.count - 1) : 0
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"

        var out = ""
        for (i, line) in lines.enumerated() {
            if !line.isEmpty {
                let t = start.addingTimeInterval(step * Double(i))
                out += "[\(df.string(from: t))] \(line)\n"
            } else {
                out += "\n"
            }
        }
        return Data(out.utf8)
    }
}
