import Foundation
import Combine
import AppKit

extension Notification.Name {
    /// 终端外观（背景色等）设置变更
    static let terminalAppearanceChanged = Notification.Name("MobaLike.terminalAppearanceChanged")
}

/// 会话相关的提示弹窗类型（一次只弹一个）
enum SessionPrompt: Identifiable {
    case username(SessionConfig)      // 未填用户名，连接前请手动输入
    case savePassword(SessionConfig)  // 登录成功，询问是否保存密码
    case retryPassword(SessionConfig) // 自动登录失败，重输密码

    var id: Int {
        switch self {
        case .username: return 1
        case .savePassword: return 2
        case .retryPassword: return 3
        }
    }

    var sessionID: UUID {
        switch self {
        case .username(let c), .savePassword(let c), .retryPassword(let c): return c.id
        }
    }
}

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

    // MARK: 会话提示弹窗（用户名缺失 / 保存密码 / 重输密码）
    @Published var prompt: SessionPrompt?

    // MARK: 终端搜索面板
    @Published var searchPanelVisible = false
    @Published var searchQuery = ""
    @Published var searchHits: [TerminalSearchHit] = []
    /// 是否已执行过至少一次搜索（用于区分“无匹配”与“未搜索”）
    @Published var recentlySearched = false

    // MARK: 侧栏宽度（默认自适应最长名字，可拖动；持久化）
    @Published var sidebarWidth: CGFloat = 158 {
        didSet { UserDefaults.standard.set(sidebarWidth, forKey: "sidebarWidth") }
    }

    private let sessionsFile = AppLocations.sessionsFile
    private var appearanceObserver: NSObjectProtocol?

    /// 保存日志是否带时间戳（设置页开关）
    var logTimestamped: Bool {
        get { UserDefaults.standard.bool(forKey: "logTimestamped") }
        set { UserDefaults.standard.set(newValue, forKey: "logTimestamped") }
    }

    init() {
        loadSessions()
        if UserDefaults.standard.object(forKey: "sidebarWidth") != nil {
            sidebarWidth = CGFloat(UserDefaults.standard.float(forKey: "sidebarWidth"))
        } else {
            fitSidebarWidth()
        }
        // 设置中修改终端外观后，实时应用到所有已打开会话
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearanceToAll()
        }
    }

    func applyAppearanceToAll() {
        for tab in tabs {
            tab.controller?.applyAppearance()
        }
    }

    // MARK: - 会话树：加载 / 保存

    private func loadSessions() {
        guard let data = try? Data(contentsOf: sessionsFile) else { return }
        if var decoded = try? JSONDecoder().decode([TreeNode].self, from: data) {
            // 回填历史会话名：SSH 若名字 == 主机名且已有用户名，则补成 主机:(用户名)
            var changed = false
            normalizeNames(&decoded, changed: &changed)
            if changed {
                sessionRoot = decoded
                saveSessions()
            } else {
                sessionRoot = decoded
            }
        }
    }

    private func normalizeNames(_ nodes: inout [TreeNode], changed: inout Bool) {
        for i in nodes.indices {
            switch nodes[i] {
            case .session(var s):
                if s.kind == .ssh && !s.username.isEmpty && s.name == s.host {
                    s.name = "\(s.host):(\(s.username))"
                    nodes[i] = .session(s)
                    changed = true
                }
            case .folder(var f):
                normalizeNames(&f.children, changed: &changed)
                nodes[i] = .folder(f)
            }
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
        _ = mutate(id, in: &sessionRoot) { node in
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

    /// 返回某节点所在文件夹 id（节点本身是文件夹则返回它自己；找不到或传 nil 返回 nil）
    func folderID(containing nodeID: UUID?) -> UUID? {
        guard let nodeID else { return nil }
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

    /// 按会话配置打开连接标签：
    /// - 串口：同一会话只保留一个实例（已打开则切到它）
    /// - SSH/本地：每次点击都新开一个标签（与 MobaXterm 行为一致）
    @discardableResult
    func openSession(config: SessionConfig) -> TerminalTab {
        if config.kind == .serial,
           let existing = tabs.first(where: { $0.kind == .serial && $0.session?.id == config.id }) {
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
            let cfg = tab.session ?? SessionConfig(name: "SSH", kind: .ssh)
            let vc = SSHViewController(session: cfg)
            vc.onNeedUsername = { [weak self] _ in
                self?.presentPrompt(.username(cfg))
            }
            vc.onOfferSavePassword = { [weak self] _ in
                self?.presentPrompt(.savePassword(cfg))
            }
            vc.onAuthFailed = { [weak self] _ in
                self?.presentPrompt(.retryPassword(cfg))
            }
            vc.onReconnectRequested = { [weak self] controller in
                self?.controllerRequestedReconnect(controller)
            }
            c = vc
        case .serial:
            let vc = SerialViewController(session: tab.session ?? SessionConfig(name: "串口", kind: .serial))
            vc.onReconnectRequested = { [weak self] controller in
                self?.controllerRequestedReconnect(controller)
            }
            c = vc
        case .local:
            let vc = LocalShellViewController()
            vc.onReconnectRequested = { [weak self] controller in
                self?.controllerRequestedReconnect(controller)
            }
            c = vc
        }
        tab.attach(controller: c)
        return c
    }

    /// 会话断开后用户按 R：用当前配置原地重建该标签（SSH/串口/本地均可）
    func controllerRequestedReconnect(_ controller: TermSessionController) {
        guard let tab = tabs.first(where: { $0.controller === controller }) else { return }
        guard let cfg = tab.session else { return }   // 本地终端无配置，也支持重建
        tab.reconnect(with: cfg)
        selectedTabID = tab.id
        focusSelectedTerminal()
    }

    // MARK: 会话提示弹窗（用户名 / 保存密码 / 重输密码）

    func presentPrompt(_ p: SessionPrompt) {
        guard prompt == nil else { return }   // 已有一个弹窗时不叠加
        prompt = p
    }

    /// 用户名已填写：更新会话并重连（原先未启动）
    func resolveUsername(_ name: String, cancelled: Bool, for config: SessionConfig) {
        guard prompt?.sessionID == config.id else { return }
        prompt = nil
        if cancelled {
            if let tab = tabs.first(where: { $0.session?.id == config.id }) {
                closeTab(id: tab.id)
            }
            return
        }
        var updated = config
        updated.username = name
        // 名称仍是「主机」这种自动风格时，随用户名补全为 主机:(用户名)
        if updated.name == updated.host || updated.name.isEmpty {
            updated.name = updated.host.isEmpty ? name : "\(updated.host):(\(name))"
        }
        updateSession(updated)
        if let tab = tabs.first(where: { $0.session?.id == config.id }) {
            tab.reconnect(with: updated)
            selectedTabID = tab.id
            focusSelectedTerminal()
        }
    }

    /// 保存密码（登录成功后询问）：只更新存档，不打断当前连接
    func resolveSavePassword(_ password: String, cancelled: Bool, for config: SessionConfig) {
        guard prompt?.sessionID == config.id else { return }
        prompt = nil
        guard !cancelled, !password.isEmpty else { return }
        var updated = config
        updated.password = password
        updateSession(updated)
    }

    /// 重输密码：更新会话并用新密码重连
    func resolveRetryPassword(_ password: String, cancelled: Bool, for config: SessionConfig) {
        guard prompt?.sessionID == config.id else { return }
        prompt = nil
        guard !cancelled else { return }
        var updated = config
        updated.password = password
        updateSession(updated)
        if let tab = tabs.first(where: { $0.session?.id == config.id }) {
            tab.reconnect(with: updated)
            selectedTabID = tab.id
            focusSelectedTerminal()
        }
    }

    // MARK: 会话菜单动作（粘贴 / 清除日志 / 保存日志）

    func toggleSearchPanel() {
        searchPanelVisible.toggle()
        if searchPanelVisible {
            performSearch()
        } else {
            recentlySearched = false
            searchHits = []
        }
    }

    func performSearch() {
        searchHits = selectedTab?.controller?.searchLineHits(searchQuery) ?? []
    }

    func jumpToSearchHit(_ hit: TerminalSearchHit) {
        guard let controller = selectedTab?.controller else { return }
        // 点击时重新搜索，用最新行号跳转（避免列表构建后新输出导致行漂移）
        let fresh = controller.searchLineHits(searchQuery)
        if !fresh.isEmpty {
            searchHits = fresh
        }
        if fresh.indices.contains(hit.id) {
            controller.jumpToSearchLine(searchQuery, hitIndex: hit.id, row: fresh[hit.id].row)
        } else {
            controller.jumpToSearchLine(searchQuery, hitIndex: hit.id, row: hit.row)
        }
        // 搜索面板还开着时不抢搜索框焦点；关闭了再聚焦终端
        if !searchPanelVisible {
            focusSelectedTerminal()
        }
    }

    func copySelectedTerminalSelection() {
        selectedTab?.controller?.copySelection()
    }

    func copySelectedTerminalAll() {
        copyAll(of: selectedTab)
    }

    func copyAll(of tab: TerminalTab? = nil) {
        (tab ?? selectedTab)?.controller?.copyAll()
    }

    func pasteInto(_ tab: TerminalTab? = nil) {
        guard let c = (tab ?? selectedTab)?.controller,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else { return }
        c.sendInput(text)
    }

    func clearLog(_ tab: TerminalTab? = nil) {
        (tab ?? selectedTab)?.controller?.clearLog()
    }

    func saveLog(_ tab: TerminalTab? = nil) {
        guard let c = (tab ?? selectedTab)?.controller,
              let data = c.exportLogData(timestamped: logTimestamped) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = c.logDefaultName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    /// 聚焦当前标签页的终端（键盘可直接输入）
    func focusSelectedTerminal() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.selectedTab?.controller?.focusTerminal()
        }
    }

    // MARK: 侧栏宽度

    /// 按会话树最长名称估算默认宽度（图标/缩进/内边距另算）
    func fitSidebarWidth() {
        var maxTextWidth: CGFloat = 0
        walkNames(sessionRoot, depth: 0) { name, depth in
            let w = textWidth(name) + CGFloat(depth) * 14 + 44
            if w > maxTextWidth { maxTextWidth = w }
        }
        sidebarWidth = min(max(maxTextWidth, 120), 340)
    }

    private func textWidth(_ s: String) -> CGFloat {
        var count: CGFloat = 0
        for ch in s.unicodeScalars {
            count += ch.isASCII ? 7.4 : 14
        }
        return count
    }

    private func walkNames(_ nodes: [TreeNode], depth: Int, _ body: (String, Int) -> Void) {
        for node in nodes {
            body(node.name, depth)
            if let folder = node.folder {
                walkNames(folder.children, depth: depth + 1, body)
            }
        }
    }

    var selectedTab: TerminalTab? {
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
