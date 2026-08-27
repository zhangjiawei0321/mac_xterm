import SwiftUI

/// 设置页：终端外观、日志输出格式等
struct SettingsView: View {
    @AppStorage("displayTimestamp") private var displayTimestamp = false
    @AppStorage("logTimestamped") private var logTimestamped = false
    @State private var bgKey: String = UserDefaults.standard.string(forKey: "terminalBackground") ?? "default"

    var body: some View {
        Form {
            Section("终端外观") {
                Picker("背景颜色", selection: $bgKey) {
                    ForEach(TerminalAppearance.options, id: \.key) { preset in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(nsColor: preset.bg))
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
                            Text(preset.title)
                        }
                        .tag(preset.key)
                    }
                }
                .onChange(of: bgKey) { _, newKey in
                    UserDefaults.standard.set(newKey, forKey: "terminalBackground")
                    NotificationCenter.default.post(name: .terminalAppearanceChanged, object: nil)
                }
                Text("切换后对已打开的会话即时生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("时间戳格式") {
                Toggle("显示会话日志时加入时间戳", isOn: $displayTimestamp)
                Toggle("保存日志时加入时间戳", isOn: $logTimestamped)
                Text("时间戳格式：yyyy-MM-dd HH:mm:ss.SSS\n「显示」为逐行实时前缀（当前串口会话生效，SSH/本地需后续自建接收才支持）；「保存」为导出时按会话起止时间近似标注。")
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
        .frame(width: 460, height: 360)
        .navigationTitle("设置")
    }
}
