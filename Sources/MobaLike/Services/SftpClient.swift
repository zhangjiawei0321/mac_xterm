import Foundation

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

/// 极简 SFTP 客户端：复用系统 `sftp` 命令（走 SSH_ASKPASS 自动登录，无需重复输密码）。
/// 每次操作起一个批次进程，主线程外调用。
final class SftpClient {
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

    // MARK: - 操作（返回值：nil=成功；否则为错误描述；或 (值, 错误)）

    func pwd() -> (String, String?) {
        let out = invoke(commands: ["pwd"], timeout: 15)
        guard let o = out else { return ("", "SFTP 进程启动失败") }
        // Remote working directory: /home/user
        if let range = o.range(of: "Remote working directory: ") {
            let path = o[range.upperBound...].split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            return (path, nil)
        }
        if o.contains("not found") || o.contains("Couldn't read packet") || o.isEmpty {
            return ("", o.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ("", nil)
    }

    func list(path: String) -> ([SftpEntry], String?) {
        // 1) 首选：sftp ls -la（标准格式解析）
        if let out = invoke(commands: ["ls -la \(path)"], timeout: 20) {
            let e = Self.parseListing(out)
            if !e.isEmpty { return (e, nil) }
            if out.contains("Permission denied") || out.contains("Couldn't") || out.contains("refused") {
                return ([], out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        // 2) 回退/更可靠：ssh 远端 ls，仅输出 类型|大小|名称（避免格式差异导致空目录）
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        ls -la -- '\(escaped)' 2>/dev/null | awk 'NR>1 { t=substr($1,1,1); n=""; for(i=9;i<=NF;i++) n=n (i>9?" ":"") $i; if (n!="." && n!="..") print t " " $5 " " n }'
        """
        if let out = runSSH(script, timeout: 20) {
            let entries = Self.parseCompact(out)
            if !entries.isEmpty { return (entries, nil) }
            if out.contains("Permission denied") || out.contains("refused") || out.contains("no such") {
                return ([], out.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return ([], nil)
        }
        return ([], "无法连接远端执行列表")
    }

    func put(local: String, remote: String) -> String? {
        let out = invoke(commands: ["put \(local) \(remote)"], timeout: 0)
        return Self.opError(from: out, name: "上传")
    }

    func get(remote: String, local: String) -> String? {
        let out = invoke(commands: ["get \(remote) \(local)"], timeout: 0)
        return Self.opError(from: out, name: "下载")
    }

    func mkdir(path: String) -> String? {
        let out = invoke(commands: ["mkdir \(path)"], timeout: 20)
        return Self.opError(from: out, name: "新建目录")
    }

    func removeFile(path: String) -> String? {
        let out = invoke(commands: ["rm \(path)"], timeout: 20)
        return Self.opError(from: out, name: "删除")
    }

    func removeDir(path: String) -> String? {
        let out = invoke(commands: ["rmdir \(path)"], timeout: 20)
        return Self.opError(from: out, name: "删除目录")
    }

    func rename(from old: String, to new: String) -> String? {
        let out = invoke(commands: ["rename \(old) \(new)"], timeout: 20)
        return Self.opError(from: out, name: "重命名")
    }

    /// 从批次输出判断操作是否失败（sftp 出错会打印 Couldn't/refused/no such file 等）
    private static func opError(from out: String?, name: String) -> String? {
        guard let out else { return "\(name)失败（SFTP 进程无法启动）" }
        let lower = out.lowercased()
        let fail = lower.contains("couldn't") || lower.contains("refused")
            || lower.contains("no such file") || lower.contains("permission denied")
            || lower.contains("failure") || lower.contains("error") || lower.contains("denied")
        guard fail else { return nil }
        let tail = out.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
        let msg = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        return msg.isEmpty ? "\(name)失败" : "\(name)失败：\(msg)"
    }

    // MARK: - 进程

    /// 通过 ssh 远端执行一条命令（输出 base64 解包后管道给 sh）
    private func runSSH(_ script: String, timeout: TimeInterval) -> String? {
        let b64 = Data(script.utf8).base64EncodedString()
        var args = ["-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ConnectTimeout=5",
                    "-o", "NumberOfPasswordPrompts=1",
                    "-p", "\(port)",
                    "\(user)@\(host)",
                    "sh -c 'printf %s \(b64) | base64 -d | sh'"]
        let env = selfEnv()
        if password.isEmpty {
            args.insert(contentsOf: ["-o", "BatchMode=yes"], at: 1)
        }
        return run(executable: "/usr/bin/ssh", args: args, env: env, send: nil, timeout: timeout)
    }

    /// 运行 sftp 批次命令，返回合并输出；timeout<=0 表示不限时（大文件传输）
    private func invoke(commands: [String], timeout: TimeInterval) -> String? {
        var args = ["-q", "-b", "-",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ConnectTimeout=5",
                    "-o", "NumberOfPasswordPrompts=1",
                    "-P", "\(port)",
                    "\(user)@\(host)"]
        var env = selfEnv()
        if password.isEmpty {
            args.insert(contentsOf: ["-o", "BatchMode=yes"], at: 1)
        }
        let payload = commands.joined(separator: "\n") + "\nexit\n"
        return run(executable: "/usr/bin/sftp", args: args, env: env, send: Data(payload.utf8), timeout: timeout)
    }

    private func selfEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if password.isEmpty { return env }
        let askpass = AskpassHelper.ensureScript()
        env["SSH_ASKPASS"] = askpass
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        env["ML_ASKPW"] = password
        return env
    }

    /// 通用进程执行：可选写入 stdin，读取合并输出；timeout<=0 不限时
    private func run(executable: String, args: [String], env: [String: String],
                     send payload: Data?, timeout: TimeInterval) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
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
        if let payload {
            inPipe.fileHandleForWriting.write(payload)
            try? inPipe.fileHandleForWriting.close()
        }
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
        return String(data: data, encoding: .utf8)
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

    /// 解析 `ls -la` 输出：每行形如
    /// drwxr-xr-x 2 user group 64 Aug 31 10:00 name
    /// -rw-r--r-- 1 user group 1234 Aug 31  2025 old.txt
    static func parseListing(_ raw: String) -> [SftpEntry] {
        // 组: 1 类型 2 权限 3 链接 4 owner 5 group 6 大小 7 月 8 日 9 时间/年 10 名称
        let pattern = #"^([\-dbclps])([rwxst\-]{9})\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\S+\s+\S+\s+(.+)$"#
        var entries: [SftpEntry] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            let l = String(line)
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { break }
            guard let m = re.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) else { continue }
            let type = String(l[Range(m.range(at: 1), in: l)!])
            let perms = String(l[Range(m.range(at: 2), in: l)!])
            let size = Int64(l[Range(m.range(at: 3), in: l)!]) ?? 0
            let name = String(l[Range(m.range(at: 4), in: l)!])
            if name == "." || name == ".." { continue }
            entries.append(SftpEntry(name: name, isDirectory: type == "d", size: size, perms: perms))
        }
        return entries
    }
}
