import SwiftUI

/// 左侧会话管理栏（树形：文件夹 + 会话）
struct SidebarView: View {
    @EnvironmentObject var model: AppModel

    // 重命名/新建文件夹弹窗状态
    @State private var renameNodeID: UUID?
    @State private var renameText = ""
    @State private var showingRename = false
    @State private var newFolderParentID: UUID?
    @State private var showingNewFolder = false
    @State private var newFolderText = "新建文件夹"

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
                    .foregroundColor(.tertiary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .alert("重命名", isPresented: $showingRename) {
            TextField("名称", text: $renameText)
            Button("确定") {
                if let id = renameNodeID {
                    model.renameNode(id: id, to: renameText)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("新建文件夹", isPresented: $showingNewFolder) {
            TextField("文件夹名称", text: $newFolderText)
            Button("创建") {
                model.addFolder(named: newFolderText, parentID: newFolderParentID)
            }
            Button("取消", role: .cancel) {}
        }
    }

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
        newFolderParentID = model.folderID(containing: model.selectedNodeID)
        newFolderText = "新建文件夹"
        showingNewFolder = true
    }

    @ViewBuilder
    private func contextMenu(for node: TreeNode) -> some View {
        if let session = node.session {
            Button("打开") { model.openSession(config: session) }
            Button("编辑…") {
                model.showEditSessionSheet(session, parentFolderID: model.folderID(containing: node.id))
            }
            Divider()
            Button("重命名…") {
                renameNodeID = node.id
                renameText = node.name
                showingRename = true
            }
            Button("删除", role: .destructive) { model.deleteNode(id: node.id) }
        } else {
            Button("新建 SSH 会话…") { model.showNewSessionSheet(kind: .ssh, inFolder: node.id) }
            Button("新建串口会话…") { model.showNewSessionSheet(kind: .serial, inFolder: node.id) }
            Button("新建文件夹…") {
                newFolderParentID = node.id
                newFolderText = "新建文件夹"
                showingNewFolder = true
            }
            Divider()
            Button("重命名…") {
                renameNodeID = node.id
                renameText = node.name
                showingRename = true
            }
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
