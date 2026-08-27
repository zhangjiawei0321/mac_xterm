import Foundation

/// 会话树节点：既可以是一整个文件夹，也可以是一条会话
indirect enum TreeNode: Identifiable, Codable, Equatable, Sendable {
    case folder(SessionFolder)
    case session(SessionConfig)

    var id: UUID {
        switch self {
        case .folder(let f): return f.id
        case .session(let s): return s.id
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var name: String {
        switch self {
        case .folder(let f): return f.name
        case .session(let s): return s.name
        }
    }

    var session: SessionConfig? {
        if case .session(let s) = self { return s }
        return nil
    }

    var folder: SessionFolder? {
        if case .folder(let f) = self { return f }
        return nil
    }

    /// OutlineGroup 需要：文件夹有 children，会话没有
    var children: [TreeNode]? {
        if case .folder(let f) = self { return f.children }
        return nil
    }

    /// 图标
    var iconName: String {
        switch self {
        case .folder: return "folder"
        case .session(let s): return s.kind.iconName
        }
    }
}

/// 文件夹节点
struct SessionFolder: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var name: String
    var children: [TreeNode] = []
}
