import SwiftUI

/// 左侧会话管理栏（自绘树形：文件夹 + 会话）
/// 用 Button 行实现「单击打开/展开 + 右键菜单 + 悬停提示」，规避 SwiftUI List/OutlineGroup
/// 上右键菜单不稳定、点击无反馈等问题。
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    private enum TextAlertKind: Equatable {
        case rename(UUID)
        case newFolder(UUID?)
    }

    @State private var alertKind: TextAlertKind?
    @State private var alertText = ""
    /// 展开的文件夹 id
    @State private var expanded: Set<UUID> = []
    /// 当前悬停的行（用于即时信息卡 + 悬停高亮）
    @State private var hoveredRowID: UUID?
    /// 信息卡延迟显示任务
    @State private var hoverTask: Task<Void, Never>?

    private struct Row: Identifiable {
        let id: UUID
        let node: TreeNode
        let depth: Int
    }

    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.secondary)
                Text("会话")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("新建 SSH 会话…") { model.showNewSessionSheet(kind: .ssh, inFolder: targetFolderForNew) }
                    Button("新建串口会话…") { model.showNewSessionSheet(kind: .serial, inFolder: targetFolderForNew) }
                    Divider()
                    Button("新建文件夹…") { prepareNewFolder() }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()

            if model.sessionRoot.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("还没有会话")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Button("点击这里新建…") {
                        model.showNewSessionSheet(kind: .ssh, inFolder: nil)
                    }
                    .buttonStyle(.link)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(flatten(model.sessionRoot, depth: 0)) { row in
                            rowView(row)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            // 底部：悬停会话信息条（替代 popover 弹窗，避免独立窗口抢焦点/点击）
            if let session = hoveredSession {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(compactSessionInfo(session))
                        .font(.system(size: 10).monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Text("单击打开 · 右键菜单 · 悬停查看")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 6)
            }
        }
        .onAppear {
            // 默认展开所有文件夹
            var ids = Set<UUID>()
            collectFolderIDs(model.sessionRoot, into: &ids)
            expanded = ids
        }
        .alert(alertTitle, isPresented: alertVisible) {
            TextField(alertPlaceholder, text: $alertText)
            Button("确定") { commitAlert() }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 树展开/扁平化

    private func flatten(_ nodes: [TreeNode], depth: Int) -> [Row] {
        var out: [Row] = []
        for node in nodes {
            out.append(Row(id: node.id, node: node, depth: depth))
            if case .folder(let f) = node, expanded.contains(f.id) {
                out.append(contentsOf: flatten(f.children, depth: depth + 1))
            }
        }
        return out
    }

    private func collectFolderIDs(_ nodes: [TreeNode], into ids: inout Set<UUID>) {
        for node in nodes {
            if case .folder(let f) = node {
                ids.insert(f.id)
                collectFolderIDs(f.children, into: &ids)
            }
        }
    }

    // MARK: - 行视图

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        switch row.node {
        case .folder(let f):
            Button {
                toggleExpand(f.id)
                model.selectedNodeID = f.id
            } label: {
                rowLabel(for: row)
            }
            .buttonStyle(.borderless)
            .contextMenu { contextMenu(for: row.node) }

        case .session(let s):
            Button {
                model.openSession(config: s)
            } label: {
                rowLabel(for: row)
            }
            .buttonStyle(.borderless)
            .contextMenu { contextMenu(for: row.node) }
        }
    }

    /// 当前悬停的会话（用于底部信息条）
    private var hoveredSession: SessionConfig? {
        guard let id = hoveredRowID else { return nil }
        return model.findNode(id: id)?.session
    }

    /// 底部信息条的紧凑描述
    private func compactSessionInfo(_ s: SessionConfig) -> String {
        switch s.kind {
        case .ssh:
            return "SSH · \(s.username.isEmpty ? "" : "\(s.username)@")\(s.host):\(s.port)"
        case .serial:
            return "Serial · \((s.serial.device as NSString).lastPathComponent) · \(s.serial.baudRate)"
        case .local:
            return "本地终端"
        }
    }

    private func rowLabel(for row: Row) -> some View {
        let isFolder = row.node.isFolder
        let isSelected = row.id == model.selectedNodeID
        let isHovered = hoveredRowID == row.id
        return HStack(spacing: 5) {
            if case .folder(let f) = row.node {
                Image(systemName: expanded.contains(f.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10)
            }
            Image(systemName: row.node.iconName)
                .font(.system(size: 12))
                .foregroundColor(isFolder ? .secondary : .accentColor)
                .frame(width: 16)
            Text(row.node.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .padding(.vertical, 6)
        .padding(.horizontal, 5)
        .frame(minHeight: 26)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.20)
                                 : (isHovered ? Color.accentColor.opacity(0.09) : Color.clear))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                // 延迟 0.3s 再更新信息条/高亮，避免瞬时划过闪烁
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled { hoveredRowID = row.id }
                }
            } else {
                hoveredRowID = nil
            }
        }
    }

    /// 悬停信息改为侧栏底部信息条显示（不再用独立窗口 popover，避免抢焦点/点击）
    private func toggleExpand(_ id: UUID) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    // MARK: - 弹窗驱动

    private var alertTitle: String {
        switch alertKind {
        case .rename: return "重命名"
        case .newFolder: return "新建文件夹"
        case nil: return ""
        }
    }

    private var alertPlaceholder: String {
        switch alertKind {
        case .rename: return "名称"
        case .newFolder: return "文件夹名称"
        case nil: return ""
        }
    }

    private var alertVisible: Binding<Bool> {
        Binding(
            get: { alertKind != nil },
            set: { if !$0 { alertKind = nil } }
        )
    }

    private func commitAlert() {
        switch alertKind {
        case .rename(let id):
            model.renameNode(id: id, to: alertText)
        case .newFolder(let parentID):
            model.addFolder(named: alertText, parentID: parentID)
        case nil:
            break
        }
        alertKind = nil
    }

    private func beginRename(_ id: UUID) {
        alertText = model.findNode(id: id)?.name ?? ""
        alertKind = .rename(id)
    }

    private func beginNewFolder(parentID: UUID?) {
        alertText = "新建文件夹"
        alertKind = .newFolder(parentID)
    }

    // MARK: - 其它动作

    /// 新建会话默认放在当前选中项所在文件夹
    private var targetFolderForNew: UUID? {
        model.folderID(containing: model.selectedNodeID)
    }

    private func prepareNewFolder() {
        beginNewFolder(parentID: model.folderID(containing: model.selectedNodeID))
    }

    @ViewBuilder
    private func contextMenu(for node: TreeNode) -> some View {
        if let session = node.session {
            Button("打开") { model.openSession(config: session) }
            Button("编辑…") {
                model.showEditSessionSheet(session, parentFolderID: model.folderID(containing: node.id))
            }
            Divider()
            Button("重命名…") { beginRename(node.id) }
            Button("删除", role: .destructive) { model.deleteNode(id: node.id) }
        } else {
            Button("新建 SSH 会话…") { model.showNewSessionSheet(kind: .ssh, inFolder: node.id) }
            Button("新建串口会话…") { model.showNewSessionSheet(kind: .serial, inFolder: node.id) }
            Button("新建文件夹…") { beginNewFolder(parentID: node.id) }
            Divider()
            Button("重命名…") { beginRename(node.id) }
            Button("删除", role: .destructive) { model.deleteNode(id: node.id) }
        }
    }
}
