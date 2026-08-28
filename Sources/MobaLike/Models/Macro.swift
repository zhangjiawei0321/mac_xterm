import Foundation

/// 一条可执行宏：名称 + 要发给当前终端的命令文本（支持多行，\n 分隔）。
struct Macro: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// 多行命令文本；空行保留，末尾回车由运行时补齐
    var commands: String

    init(name: String, commands: String) {
        self.name = name
        self.commands = commands
    }

    /// 管理列表里预览用：命令文本的首行
    var preview: String {
        commands.split(whereSeparator: \.isNewline).first.map(String.init).map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
}
