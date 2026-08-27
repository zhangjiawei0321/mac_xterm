import Foundation
import Combine

/// 全局应用状态：会话树 + 打开的标签页 + 新建/编辑会话弹窗状态
@MainActor
final class AppModel: ObservableObject {

    // MARK: 持久化的会话树
    @Published var sessionRoot: [TreeNode] = []

    // MARK: 打开的标签页
    @Published var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?

    // MARK: UI 状态
    @Published var sidebarVisible = true
    /// 侧栏当前选中的节点 id（用于“新建会话放哪”）
    @Published var selectedNodeID: UUID?
    @Published var showNewSession = false
    @Published var newSessionKind: SessionKind = .ssh
    @Published var editingSession: SessionConfig?
    /// 新建/编辑会话默认放入的文件夹
    @Published var pendingParentID: UUID?

    private let sessionsFile = AppLocations.sessionsFile

    init() {
        loadSessions()
    }

    // MARK: - 会话树：加载 / 保存

    private func loadSessions() {
        guard let data = try? Data(contentsOf: sessionsFile) else { return }
        if let decoded = try? JSONDecoder().decode([TreeNode].self, from: data) {
            sessionRoot = decoded
        }
    }

    func saveSessions() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sessionRoot) {
            try? data.write(to: sessionsFile, options: .atomic)
        }
    }

    // MARK: - 会话树：增删改

    /// 在指定文件夹（nil=根级）下新建文件夹
    @discardableResult
    func addFolder(named name: String, parentID: UUID?) -> UUID {
        let folder = SessionFolder(name: name)
        insert(.folder(folder), atFolder: parentID)
        saveSessions()
        return folder.id
    }

    /// 在指定文件夹（nil=根级）下加入一条会话
    @discardableResult
    func addSession(_ config: SessionConfig, toFolder parentID: UUID?) -> UUID {
        insert(.session(config), atFolder: parentID)
        saveSessions()
        return config.id
    }

    /// 保存编辑：替换树中同 id 会话的内容
    func updateSession(_ config: SessionConfig) {
        _ = replaceSession(id: config.id, with: config, in: &sessionRoot)
        saveSessions()
    }

    func deleteNode(id: UUID) {
        remove(id: id, in: &sessionRoot)
        saveSessions()
    }

    func renameNode(id: UUID, to name: String) {
        _ = mutate(id: id, in: &sessionRoot) { node in
            switch node {
            case .folder(var f):
                f.name = name
                node = .folder(f)
            case .session(var s):
                s.name = name
                node = .session(s)
            }
        }
        saveSessions()
    }

    // MARK: - 树辅助

    private func insert(_ node: TreeNode, atFolder parentID: UUID?) {
        guard let parentID else {
            sessionRoot.append(node)
            return
        }
        _ = mutateFolder(parentID, in: &sessionRoot) { folder in
            folder.children.append(node)
        }
    }

    @discardableResult
    private func mutate(_ id: UUID, in nodes: inout [TreeNode], _ body: (inout TreeNode) -> Void) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id {
                body(&nodes[i])
                return true
            }
        }
        for i in nodes.indices {
            if case .folder(var f) = nodes[i] {
                if mutate(id, in: &f.children, body) {
                    nodes[i] = .folder(f)
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    private func mutateFolder(_ id: UUID, in nodes: inout [TreeNode], _ body: (inout SessionFolder) -> Void) -> Bool {
        for i in nodes.indices {
            if case .folder(var f) = nodes[i] {
                if f.id == id {
                    body(&f)
                    nodes[i] = .folder(f)
                    return true
                }
                if mutateFolder(id, in: &f.children, body) {
                    nodes[i] = .folder(f)
                    return true
                }
            }
        }
        return false
    }

    @discardableResult
    private func replaceSession(id: UUID, with config: SessionConfig, in nodes: inout [TreeNode]) -> Bool {
        for i in nodes.indices {
            switch nodes[i] {
            case .session(let s):
                if s.id == id {
                    nodes[i] = .session(config)
                    return true
                }
            case .folder(var f):
                if replaceSession(id: id, with: config, in: &f.children) {
                    nodes[i] = .folder(f)
                    return true
                }
            }
        }
        return false
    }

    private func remove(id: UUID, in nodes: inout [TreeNode]) {
        nodes.removeAll { $0.id == id }
        for i in nodes.indices {
            if case .folder(var f) = nodes[i] {
                remove(id: id, in: &f.children)
                nodes[i] = .folder(f)
            }
        }
    }

    /// 定位一个节点
    func findNode(id: UUID) -> TreeNode? {
        var walk = sessionRoot
        return findNodeIn(id: id, nodes: &walk)
    }

    private func findNodeIn(id: UUID, nodes: inout [TreeNode]) -> TreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if case .folder(let f) = node {
                var children = f.children
                if let found = findNodeIn(id: id, nodes: &children) { return found }
            }
        }
        return nil
    }

    /// 返回某节点所在文件夹 id（节点本身是文件夹则返回它自己；找不到返回 nil）
    func folderID(containing nodeID: UUID) -> UUID? {
        guard let node = findNode(id: nodeID) else { return nil }
        if node.isFolder { return nodeID }
        return parentFolderID(of: nodeID, in: sessionRoot)
    }

    private func parentFolderID(of id: UUID, in nodes: [TreeNode]) -> UUID? {
        for node in nodes {
            if case .folder(let f) = node {
                if f.children.contains(where: { $0.id == id }) { return f.id }
                if let found = parentFolderID(of: id, in: f.children) { return found }
            }
        }
        return nil
    }
}

// MARK: - 标签页操作

extension AppModel {

    /// 新建并打开一个标签页
    @discardableResult
    func openTab(kind: SessionKind, session: SessionConfig?, title: String) -> TerminalTab {
        let tab = TerminalTab(kind: kind, session: session, title: title)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab
    }

    /// 打开本地终端标签
    @discardableResult
    func openLocalTerminal() -> TerminalTab {
        let tab = openTab(kind: .local, session: nil, title: "本地终端")
        return tab
    }

    /// 按会话配置打开连接标签（同配置已打开则切换到它）
    @discardableResult
    func openSession(config: SessionConfig) -> TerminalTab {
        if let existing = tabs.first(where: { $0.session?.id == config.id }),
           existing.controller != nil {
            selectedTabID = existing.id
            return existing
        }
        return openTab(kind: config.kind, session: config, title: config.defaultTabTitle)
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[idx]
        tab.close()
        if selectedTabID == id {
            let next = tabs[idx + 1 < tabs.count ? idx + 1 : max(idx - 1, 0)]
            let nextID = tabs.count > 1 ? next.id : nil
            selectedTabID = nextID
        }
        tabs.remove(at: idx)
        if tabs.isEmpty { selectedTabID = nil }
    }

    /// 获取标签页对应的会话控制器（懒创建）
    func controller(for tab: TerminalTab) -> TermSessionController {
        if let c = tab.controller { return c }
        let c: TermSessionController
        switch tab.kind {
        case .ssh:
            c = SSHViewController(session: tab.session ?? SessionConfig(name: "SSH", kind: .ssh))
        case .serial:
            c = SerialViewController(session: tab.session ?? SessionConfig(name: "串口", kind: .serial))
        case .local:
            c = LocalShellViewController()
        }
        tab.attach(controller: c)
        return c
    }

    func selectedTab: TerminalTab? {
        tabs.first { $0.id == selectedTabID }
    }

    func terminateAll() {
        for tab in tabs { tab.close() }
        tabs.removeAll()
        selectedTabID = nil
    }

    // MARK: 新建会话 Sheet 的打开方式

    func showNewSessionSheet(kind: SessionKind, inFolder folderID: UUID?) {
        newSessionKind = kind
        pendingParentID = folderID
        editingSession = nil
        showNewSession = true
    }

    func showEditSessionSheet(_ config: SessionConfig, parentFolderID: UUID?) {
        editingSession = config
        pendingParentID = parentFolderID
        newSessionKind = config.kind
        showNewSession = true
    }
}
