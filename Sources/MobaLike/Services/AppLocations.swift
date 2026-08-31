import Foundation

/// 应用数据存放目录
enum AppLocations {
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("NblityTerm", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 一次性迁移旧名 MobaLike 的数据（会话/宏/askpass 脚本），避免改名后丢失
        let legacy = base.appendingPathComponent("MobaLike", isDirectory: true)
        for file in ["sessions.json", "macros.json", "mobalike-askpass.sh"] {
            let dst = dir.appendingPathComponent(file)
            let src = legacy.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: dst.path),
               FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(at: src, to: dst)
            }
        }
        return dir
    }

    static var sessionsFile: URL {
        supportDir.appendingPathComponent("sessions.json")
    }

    static var macrosFile: URL {
        supportDir.appendingPathComponent("macros.json")
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
