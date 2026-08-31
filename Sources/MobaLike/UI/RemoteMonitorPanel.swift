import SwiftUI

/// 底部远程监控面板（紧凑单行，高度约等于宏栏）：CPU / 内存 / 负载 / 运行时长
struct RemoteMonitorPanel: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30)
                .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let msg = model.remoteMonitorMessage {
            HStack(spacing: 7) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(msg)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("每 3 秒刷新")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
        } else if let s = model.remoteStats {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 10))
                        .foregroundColor(.accentColor)
                    Text(s.host.isEmpty ? "监控" : s.host)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(minWidth: 110, alignment: .leading)

                metric("CPU", text: s.cpuText, pct: s.cpu.map { $0 / 100 })
                metric("内存 \(s.memoryPercentText)", text: s.memoryText, pct: s.memUsedPercent.map { $0 / 100 })
                if !s.loadText.isEmpty {
                    Text("负载 \(s.loadText)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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
            .padding(.horizontal, 10)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在获取监控数据…")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
        }
    }

    private func metric(_ title: String, text: String, pct: Double?) -> some View {
        HStack(spacing: 6) {
            bar(pct: pct ?? 0, width: 46)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 118, alignment: .leading)
        .help(text)
    }

    private func bar(pct: Double, width: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * pct)))
            }
        }
        .frame(width: width, height: 5)
    }
}
