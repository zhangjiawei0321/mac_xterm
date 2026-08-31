import SwiftUI
import AppKit

/// 宏管理：分组（前置）+ 未分组 + 回收站；排序；编辑 / 删除(确认) / 运行 / 新建；
/// 支持把宏按钮拖动到别的行前（重排/换组）或拖到分组标题上（加入该组）。
struct MacroManagerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    // 编辑器在面板内嵌套弹出，避免与主窗口 sheet 叠放导致“点了没反应”
    @State private var editorPresented = false
    @State private var showGroupAlert = false
    @State private var groupName = ""
    @State private var renameTargetID: UUID?
    @State private var renameName = ""
    @State private var renamePresented = false
    @State private var confirmDelete: Macro?
    @State private var confirmPurgeAll = false

    private var isManual: Bool { model.macroSort == .manual }
    private var trash: [Macro] { model.deletedMacros }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 500)
        .sheet(isPresented: $editorPresented) {
            MacroEditorSheet()
                .environmentObject(model)
        }
        .newGroupAlert(binding: $showGroupAlert, name: $groupName) { model.addMacroGroup(named: $0) }
        .alert("重命名分组", isPresented: $renamePresented) {
            TextField("分组名称", text: $renameName)
            Button("确定") {
                if let id = renameTargetID { model.renameMacroGroup(id: id, to: renameName) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmDeleteAlert(macro: $confirmDelete, delete: { model.deleteMacro(id: $0) })
        .alert("清空回收站", isPresented: $confirmPurgeAll) {
            Button("永久清空", role: .destructive) { model.purgeDeletedMacros() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除回收站里所有宏，此操作不可恢复。")
        }
    }

    /// 在面板内打开宏编辑器（editing 传 nil 表示新建）
    private func openEditor(_ editing: Macro?) {
        model.editingMacro = editing
        model.defaultNewMacroGroup = nil
        editorPresented = true
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            Text("宏管理")
                .font(.title3.bold())
            Picker("", selection: Binding(
                get: { model.macroSort },
                set: { model.macroSort = $0 }
            )) {
                ForEach(MacroSort.allCases) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .help("排序方式：手动排序可拖动/用 ▲▼ 调整")

            Spacer()

            Menu {
                Button("新建宏…") { openEditor(nil) }
                Button("新建分组…") { groupName = ""; showGroupAlert = true }
            } label: {
                Label("新建", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .padding(14)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if model.macros.isEmpty && model.macroGroups.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "scope")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)
                Text("还没有宏，点击「新建」创建宏或分组")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                // 1) 分组（前置）
                ForEach(model.macroGroups) { g in
                    groupSection(gid: g.id, title: g.name)
                }
                // 2) 未分组
                if !model.macros(inGroup: nil).isEmpty {
                    groupSection(gid: nil, title: "未分组")
                }
                // 3) 回收站
                if !trash.isEmpty {
                    trashSection
                }
            }
            .listStyle(.inset)
        }
    }

    // MARK: - 分组 Section（含拖放目标 + 行内拖源）

    @ViewBuilder
    private func groupSection(gid: UUID?, title: String) -> some View {
        let rows = model.macros(inGroup: gid)
        Section {
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, macro in
                row(macro, idx: idx, count: rows.count, gid: gid)
                    .draggable(macro.id.uuidString)
                    .dropDestination(for: String.self) { items, _ in
                        handleDrop(items, targetGroup: gid, before: macro.id)
                    }
            }
        } header: {
            sectionHeader(gid: gid, title: title, count: rows.count)
                .dropDestination(for: String.self) { items, _ in
                    handleDrop(items, targetGroup: gid, before: nil)
                }
        }
    }

    private func sectionHeader(gid: UUID?, title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: gid == nil ? "tray" : "folder")
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text("(\(count))").foregroundColor(.secondary)
            Spacer()
            if let gid {
                Menu {
                    Button("重命名…") {
                        renameTargetID = gid
                        renameName = model.macroGroups.first(where: { $0.id == gid })?.name ?? ""
                        DispatchQueue.main.async { renamePresented = true }
                    }
                    Button("删除分组（宏移入未分组）", role: .destructive) {
                        model.deleteMacroGroup(id: gid)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - 宏行

    private func row(_ macro: Macro, idx: Int, count: Int, gid: UUID?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(macro.name)
                        .fontWeight(.medium)
                    if macro.useCount > 0 {
                        Text("已用 \(macro.useCount) 次")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if let last = macro.lastUsedAt {
                        Text(last.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if !macro.preview.isEmpty {
                    Text(macro.preview)
                        .font(.callout.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()

            if isManual {
                Button { model.moveMacroUp(macro.id) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless)
                    .disabled(findPrevInGroup(macro, gid: gid) == nil)
                    .help("上移")
                Button { model.moveMacroDown(macro.id) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(findNextInGroup(macro, gid: gid) == nil)
                    .help("下移")
            }

            Button { openEditor(macro) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑宏内容")

            Button { confirmDelete = macro } label: {
                Image(systemName: "trash").foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("删除（进回收站）")
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("运行") { model.runMacro(macro) }
            Button("编辑内容…") { openEditor(macro) }
            Menu("移动到分组") {
                Button("未分组") { model.moveMacroToGroup(id: macro.id, groupId: nil) }
                ForEach(model.macroGroups) { g in
                    Button(g.name) { model.moveMacroToGroup(id: macro.id, groupId: g.id) }
                }
            }
            Divider()
            if isManual {
                Button("上移") { model.moveMacroUp(macro.id) }
                Button("下移") { model.moveMacroDown(macro.id) }
                Divider()
            }
            Button("删除", role: .destructive) { confirmDelete = macro }
        }
    }

    // MARK: - 回收站

    private var trashSection: some View {
        Section {
            ForEach(trash) { macro in
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(macro.name).fontWeight(.medium)
                        if !macro.preview.isEmpty {
                            Text(macro.preview)
                                .font(.callout.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let d = macro.deletedAt {
                        Text("删除于 " + d.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("恢复") { model.restoreMacro(id: macro.id) }
                        .buttonStyle(.bordered)
                    Button { model.purgeMacro(id: macro.id) } label: {
                        Image(systemName: "xmark.circle").foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("永久删除")
                }
                .contextMenu {
                    Button("恢复") { model.restoreMacro(id: macro.id) }
                    Button("永久删除", role: .destructive) { model.purgeMacro(id: macro.id) }
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
                Text("已删除 (\(trash.count))").font(.headline)
                Spacer()
                Button("清空") { confirmPurgeAll = true }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .disabled(trash.isEmpty)
            }
        }
    }

    // MARK: - 拖放解析

    private func handleDrop(_ items: [String], targetGroup: UUID?, before: UUID?) -> Bool {
        guard let s = items.first, let src = UUID(uuidString: s) else { return false }
        if let targetID = before {
            model.moveMacro(src, before: targetID)   // 同组=重排，跨组=换到该组该行前
        } else {
            model.moveMacroToGroup(id: src, groupId: targetGroup)   // 拖到分组标题=加入该组
        }
        return true
    }

    // MARK: - 组内找相邻（▲▼ 边界判断）

    private func findPrevInGroup(_ macro: Macro, gid: UUID?) -> Macro? {
        guard let i = model.macros.firstIndex(where: { $0.id == macro.id }) else { return nil }
        for j in (0..<i).reversed() where model.macros[j].groupId == gid && !model.macros[j].isDeleted {
            return model.macros[j]
        }
        return nil
    }

    private func findNextInGroup(_ macro: Macro, gid: UUID?) -> Macro? {
        guard let i = model.macros.firstIndex(where: { $0.id == macro.id }) else { return nil }
        for j in (i + 1)..<model.macros.count where model.macros[j].groupId == gid && !model.macros[j].isDeleted {
            return model.macros[j]
        }
        return nil
    }
}
