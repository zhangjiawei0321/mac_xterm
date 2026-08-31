import Foundation

/// 文件浏览器后端统一接口：SSH → 远端（ssh/sftp 命令）；本地终端 → 本地文件系统
protocol FileClient {
    var identity: String { get }
    func home() -> (String, String?)
    func list(path: String) -> ([SftpEntry], String?)
    func put(local: String, remote: String) -> String?
    func get(remote: String, local: String) -> String?
    func mkdir(path: String) -> String?
    func removeFile(path: String) -> String?
    func removeDir(path: String) -> String?
    func rename(from old: String, to new: String) -> String?
}

/// SFTP 目录项（一个文件/文件夹条目）
struct SftpEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let isDirectory: Bool
    let size: Int64
    let perms: String

    /// 人类可读大小
    var sizeText: String {
        guard !isDirectory else { return "" }
        let f = Double(size)
        if f >= 1_073_741_824 { return String(format: "%.1f GB", f / 1_073_741_824) }
        if f >= 1_048_576 { return String(format: "%.1f MB", f / 1_048_576) }
        if f >= 1024 { return String(format: "%.0f KB", f / 1024) }
        return "\(size) B"
    }
}

/// 远端文件客户端：复用系统 `ssh`（走 SSH_ASKPASS 自动登录），
/// 列目录/传输/建删改都走 ssh 单条命令（比 sftp 批处理更稳，尤其 Ubuntu）。
final class SftpClient: FileClient {
    let host: String
    let port: Int
    let user: String
    let password: String

    init(host: String, port: Int, user: String, password: String) {
        self.host = host
        self.port = port
        self.user = user
        self.password = password
    }

    func matches(host h: String, port p: Int, user u: String, password pw: String) -> Bool {
        host == h && port == p && user == u && password == pw
    }

    var identity: String { "\(user)@\(host):\(port)" }

    // MARK: - 操作

    /// 读登录用户主目录
    func home() -> (String, String?) {
        guard let r = runSSH(script: "printf '%s' \"$HOME\"", timeout: 15), r.status == 0 else {
            return ("", "无法连接远端")
        }
        let home = String(data: r.output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return home.isEmpty ? ("", "无法获取主目录") : (home, nil)
    }

    /// 列出目录（远端 ls + awk 只输出 类型|大小|名称）
    func list(path: String) -> ([SftpEntry], String?) {
        let script = """
        ls -la -- \(sh(path)) 2>/dev/null | awk 'NR>1 { t=substr($1,1,1); n=""; for(i=9;i<=NF;i++) n=n (i>9?" ":"") $i; if (n!="." && n!="..") print t " " $5 " " n }'
        """
        guard let r = runSSH(script: script, timeout: 20) else { return ([], "无法连接远端") }
        let entries = Self.parseCompact(String(data: r.output, encoding: .utf8) ?? "")
        if !entries.isEmpty { return (entries, nil) }
        if r.status != 0 || (String(data: r.output, encoding: .utf8) ?? "").contains("Permission denied") {
            return ([], String(data: r.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "列目录失败")
        }
        return ([], nil)
    }

    /// 上传：本地文件的数据经 ssh 直连命令写入远端（不经 base64 管道——那样 stdin 会被管道吃掉）
    func put(local: String, remote: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: local)) else {
            return "无法读取本地文件"
        }
        // wrap=false：直接把 "cat > 路径" 作为远端命令，ssh 的 stdin(=文件数据) 成为 cat 的输入
        guard let r = runSSH(script: "cat > \(sh(remote))", stdin: data, timeout: 0, wrap: false),
              r.status == 0 else {
            return "上传失败（远端拒绝）"
        }
        return nil
    }

    /// 下载：远端文件内容写为本地文件
    func get(remote: String, local: String) -> String? {
        guard let r = runSSH(script: "cat \(sh(remote))", stdin: nil, timeout: 0), r.status == 0 else {
            return "下载失败（远端拒绝或无此文件）"
        }
        do {
            try r.output.write(to: URL(fileURLWithPath: local))
            return nil
        } catch {
            return "写入本地失败：\(error.localizedDescription)"
        }
    }

    func mkdir(path: String) -> String? {
        guard let r = runSSH(script: "mkdir -p \(sh(path))", timeout: 20), r.status == 0 else {
            return "创建目录失败"
        }
        return nil
    }

    func removeFile(path: String) -> String? {
        guard let r = runSSH(script: "rm -f -- \(sh(path))", timeout: 20), r.status == 0 else {
            return "删除失败"
        }
        return nil
    }

    func removeDir(path: String) -> String? {
        guard let r = runSSH(script: "rm -rf -- \(sh(path))", timeout: 20), r.status == 0 else {
            return "删除目录失败"
        }
        return nil
    }

    func rename(from old: String, to new: String) -> String? {
        guard let r = runSSH(script: "mv -- \(sh(old)) \(sh(new))", timeout: 20), r.status == 0 else {
            return "重命名失败"
        }
        return nil
    }

    // MARK: - 进程（ssh 单命令，可带 stdin 二进制）

    /// shell 单引号转义
    private func sh(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func runSSH(script: String, stdin: Data? = nil, timeout: TimeInterval, wrap: Bool = true) -> (output: Data, status: Int32)? {
        let remoteCommand: String
        if wrap {
            let b64 = Data(script.utf8).base64EncodedString()
            remoteCommand = "sh -c 'printf %s \(b64) | base64 -d | sh'"
        } else {
            remoteCommand = script   // 直连命令：ssh 的 stdin 直达该命令（用于上传 cat >）
        }
        var args = ["-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ConnectTimeout=5",
                    "-o", "NumberOfPasswordPrompts=1",
                    "-p", "\(port)",
                    "\(user)@\(host)",
                    remoteCommand]
        var env = ProcessInfo.processInfo.environment
        if password.isEmpty {
            args.insert(contentsOf: ["-o", "BatchMode=yes"], at: 1)
        } else {
            let askpass = AskpassHelper.ensureScript()
            env["SSH_ASKPASS"] = askpass
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
            env["ML_ASKPW"] = password
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = args
        p.environment = env

        let inPipe = Pipe()
        let outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = outPipe
        do {
            try p.run()
        } catch {
            return nil
        }
        if let stdin {
            inPipe.fileHandleForWriting.write(stdin)
        }
        try? inPipe.fileHandleForWriting.close()

        var watchdog: DispatchWorkItem?
        if timeout > 0 {
            watchdog = DispatchWorkItem { [weak p] in
                if let p, p.isRunning { p.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog!)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog?.cancel()
        return (data, p.terminationStatus)
    }

    // MARK: - 解析

    /// 解析远端 `ls` 紧凑输出：每行 `类型 大小 名称...`（类型 d=目录）
    static func parseCompact(_ raw: String) -> [SftpEntry] {
        var entries: [SftpEntry] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 2)
            guard parts.count == 3, parts[0].count == 1, let sz = Int64(parts[1]) else { continue }
            let name = String(parts[2])
            if name == "." || name == ".." { continue }
            entries.append(SftpEntry(name: name, isDirectory: parts[0] == "d", size: sz, perms: ""))
        }
        return entries
    }
}
