import Foundation
import Combine
import AppKit
import SwiftUI

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

    // MARK: 宏（宏栏 + 宏管理）
    @Published var macros: [Macro] = [] {
        didSet { saveMacros() }
    }
    @Published var macroGroups: [MacroGroup] = [] {
        didSet { saveMacros() }
    }
    /// 宏列表排序方式（持久化；@Published 使管理面板/宏栏即时刷新）
    @Published var macroSort: MacroSort = .manual {
        didSet { UserDefaults.standard.set(macroSort.rawValue, forKey: "macroSort") }
    }
    /// 宏栏停靠位置（持久化；@Published 使主界面即时重排）
    @Published var macroBarPosition: MacroBarPosition = .bottom {
        didSet { UserDefaults.standard.set(macroBarPosition.rawValue, forKey: "macroBarPosition") }
    }
    @Published var macroManagerPresented = false
    @Published var macroEditorPresented = false
    /// 正在编辑的宏；为 nil 表示新建
    @Published var editingMacro: Macro?
    /// 从宏栏分组菜单「新建宏到该分组」预设的默认分组（打开编辑器后即消费）
    @Published var defaultNewMacroGroup: UUID?

    // MARK: 分屏（多窗口）平铺
    /// 单屏 / 2格 / 4格
    @Published var paneLayout: PaneLayout = .single {
        didSet {
            hostEpoch += 1   // 布局切换自增：强制终端宿主重建，避免残留空白
            rebuildPanes()
            focusSelectedTerminal()   // 单屏/分屏都聚焦当前激活标签
        }
    }
    /// 宿主代次：布局每次切换 +1，用于 .id 强制重建终端容器
    @Published var hostEpoch = 0
    /// 当前接收输入的激活分屏格索引
    @Published var activePaneIndex = 0
    /// 每个分屏格显示的标签页 id（nil = 空，显示＋）
    @Published var paneTabIDs: [UUID?] = []
    /// 点空格的＋时记录要填充的分屏格
    @Published var pendingPaneIndex: Int?

    @Published var paneTwoSplit: CGFloat = 0.5 {
        didSet { UserDefaults.standard.set(Float(paneTwoSplit), forKey: "paneTwoSplit") }
    }
    @Published var paneFourRowSplit: CGFloat = 0.5 {
        didSet { UserDefaults.standard.set(Float(paneFourRowSplit), forKey: "paneFourRowSplit") }
    }
    @Published var paneFourColSplit: CGFloat = 0.5 {
        didSet { UserDefaults.standard.set(Float(paneFourColSplit), forKey: "paneFourColSplit") }
    }

    // MARK: 远程监控（仿 MobaXterm）
    @Published var remoteMonitorEnabled: Bool = UserDefaults.standard.bool(forKey: "remoteMonitorEnabled") {
        didSet {
            UserDefaults.standard.set(remoteMonitorEnabled, forKey: "remoteMonitorEnabled")
            if remoteMonitorEnabled {
                restartRemoteMonitor()
            } else {
                stopRemoteMonitor()
                remoteStats = nil
            }
        }
    }
    @Published var remoteStats: RemoteStats?
    /// 监控面板显示状态：nil=正常，否则为提示/错误信息
    @Published var remoteMonitorMessage: String?
    private var remoteMonitor: RemoteMonitor?
    private var monitorSink: AnyCancellable?

    // MARK: 侧栏宽度（默认自适应最长名字，可拖动；持久化）
    @Published var sidebarWidth: CGFloat = 158 {
        didSet { UserDefaults.standard.set(sidebarWidth, forKey: "sidebarWidth") }
    }

    private let sessionsFile = AppLocations.sessionsFile
    private var appearanceObserver: NSObjectProtocol?
    private var paneMouseMonitor: Any?

    /// 保存日志是否带时间戳（设置页开关）
    var logTimestamped: Bool {
        get { UserDefaults.standard.bool(forKey: "logTimestamped") }
        set { UserDefaults.standard.set(newValue, forKey: "logTimestamped") }
    }

    init() {
        loadSessions()
        loadMacros()
        if let raw = UserDefaults.standard.string(forKey: "macroBarPosition"),
           let p = MacroBarPosition(rawValue: raw) { macroBarPosition = p }
        if let raw = UserDefaults.standard.string(forKey: "macroSort"),
           let s = MacroSort(rawValue: raw) { macroSort = s }
        if UserDefaults.standard.object(forKey: "sidebarWidth") != nil {
            sidebarWidth = CGFloat(UserDefaults.standard.float(forKey: "sidebarWidth"))
        } else {
            fitSidebarWidth()
        }
        // 分屏分隔比例（持久化）
        if UserDefaults.standard.object(forKey: "paneTwoSplit") != nil {
            paneTwoSplit = CGFloat(UserDefaults.standard.float(forKey: "paneTwoSplit"))
        }
        if UserDefaults.standard.object(forKey: "paneFourRowSplit") != nil {
            paneFourRowSplit = CGFloat(UserDefaults.standard.float(forKey: "paneFourRowSplit"))
        }
        if UserDefaults.standard.object(forKey: "paneFourColSplit") != nil {
            paneFourColSplit = CGFloat(UserDefaults.standard.float(forKey: "paneFourColSplit"))
        }
        // 设置中修改终端外观后，实时应用到所有已打开会话
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .terminalAppearanceChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyAppearanceToAll()
        }
        // 分屏：点击任意终端后同步激活对应分屏格（高亮/输入目标跟随）
        paneMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.syncActivePaneFromFocus()
            }
            return event
        }
        // 远程监控：选中标签变化时自动切换监控目标
        monitorSink = $selectedTabID.sink { [weak self] _ in
            self?.restartRemoteMonitor()
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

    // MARK: - 宏：加载 / 保存

    private func loadMacros() {
        guard let data = try? Data(contentsOf: AppLocations.macrosFile) else { return }
        do {
            let store = try JSONDecoder().decode(MacroStore.self, from: data)
            macroGroups = store.groups
            macros = store.macros
        } catch {
            // 兼容旧版裸 [Macro] 格式
            if let old = try? JSONDecoder().decode([Macro].self, from: data) {
                macroGroups = []
                macros = old
            }
        }
    }

    private func saveMacros() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let store = MacroStore(groups: macroGroups, macros: macros)
        if let data = try? encoder.encode(store) {
            try? data.write(to: AppLocations.macrosFile, options: .atomic)
        }
    }

    // MARK: - 宏：排序展示

    /// 底部宏栏展示顺序（整列排序；不含回收站）
    var barMacros: [Macro] {
        let alive = macros.filter { !$0.isDeleted }
        return macroSort == .manual ? alive : alive.sorted(by: macroSortComparator)
    }

    /// 某分组内的宏（按当前排序方式排列）；gid 传 nil 表示「未分组」，不含回收站
    func macros(inGroup gid: UUID?) -> [Macro] {
        let members = macros.filter { $0.groupId == gid && !$0.isDeleted }
        return macroSort == .manual ? members : members.sorted(by: macroSortComparator)
    }

    /// 某分组内未删除宏的原始索引（用于拖拽/上下移动落回原数组）
    func rawIndices(inGroup gid: UUID?) -> [Int] {
        macros.indices.filter { macros[$0].groupId == gid && !macros[$0].isDeleted }
    }

    /// 回收站：已删除的宏（按删除时间倒序）
    var deletedMacros: [Macro] {
        macros.filter { $0.isDeleted }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var macroSortComparator: (Macro, Macro) -> Bool {
        switch macroSort {
        case .manual:
            return { _, _ in false }
        case .name:
            return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .createTime:
            return { $0.createdAt > $1.createdAt }
        case .recent:
            return { a, b in
                switch (a.lastUsedAt, b.lastUsedAt) {
                case let (x?, y?): return x > y
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.useCount > b.useCount
                }
            }
        case .frequency:
            return { a, b in
                a.useCount != b.useCount ? a.useCount > b.useCount : a.createdAt > b.createdAt
            }
        }
    }

    // MARK: - 宏：操作

    /// 打开宏编辑弹窗：editing 传 nil 表示新建
    func showMacroEditor(_ editing: Macro?) {
        editingMacro = editing
        macroEditorPresented = true
    }

    /// 是否已有同名（未删除）宏；`excluding` 用于编辑时排除自己
    func macroNameExists(_ name: String, excluding id: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return macros.contains {
            $0.name == trimmed && !$0.isDeleted && $0.id != id
        }
    }

    /// 保存宏（id 已存在则按 id 更新，否则追加）。重名时拒绝保存并返回 false。
    @discardableResult
    func saveMacro(id: UUID?, name: String, commands: String, lineDelayMs: Int, groupId: UUID?) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id {
            guard let idx = macros.firstIndex(where: { $0.id == id }) else { return false }
            guard !macroNameExists(trimmedName, excluding: id) else { return false }
            macros[idx].name = trimmedName
            macros[idx].commands = commands
            macros[idx].lineDelayMs = lineDelayMs
            macros[idx].groupId = groupId
            return true
        } else {
            let finalName = trimmedName.isEmpty ? defaultMacroName(prefix: "宏") : trimmedName
            guard !macroNameExists(finalName) else { return false }
            macros.append(Macro(name: finalName, commands: commands, lineDelayMs: lineDelayMs, groupId: groupId))
            return true
        }
    }

    /// 删除宏 → 软删除，移入「已删除（回收站）」可恢复
    func deleteMacro(id: UUID) {
        guard let idx = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[idx].deletedAt = Date()
    }

    /// 从回收站恢复
    func restoreMacro(id: UUID) {
        guard let idx = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[idx].deletedAt = nil
    }

    /// 永久删除单条（回收站内）
    func purgeMacro(id: UUID) {
        macros.removeAll { $0.id == id }
    }

    /// 清空回收站（永久删除所有已删除宏）
    func purgeDeletedMacros() {
        macros.removeAll { $0.isDeleted }
    }

    /// 把宏移动到指定分组（nil = 未分组）
    func moveMacroToGroup(id: UUID, groupId: UUID?) {
        guard let idx = macros.firstIndex(where: { $0.id == id }) else { return }
        macros[idx].groupId = groupId
    }

    /// 拖动换位：把 sourceID 放到 targetID 所在行之前（同组=重排；跨组=换入目标分组）
    func moveMacro(_ sourceID: UUID, before targetID: UUID) {
        guard let sIdx = macros.firstIndex(where: { $0.id == sourceID }),
              let tIdx = macros.firstIndex(where: { $0.id == targetID }),
              sIdx != tIdx else { return }
        let targetGroup = macros[tIdx].groupId
        var moving = macros.remove(at: sIdx)
        moving.groupId = targetGroup
        let newT = macros.firstIndex(where: { $0.id == targetID })!
        macros.insert(moving, at: newT)
    }

    /// 组内拖拽排序（仅手动排序模式使用）
    func moveMacro(fromOffsets offsets: IndexSet, toOffset dest: Int, inGroup gid: UUID?) {
        let members = rawIndices(inGroup: gid)
        guard !members.isEmpty else { return }
        var temp = members.map { macros[$0] }
        temp.move(fromOffsets: offsets, toOffset: dest)
        for (slot, macro) in temp.enumerated() {
            macros[members[slot]] = macro
        }
    }

    /// 组内上移/下移一位（显式排序按钮；跳过回收站项）
    func moveMacroUp(_ id: UUID) {
        guard let i = macros.firstIndex(where: { $0.id == id }) else { return }
        let gid = macros[i].groupId
        guard let prev = (0..<i).reversed().first(where: { macros[$0].groupId == gid && !macros[$0].isDeleted }) else { return }
        macros.swapAt(prev, i)
    }

    func moveMacroDown(_ id: UUID) {
        guard let i = macros.firstIndex(where: { $0.id == id }) else { return }
        let gid = macros[i].groupId
        guard let next = ((i + 1)..<macros.count).first(where: { macros[$0].groupId == gid && !macros[$0].isDeleted }) else { return }
        macros.swapAt(i, next)
    }

    // MARK: - 宏分组：操作

    /// 新建分组；返回其 id
    @discardableResult
    func addMacroGroup(named name: String) -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let g = MacroGroup(name: trimmed)
        macroGroups.append(g)
        return g.id
    }

    func renameMacroGroup(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = macroGroups.firstIndex(where: { $0.id == id }) else { return }
        macroGroups[idx].name = trimmed
    }

    /// 删除分组：其中宏移到「未分组」
    func deleteMacroGroup(id: UUID) {
        macroGroups.removeAll { $0.id == id }
        for i in macros.indices where macros[i].groupId == id {
            macros[i].groupId = nil
        }
    }

    private func defaultMacroName(prefix: String) -> String {
        let existing = Set(macros.filter { !$0.isDeleted }.map { $0.name })
        var i = 1
        while existing.contains("\(prefix) \(i)") { i += 1 }
        return "\(prefix) \(i)"
    }

    /// 运行宏：把命令文本发给当前活动标签页的终端（末尾自动补回车，确保最后一条命令立即执行）。
    /// 说明：shell 本身是逐行读取的——即使整段一起发，前台命令跑完前也不会执行下一条。
    /// 若配置了行间延迟，则逐行下发，每条之间等待指定毫秒（用于“等设备就绪再发下一条”）。
    func runMacro(_ macro: Macro) {
        var text = macro.commands
        guard !macro.isDeleted, !text.isEmpty, let controller = macroSendTarget else { return }
        // 记录使用时间/次数（用于按最近使用、使用频次排序）
        if let idx = macros.firstIndex(where: { $0.id == macro.id }) {
            macros[idx].lastUsedAt = Date()
            macros[idx].useCount += 1
        }
        if !text.hasSuffix("\n") { text += "\n" }

        let delay = max(0, macro.lineDelayMs)
        guard delay > 0 else {
            controller.sendInput(text)
            focusSelectedTerminal()
            return
        }

        // 去掉末尾因补回车产生的空串，逐行下发
        let lines = text.components(separatedBy: "\n").dropLast()
        Task {
            for line in lines {
                controller.sendInput(line + "\n")
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            focusSelectedTerminal()
        }
    }

    /// 宏的发送目标：当前选中的标签页（控制器懒创建）
    private var macroSendTarget: TermSessionController? {
        guard let tab = selectedTab else { return nil }
        return controller(for: tab)
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

    /// 新建并打开一个标签页；分屏模式下优先放入空分屏格，其次激活格/待填充格
    @discardableResult
    func openTab(kind: SessionKind, session: SessionConfig?, title: String) -> TerminalTab {
        let tab = TerminalTab(kind: kind, session: session, title: title)
        tabs.append(tab)
        selectedTabID = tab.id
        if paneLayout != .single {
            if let pp = pendingPaneIndex, paneTabIDs.indices.contains(pp) {
                paneTabIDs[pp] = tab.id
                activePaneIndex = pp
                pendingPaneIndex = nil
            } else if let empty = paneTabIDs.firstIndex(where: { $0 == nil }) {
                // 优先填进空分屏格（例如连续打开多个同 IP SSH）
                paneTabIDs[empty] = tab.id
                activePaneIndex = empty
            } else if paneTabIDs.indices.contains(activePaneIndex) {
                paneTabIDs[activePaneIndex] = tab.id   // 换下激活格原有内容
            } else {
                rebuildPanes()
            }
        }
        return tab
    }

    /// 选择标签页：分屏下同步激活对应的分屏格；若不在任何格内则显示到当前激活格
    func selectTab(_ id: UUID) {
        selectedTabID = id
        if paneLayout != .single {
            if let i = paneTabIDs.firstIndex(of: id) {
                activePaneIndex = i
            } else if paneTabIDs.indices.contains(activePaneIndex) {
                paneTabIDs[activePaneIndex] = id
            }
        }
        focusSelectedTerminal()
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
        // 分屏：清掉引用该标签的空格
        for i in paneTabIDs.indices where paneTabIDs[i] == id {
            paneTabIDs[i] = nil
        }
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
        case .telnet:
            let vc = TelnetViewController(session: tab.session ?? SessionConfig(name: "Telnet", kind: .telnet))
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
        restartRemoteMonitor()
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
        restartRemoteMonitor()
    }

    /// 保存密码（登录成功后询问）：只更新存档，不打断当前连接
    func resolveSavePassword(_ password: String, cancelled: Bool, for config: SessionConfig) {
        guard prompt?.sessionID == config.id else { return }
        prompt = nil
        guard !cancelled, !password.isEmpty else { return }
        var updated = config
        updated.password = password
        updateSession(updated)
        restartRemoteMonitor()
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
        restartRemoteMonitor()
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

    // MARK: - 分屏（多窗口）操作

    /// 分屏格数变化时重建各格内容：优先保留已有映射，空位用未展示的标签页填充
    func rebuildPanes() {
        let count = paneLayout.paneCount
        guard count > 1 else {
            paneTabIDs = []
            activePaneIndex = 0
            return
        }
        var ids: [UUID?] = Array(repeating: nil, count: count)
        var used = Set<UUID>()
        for i in 0..<min(ids.count, paneTabIDs.count) {
            if let id = paneTabIDs[i], tabs.contains(where: { $0.id == id }) {
                ids[i] = id
                used.insert(id)
            }
        }
        // 候选：选中的最优先，其余按标签顺序
        var rest = tabs.filter { !used.contains($0.id) }
        if let selID = selectedTabID, let idx = rest.firstIndex(where: { $0.id == selID }) {
            let sel = rest.remove(at: idx)
            rest.insert(sel, at: 0)
        }
        for i in ids.indices where ids[i] == nil {
            if !rest.isEmpty { ids[i] = rest.removeFirst().id }
        }
        paneTabIDs = ids
    }

    /// 激活某个分屏格：切换输入目标（选中对应标签并聚焦其终端）
    func setActivePane(_ index: Int) {
        guard paneLayout != .single, paneTabIDs.indices.contains(index) else { return }
        activePaneIndex = index
        if let id = paneTabIDs[index] {
            selectedTabID = id
        }
        focusSelectedTerminal()
    }

    // MARK: - 远程监控

    /// 当前监控目标：SSH 会话→远端主机；本地终端→本机；其它→不支持
    private var remoteMonitorTarget: RemoteMonitor.Target? {
        guard let tab = selectedTab else { return nil }
        switch tab.kind {
        case .ssh:
            guard let s = tab.session, !s.host.isEmpty else { return nil }
            let user = s.username.isEmpty ? NSUserName() : s.username
            return .ssh(host: s.host, port: Int(s.port), user: user, password: s.password)
        case .local:
            return .local
        case .serial, .telnet:
            return nil
        }
    }

    func restartRemoteMonitor() {
        stopRemoteMonitor()
        guard remoteMonitorEnabled else { return }
        guard let target = remoteMonitorTarget else {
            remoteStats = nil
            remoteMonitorMessage = "当前会话不支持远程监控：请选择 SSH 会话（监控远端）或本地终端（监控本机）。"
            return
        }
        remoteMonitorMessage = nil
        let mon = RemoteMonitor()
        remoteMonitor = mon
        mon.start(target: target, interval: 3) { [weak self] stats in
            self?.remoteStats = stats
        }
    }

    func stopRemoteMonitor() {
        remoteMonitor?.stop()
        remoteMonitor = nil
    }

    /// 把一个会话（标签）放到某个分屏格（从顶栏标题拖入/从其它格拖入）。
    /// 若该会话已在别的格显示，则两格内容对调。
    func assignPane(_ index: Int, tabID: UUID) {
        guard paneLayout != .single, paneTabIDs.indices.contains(index),
              tabs.contains(where: { $0.id == tabID }) else { return }
        if paneTabIDs[index] == tabID {
            activePaneIndex = index
            focusSelectedTerminal()
            return
        }
        if let j = paneTabIDs.firstIndex(of: tabID) {
            let mine = paneTabIDs[index]
            paneTabIDs[j] = mine
            paneTabIDs[index] = tabID
        } else {
            paneTabIDs[index] = tabID
        }
        activePaneIndex = index
        selectedTabID = tabID
        focusSelectedTerminal()
    }

    /// 点击终端后同步激活对应分屏格（把输入目标与高亮同步到被点击的格子）
    func syncActivePaneFromFocus() {
        guard paneLayout != .single, let fr = NSApp.keyWindow?.firstResponder as? NSView else { return }
        guard let tab = tabs.first(where: { cid in
            guard let view = cid.controller?.view else { return false }
            return view === fr || isDescendant(fr, of: view)
        }) else { return }
        if let i = paneTabIDs.firstIndex(of: tab.id) {
            activePaneIndex = i
            selectedTabID = tab.id
        }
    }

    private func isDescendant(_ maybe: NSView?, of root: NSView) -> Bool {
        var cur = maybe
        while let c = cur {
            if c === root { return true }
            cur = c.superview
        }
        return false
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
