import Foundation

/// 一条可执行宏：名称 + 要发给当前终端的命令文本（支持多行，\n 分隔）。
struct Macro: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// 多行命令文本；空行保留，末尾回车由运行时补齐
    var commands: String
    /// 多行命令逐行下发时，行与行之间的延迟（毫秒）。0 = 一次整体下发。
    /// 用于第一条命令执行完/设备就绪后再发第二条的场景。
    var lineDelayMs: Int

    init(name: String, commands: String, lineDelayMs: Int = 0) {
        self.name = name
        self.commands = commands
        self.lineDelayMs = lineDelayMs
    }

    /// 管理列表里预览用：命令文本的首行
    var preview: String {
        commands.split(whereSeparator: \.isNewline).first.map(String.init).map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // 自定义解码：兼容旧版本保存的 macros.json（没有 lineDelayMs 字段）
    private enum CodingKeys: String, CodingKey {
        case id, name, commands, lineDelayMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        commands = try c.decode(String.self, forKey: .commands)
        lineDelayMs = try c.decodeIfPresent(Int.self, forKey: .lineDelayMs) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(commands, forKey: .commands)
        try c.encode(lineDelayMs, forKey: .lineDelayMs)
    }
}
