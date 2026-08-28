import SwiftUI

/// 悬停会话信息卡（画在主窗口内、贴近悬停行；无独立窗口，不抢焦点/不影响点击）
struct HoverInfoCard: View {
    let session: SessionConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.name)
                .font(.caption.bold())
                .lineLimit(1)
                .truncationMode(.tail)
            ForEach(infoLines(session), id: \.self) { line in
                Text(line)
                    .font(.system(size: 11).monospaced())
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: Color.black.opacity(0.25), radius: 8, y: 2)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.35), lineWidth: 1))
        .frame(width: 250, alignment: .leading)
    }

    private func infoLines(_ s: SessionConfig) -> [String] {
        switch s.kind {
        case .ssh:
            return [
                "类型: SSH",
                "主机地址: \(s.host):\(s.port)",
                "用户名: \(s.username.isEmpty ? "(未填写)" : s.username)",
            ]
        case .serial:
            return [
                "类型: 串口 Serial",
                "设备: \(s.serial.device)",
                "波特率: \(s.serial.baudRate)",
                "数据位: \(s.serial.dataBits)  校验: \(s.serial.parity.displayName)",
                "停止位: \(s.serial.stopBits)  流控: \(s.serial.flowControl.displayName)",
            ]
        case .local:
            return ["类型: 本地终端"]
        }
    }
}
