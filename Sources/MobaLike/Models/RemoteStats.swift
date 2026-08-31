import Foundation

/// 远端监控的一帧数据（CPU/内存/磁盘/负载等）
struct RemoteStats {
    var host = ""
    var cpu: Double?          // 0-100（无则 nil）
    var memUsedBytes: Double?
    var memTotalBytes: Double?
    var loadText = ""
    var uptimeText = ""
    var disks: [(name: String, usedPercent: Double)] = []
    /// 网络：当前累计收发字节 + 引擎算出的实时速率（字节/秒）
    var netRxBytes: Double?
    var netTxBytes: Double?
    var netDownPerSec = 0.0
    var netUpPerSec = 0.0

    var cpuText: String {
        cpu.map { String(format: "%.1f%%", $0) } ?? "—"
    }
    var memUsedPercent: Double? {
        guard let u = memUsedBytes, let t = memTotalBytes, t > 0 else { return nil }
        return u / t * 100
    }
    var memoryText: String {
        guard let u = memUsedBytes, let t = memTotalBytes else { return "—" }
        return "\(Self.gb(u)) / \(Self.gb(t))"
    }
    var memoryPercentText: String {
        memUsedPercent.map { String(format: "%.0f%%", $0) } ?? "—"
    }

    /// 网络速率显示（下行 ↓ / 上行 ↑）
    var networkText: String {
        "↓ \(Self.rate(netDownPerSec)) · ↑ \(Self.rate(netUpPerSec))"
    }

    private static func gb(_ bytes: Double) -> String {
        String(format: "%.1fG", bytes / 1_073_741_824)
    }

    private static func rate(_ bps: Double) -> String {
        guard bps >= 0 else { return "—" }
        let kb = bps / 1024
        if kb >= 1024 { return String(format: "%.1f MB/s", kb / 1024) }
        return String(format: "%.0f KB/s", kb)
    }
}
