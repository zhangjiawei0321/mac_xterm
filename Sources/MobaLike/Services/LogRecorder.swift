import Foundation

/// 会话「记录日志」写入器（SecureCRT 风格）：把开始记录之后的输出实时追加到指定文件。
/// 非主线程隔离（可能从读取线程调用），文件句柄只由单一调用路径写入。
final class LogRecorder {
    private let fileURL: URL
    private let handle: FileHandle
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

    /// 追加一块输出（就是送入终端显示的那份数据，含着色/时间戳处理后的结果）
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        try? handle.write(contentsOf: data)
        savedBytes += data.count
    }

    /// 结束记录，关闭文件
    func close() {
        try? handle.close()
    }

    var url: URL { fileURL }
}
