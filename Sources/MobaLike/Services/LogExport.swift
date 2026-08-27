import Foundation

/// 日志与时间戳工具
enum LogExport {
    static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 时间戳字符串：yyyy-MM-dd HH:mm:ss.SSS（日期-时-分-秒-毫秒）
    static func timestampString(_ date: Date) -> String {
        df.string(from: date)
    }

    /// 会话开始到写入时刻的真实时长，按行数均匀分布，给每行打上单调递增的时间戳。
    /// 说明：终端缓冲本身不记录每行的精确时间；这里用会话起止时间做均匀近似。
    static func timestamped(_ data: Data, start: Date) -> Data {
        guard let text = String(data: data, encoding: .utf8) else { return data }
        let lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return data }

        let duration = max(Date().timeIntervalSince(start), 0)
        let step = lines.count > 1 ? duration / Double(lines.count - 1) : 0

        var out = ""
        for (i, line) in lines.enumerated() {
            if !line.isEmpty {
                let t = start.addingTimeInterval(step * Double(i))
                out += "[\(timestampString(t))] \(line)\n"
            } else {
                out += "\n"
            }
        }
        return Data(out.utf8)
    }
}
