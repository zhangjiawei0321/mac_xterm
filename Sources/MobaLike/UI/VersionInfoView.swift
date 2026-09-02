import SwiftUI
import AppKit

/// 「帮助 → 版本信息」：列出每个版本新增的特性与修复的问题
struct VersionInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("NblityTerm \(AppInfo.currentVersion) — 版本信息", systemImage: "info.circle")
                    .font(.title3.bold())
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(AppInfo.versionNotes) { note in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(note.version)  ·  \(note.date)")
                                .font(.headline)
                            ForEach(note.items, id: \.self) { item in
                                Text("・ \(item)")
                                    .font(.callout)
                                    .foregroundColor(.primary.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if note.id != AppInfo.versionNotes.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(14)
            }
            .frame(width: 540, height: 380)
        }
        .frame(width: 568)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 版本信息数据（内嵌，便于裸二进制运行时也能展示）
enum AppInfo {
    static let currentVersion: String = {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return v ?? "1.0.2"
    }()

    struct Note: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let items: [String]
    }

    static let versionNotes: [Note] = [
        Note(version: "1.0.2", date: "2025-09-02", items: [
            "新增「开始保存接下来的日志」（SecureCRT 风格）：从点击那一刻起把后续输出实时追加写入所选文件，可随时停止；标签页与窗口标题栏用红点提示记录中。",
            "「保存日志」改名为「保存当前日志…」，与「保存接下来的日志」区分开。",
            "顶部「帮助」菜单新增「版本信息…」，可在此查看每个版本的优化与修复。",
        ]),
        Note(version: "1.0.1", date: "2025-09-01", items: [
            "新增会话日志缓存上限：超过上限自动丢弃较早内容，并弹窗询问一次性保存全部 / 只保存最近一部分 / 继续丢弃。",
            "修复终端输入数字「每满 4 个字符才落屏」（IP 着色器缓冲所致），现逐键即时显示。",
            "修复缓存上限 / 端口 / 波特率 / 行间延迟输入框难输入与卡顿，改用原生输入框。",
            "可执行文件的绿色调浅调柔，减轻长时间观看的晃眼感。",
        ]),
        Note(version: "1.0.0", date: "2025-08-31", items: [
            "定版并更名为 NblityTerm（原 MobaLike）。",
            "底部发送输入栏（SecureCRT 风格）：多行输入、多窗口选择、终端序号。",
            "侧栏 SFTP 远端文件浏览器与本地文件浏览，文件可直接打开编辑并支持双向上传下载。",
            "远程监控面板（CPU / 网络速率 / 告警色）。",
            "宏、终端搜索、分屏、会话管理、日志导出等功能。",
        ]),
    ]
}
