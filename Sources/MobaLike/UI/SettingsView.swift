import SwiftUI

/// 设置页：日志输出格式等
struct SettingsView: View {
    @AppStorage("logTimestamped") private var logTimestamped = false

    var body: some View {
        Form {
            Section("日志") {
                Toggle("保存日志时加入时间戳", isOn: $logTimestamped)
                Text("开启后导出的日志每行带 [HH:mm:ss]。\n说明：终端缓冲区不记录每行精确时间，目前按会话起止时间逐行近似标注。如需逐字节精确时间戳，可后续改造为自建接收日志。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("会话栏") {
                Text("会话栏宽度可在主界面左侧分隔线上左右拖动调整（会自动记住）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 240)
        .navigationTitle("设置")
    }
}
