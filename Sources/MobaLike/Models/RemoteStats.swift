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

    private static func gb(_ bytes: Double) -> String {
        String(format: "%.1fG", bytes / 1_073_741_824)
    }
}
