import SwiftUI

/// 设置页：日志输出格式等
struct SettingsView: View {
    @AppStorage("logTimestamped") private var logTimestamped = false

    var body: some View {
        Form {
            Section("日志") {
                Toggle("保存日志时加入时间戳", isOn: $logTimestamped)
                Text("SSH/本地终端的日志按会话起止时间逐行近似标注；串口为接收时刻时间。")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
