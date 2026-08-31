import Foundation

/// 远程监控引擎：定时对目标（SSH 主机 / 本地机器）执行探针脚本并解析出指标。
/// 探针脚本用 base64 传输后在目标端 `base64 -d | sh` 执行，避免多层引号转义。
final class RemoteMonitor {
    enum Target {
        case local
        case ssh(host: String, port: Int, user: String, password: String)
    }

    private let queue = DispatchQueue(label: "mobalike.remote-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = 0
    private var busy = false
    /// 上一帧网络累计字节 + 时间（用于算实时速率）
    private var lastNetSample: (rx: Double, tx: Double, t: TimeInterval)?
    private let netLock = NSLock()

    deinit { stop() }

    /// 开始定时监控。interval 秒一帧；每次成功解析后通过 onUpdate（主线程）回调。
    func start(target: Target, interval: TimeInterval, onUpdate: @escaping (RemoteStats) -> Void) {
        stop()
        generation += 1
        netLock.lock(); lastNetSample = nil; netLock.unlock()
        let gen = generation
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.15, repeating: interval, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in
            self?.tick(target: target, gen: gen, onUpdate: onUpdate)
        }
        timer = t
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
        generation += 1
        busy = false
    }

    // MARK: - 轮询一帧

    private func tick(target: Target, gen: Int, onUpdate: @escaping (RemoteStats) -> Void) {
        guard !busy else { return }          // 上一帧未结束则跳过本次
        busy = true
        defer { busy = false }

        let b64 = Data(Self.probeScript.utf8).base64EncodedString()
        if let output = runProbe(target: target, base64: b64), gen == generation {
            if var stats = Self.parse(output) {
                computeNetRates(&stats)
                if gen == generation {
                    let snapshot = stats
                    DispatchQueue.main.async { onUpdate(snapshot) }
                }
            }
        }
    }

    /// 用前后两帧累计网络字节算实时速率
    private func computeNetRates(_ stats: inout RemoteStats) {
        guard let rx = stats.netRxBytes, let tx = stats.netTxBytes else { return }
        let now = Date().timeIntervalSince1970
        netLock.lock()
        let last = lastNetSample
        lastNetSample = (rx, tx, now)
        netLock.unlock()
        guard let last, now > last.t, rx >= last.rx, tx >= last.tx else {
            stats.netDownPerSec = 0
            stats.netUpPerSec = 0
            return
        }
        let dt = now - last.t
        stats.netDownPerSec = (rx - last.rx) / dt
        stats.netUpPerSec = (tx - last.tx) / dt
    }

    /// 执行探针并返回原始输出（组合 stdout+stderr；失败返回 nil）
    private func runProbe(target: Target, base64: String) -> String? {
        let p = Process()
        var args: [String] = []
        switch target {
        case .local:
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            args = ["-c", "printf %s '\(base64)' | base64 -d | sh"]
        case .ssh(let host, let port, let user, let password):
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            args = ["-p", "\(port)",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-o", "ConnectTimeout=5",
                    "-o", "NumberOfPasswordPrompts=1",
                    "\(user)@\(host)",
                    "printf %s \(base64) | base64 -d | sh"]
            var env = ProcessInfo.processInfo.environment
            if password.isEmpty {
                args.insert("-o", at: 1); args.insert("BatchMode=yes", at: 2)  // 仅密钥，避免挂起等密码
            } else {
                let askpass = AskpassHelper.ensureScript()
                env["SSH_ASKPASS"] = askpass
                env["SSH_ASKPASS_REQUIRE"] = "force"
                env["DISPLAY"] = env["DISPLAY"] ?? ":0"
                env["ML_ASKPW"] = password
            }
            p.environment = env
        }
        p.arguments = args

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return nil
        }
        // 看门狗：最多执行 8s，超时强杀
        let watchdog = DispatchWorkItem { [weak p] in if let p, p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - 解析

    static func parse(_ raw: String) -> RemoteStats? {
        var stats = RemoteStats()
        var gotCPU = false
        for line in raw.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0]
            let value = parts[1]
            switch key {
            case "MZ_CPU":
                // 兼容 macOS `12.5%` 带 %（Linux 为纯数字）
                let cleaned = value.filter { $0.isNumber || $0 == "." }
                if let v = Double(cleaned) { stats.cpu = v; gotCPU = true }
            case "MZ_MT":
                stats.memTotalBytes = Double(value)
            case "MZ_MU":
                stats.memUsedBytes = Double(value)
            case "MZ_LOAD":
                stats.loadText = String(value)
            case "MZ_UP":
                stats.uptimeText = String(value)
            case "MZ_HOST":
                stats.host = String(value)
            case "MZ_NET_RX":
                stats.netRxBytes = Double(value)
            case "MZ_NET_TX":
                stats.netTxBytes = Double(value)
            case "MZ_DISK":
                let seg = value.split(separator: "|", maxSplits: 1)
                if seg.count == 2,
                   let pct = Double(seg[1].dropLast()) {   // 去掉尾部 %
                    stats.disks.append((String(seg[0]), pct))
                }
            default:
                break
            }
        }
        guard gotCPU || stats.memTotalBytes != nil || !stats.disks.isEmpty else { return nil }
        return stats
    }

    // MARK: - 探针脚本（Linux 优先，macOS 兜底）

    static let probeScript = """
    U=$(uptime)
    LC=$(top -bn1 2>/dev/null | awk '/%Cpu/{print 100-$8; exit}')
    [ -z "$LC" ] && LC=$(top -l 1 2>/dev/null | awk '/CPU usage/{print $3}')
    MT=$(free -b 2>/dev/null | awk '/Mem:/{print $2}')
    MU=$(free -b 2>/dev/null | awk '/Mem:/{print $3}')
    [ -z "$MT" ] && MT=$(sysctl -n hw.memsize 2>/dev/null)
    [ -z "$MU" ] && MU=$(vm_stat 2>/dev/null | awk '/Pages active/{a=$3} /Pages wired/{w=$4} END{if(a!="")print (a+w)*4096}')
    LD=$(printf '%s' "$U" | sed -E 's/.*load average[s]*: *//')
    UP=$(printf '%s' "$U" | sed 's/^ *//; s/  */ /g')
    HN=$(hostname 2>/dev/null)
    echo "MZ_CPU=$LC"
    echo "MZ_MT=$MT"
    echo "MZ_MU=$MU"
    echo "MZ_LOAD=$LD"
    echo "MZ_UP=$UP"
    echo "MZ_HOST=$HN"
    { df -h -x tmpfs -x devtmpfs 2>/dev/null | awk 'NR>1 && $1 !~ /^(tmpfs|udev|loop|snap|overlay)/ {print "MZ_DISK="$6"|"$5}'; df -h 2>/dev/null | awk 'NR>1 && $1 !~ /^(map|devfs|tmpfs)/ {print "MZ_DISK="$9"|"$5}'; } | sort -u | head -8
    # 网络累计字节（Linux /proc/net/dev，macOS netstat -ib）
    NRX=$(awk 'NR>2 {n=$1; sub(":","",n); if (n!="lo") {rx+=$2; tx+=$10}} END{print rx" "tx}' /proc/net/dev 2>/dev/null)
    [ -z "$NRX" ] && NRX=$(netstat -ib 2>/dev/null | awk '$3 ~ /<Link#/ {n=$1; if (n !~ /^(lo0|utun|awdl|llw|gif|stf|ap|fw0|bridge)/) {r+=$7; t+=$10}} END{print r" "t}')
    echo "MZ_NET_RX=$(printf '%s' "$NRX" | awk '{print $1}')"
    echo "MZ_NET_TX=$(printf '%s' "$NRX" | awk '{print $2}')"
    """
}
