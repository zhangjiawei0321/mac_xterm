import SwiftUI

/// 左侧会话管理栏（树形：文件夹 + 会话）
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    private enum TextAlertKind: Equatable {
        case rename(UUID)
        case newFolder(UUID?)
    }

    @State private var alertKind: TextAlertKind?
    @State private var alertText = ""

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
                List(selection: $model.selectedNodeID) {
                    OutlineGroup(model.sessionRoot, children: \.children) { node in
                        SidebarRowView(node: node)
                            .contextMenu { contextMenu(for: node) }
                            .onTapGesture(count: 2) { open(node: node) }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack {
                Spacer()
                Text("双击打开会话")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .alert(alertTitle, isPresented: alertVisible) {
            TextField(alertPlaceholder, text: $alertText)
            Button("确定") { commitAlert() }
            Button("取消", role: .cancel) {}
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

    private func open(node: TreeNode) {
        if let session = node.session {
            model.openSession(config: session)
        }
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

struct SidebarRowView: View {
    let node: TreeNode

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.iconName)
                .foregroundColor(node.isFolder ? .secondary : .accentColor)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }
}
