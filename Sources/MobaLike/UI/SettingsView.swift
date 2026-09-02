import SwiftUI

/// 设置页：终端外观、日志输出格式、宏栏等
struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("displayTimestamp") private var displayTimestamp = false
    @AppStorage("logTimestamped") private var logTimestamped = false
    @State private var bgKey: String = UserDefaults.standard.string(forKey: "terminalBackground") ?? "default"
    @State private var logCacheText = ""

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

            Section("日志") {
                HStack(spacing: 8) {
                    Text("缓存上限")
                        .foregroundColor(.secondary)
                    NativeDigitField(text: $logCacheText) { commitLogCache() }
                        .frame(width: 70)
                    Stepper("", value: Binding(
                        get: { model.logCacheMB },
                        set: { model.logCacheMB = $0; logCacheText = String($0) }
                    ), in: 0...4096, step: 5)
                    .labelsHidden()
                    Text("MB")
                        .foregroundColor(.secondary)
                }
                Text("此上限只作用于「保存之前的日志」：超过后较早内容被丢弃，并弹窗询问保存全部 / 只保存最近一部分 / 继续丢弃。设为 0 表示不限。它不影响屏幕显示（显示不限量），也不限制「保存接下来的日志」（实时记录会完整写入文件，与上限无关）。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("宏") {
                Picker("宏栏位置", selection: $model.macroBarPosition) {
                    ForEach(MacroBarPosition.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Text("底部为横向条，左/右侧为纵向面板。切换即时生效。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("会话栏") {
                Text("会话栏宽度可在主界面左侧分隔线上左右拖动调整（会自动记住）。右键会话可重命名/删除/新建，悬停可查看会话信息。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 440)
        .navigationTitle("设置")
        .onAppear { logCacheText = String(model.logCacheMB) }
    }

    /// 缓存上限提交：只在回车 / 失焦时写出（避免逐键触发 UserDefaults 写入导致卡顿）
    private func commitLogCache() {
        model.logCacheMB = Int(logCacheText) ?? 0
    }
}
