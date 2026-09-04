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
        return v ?? "1.0.3"
    }()

    struct Note: Identifiable {
        let id = UUID()
        let version: String
        let date: String
        let items: [String]
    }

    static let versionNotes: [Note] = [
        Note(version: "1.0.3", date: "2025-09-03", items: [
            "修复日志缓存上限设 0（不限量）时「保存全部日志」为空的问题，0 现在真正不限量捕获。",
            "修复串口/Telnet 后台线程直接操作终端与日志记录导致的并发崩溃风险，输出统一走主线程。",
            "修复串口关闭与读取的 fd 竞争（关闭时等待读线程退出再关句柄）。",
            "修复宏「行间延迟」、日志「缓存上限」输入超大数字时的算术溢出崩溃，加上限钳制。",
            "修复远程监控在「仅密钥、未存密码」时失效（ssh 参数错位）。",
            "修复「显示时间戳」中途开关后时间戳错乱（漏加整行）。",
            "修复本地终端找不到 npx 等命令：改用登录 shell 启动（与 Terminal.app 一致），使 /etc/paths 与 ~/.zprofile 的 PATH 生效。",
        ]),
        Note(version: "1.0.2", date: "2025-09-02", items: [
            "新增「开始保存接下来的日志」（SecureCRT 风格）：从点击那一刻起把后续输出实时追加写入所选文件，写入前自动剥离 ANSI 颜色码/控制序列（文件为干净文本，与屏幕显示一致），可随时停止；标签页与窗口标题栏用红点提示记录中。",
            "「保存日志」改名为「保存当前日志…」，与「保存接下来的日志」区分开。",
            "日志缓存上限明确只作用于「保存之前的日志」：不影响屏幕显示（显示不限量），也不限制「保存接下来的日志」（实时记录完整写入文件）；录制过程中不再弹出上限询问，避免中断记录。",
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
