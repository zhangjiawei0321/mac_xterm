import Foundation

/// 一条可执行宏：名称 + 要发给当前终端的命令文本（支持多行，\n 分隔）。
struct Macro: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    /// 多行命令文本；空行保留，末尾回车由运行时补齐
    var commands: String
    /// 多行命令逐行下发时，行与行之间的延迟（毫秒）。0 = 一次整体下发。
    var lineDelayMs: Int
    /// 创建时间
    var createdAt = Date()
    /// 最近一次从底部宏栏/管理里运行的时间
    var lastUsedAt: Date?
    /// 累计运行次数（用于按“使用频次”排序）
    var useCount = 0
    /// 所属分组 id；nil = 未分组
    var groupId: UUID?
    /// 软删除时间：非 nil 表示在“已删除（回收站）”里，可恢复
    var deletedAt: Date?

    init(name: String, commands: String, lineDelayMs: Int = 0, groupId: UUID? = nil) {
        self.name = name
        self.commands = commands
        self.lineDelayMs = lineDelayMs
        self.groupId = groupId
        self.createdAt = Date()
    }

    var isDeleted: Bool { deletedAt != nil }

    /// 管理列表里预览用：命令文本的首行
    var preview: String {
        commands.split(whereSeparator: \.isNewline).first.map(String.init).map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    // 自定义解码：兼容旧版本保存的 macros.json（缺少新字段时用默认值）
    private enum CodingKeys: String, CodingKey {
        case id, name, commands, lineDelayMs, createdAt, lastUsedAt, useCount, groupId, deletedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        commands = try c.decode(String.self, forKey: .commands)
        lineDelayMs = try c.decodeIfPresent(Int.self, forKey: .lineDelayMs) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        useCount = try c.decodeIfPresent(Int.self, forKey: .useCount) ?? 0
        groupId = try c.decodeIfPresent(UUID.self, forKey: .groupId)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(commands, forKey: .commands)
        try c.encode(lineDelayMs, forKey: .lineDelayMs)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(useCount, forKey: .useCount)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }
}

/// 宏分组
struct MacroGroup: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var createdAt = Date()

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }
}

/// 宏与分组的持久化容器
struct MacroStore: Codable, Equatable, Sendable {
    var groups: [MacroGroup]
    var macros: [Macro]

    init(groups: [MacroGroup] = [], macros: [Macro] = []) {
        self.groups = groups
        self.macros = macros
    }
}

/// 宏列表排序方式
enum MacroSort: String, Codable, CaseIterable, Identifiable {
    case manual      // 手动（保持添加/拖拽后的顺序）
    case name        // 按名称
    case createTime  // 按创建时间
    case recent      // 按最近使用
    case frequency   // 按使用频次

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .manual: return "手动"
        case .name: return "名称"
        case .createTime: return "创建时间"
        case .recent: return "最近使用"
        case .frequency: return "使用频次"
        }
    }
}

/// 宏栏停靠位置
enum MacroBarPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottom: return "底部"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
}
