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

/// SSH_ASKPASS 机制：让系统 ssh 借助独立程序自动应答密码提示。
/// 脚本内容不内嵌密码，密码通过环境变量 ML_ASKPW 传入，脚本只负责打印该变量。
enum AskpassHelper {
    static func ensureScript() -> String {
        let url = AppLocations.supportDir.appendingPathComponent("mobalike-askpass.sh")
        let content = "#!/bin/sh\nprintf '%s\\n' \"$ML_ASKPW\"\n"
        do {
            if !FileManager.default.fileExists(atPath: url.path) {
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
            // ssh 要求 askpass 程序所有者是当前用户且不被组/其他可写
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            // 失败则退回交互输入
            return ""
        }
        return url.path
    }
}
