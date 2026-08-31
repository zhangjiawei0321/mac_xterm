import SwiftUI

/// 底部远程监控面板：CPU / 内存 / 磁盘 / 负载 / 运行时长（仿 MobaXterm Remote Monitoring）
struct RemoteMonitorPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let msg = model.remoteMonitorMessage {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text(msg)
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
                Text("每 3 秒刷新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
        } else if let s = model.remoteStats {
            HStack(spacing: 18) {
                // 目标
                HStack(spacing: 5) {
                    Image(systemName: "desktopcomputer")
                        .foregroundColor(.accentColor)
                    Text(s.host.isEmpty ? "监控" : s.host)
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(minWidth: 130, alignment: .leading)

                metric("CPU", text: s.cpuText, pct: s.cpu.map { $0 / 100 })
                metric("内存", text: "\(s.memoryText) · \(s.memoryPercentText)", pct: s.memUsedPercent.map { $0 / 100 })

                // 磁盘（至多 3 个分区，显示最满的前几个）
                if !s.disks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("磁盘")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(s.disks.prefix(3), id: \.name) { d in
                            HStack(spacing: 4) {
                                Text(d.name)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .frame(width: 42, alignment: .leading)
                                bar(pct: d.usedPercent / 100, color: color(d.usedPercent), width: 60)
                            }
                        }
                    }
                }

                Text(s.loadText.isEmpty ? "" : "负载 \(s.loadText)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if !s.uptimeText.isEmpty {
                    Text(s.uptimeText)
                        .font(.system(size: 10))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                }

                Spacer()
                Text("每 3 秒刷新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在获取监控数据…")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    private func metric(_ title: String, text: String, pct: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
            }
            bar(pct: pct ?? 0, color: .accentColor, width: 110)
        }
        .frame(minWidth: 130, alignment: .leading)
    }

    private func bar(pct: Double, color: Color, width: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * pct)))
            }
        }
        .frame(width: width, height: 5)
    }

    private func color(_ pct: Double) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return .accentColor
    }
}
