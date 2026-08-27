import SwiftUI

/// 设置页：日志输出格式等
struct SettingsView: View {
    @AppStorage("displayTimestamp") private var displayTimestamp = false
    @AppStorage("logTimestamped") private var logTimestamped = false

    var body: some View {
        Form {
            Section("时间戳格式") {
                Toggle("显示会话日志时加入时间戳", isOn: $displayTimestamp)
                Toggle("保存日志时加入时间戳", isOn: $logTimestamped)
                Text("时间戳格式：yyyy-MM-dd HH:mm:ss.SSS\n「显示」为逐行实时前缀（当前串口会话生效）；「保存」为导出时按会话起止时间近似标注。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("会话栏") {
                Text("会话栏宽度可在主界面左侧分隔线上左右拖动调整（会自动记住）。右键会话可重命名/删除/新建，悬停可查看会话信息。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 280)
        .navigationTitle("设置")
    }
}
