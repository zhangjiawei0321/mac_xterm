import Foundation

/// 应用数据存放目录
enum AppLocations {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MobaLike", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var sessionsFile: URL {
        supportDir.appendingPathComponent("sessions.json")
    }
}
