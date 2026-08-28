import SwiftUI
import AppKit

/// 宏栏方向：底部横向 / 左/右侧纵向
enum MacroBarOrientation {
    case horizontal, vertical
}

/// 宏栏：横条（底部）或竖条（左/右）。
/// - 未分组的宏直接显示为按钮；
/// - 分组在宏栏里也显示：横向为「文件夹菜单」（点开运行其成员宏），纵向为分组小标题。
struct MacroBarView: View {
    @EnvironmentObject var model: AppModel
    let orientation: MacroBarOrientation

    @State private var showGroupAlert = false
    @State private var groupName = ""
    /// 纵向面板中处于折叠状态的分组 id
    @State private var collapsedGroups: Set<UUID> = []

    private var ungrouped: [Macro] { model.macros(inGroup: nil) }

    var body: some View {
        switch orientation {
        case .horizontal:
            horizontalBody
        case .vertical:
            verticalBody
        }
    }

    // MARK: - 底部横条

    private var horizontalBody: some View {
        HStack(spacing: 8) {
            Label("宏", systemImage: "play.rectangle.on.rectangle")
                .font(.callout.bold())
                .foregroundColor(.secondary)
                .padding(.leading, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ungrouped) { macro in
                        MacroBarButton(macro: macro, vertical: false)
                    }
                    ForEach(model.macroGroups) { g in
                        groupMenu(g)
                    }
                    if model.macros.isEmpty && model.macroGroups.isEmpty {
                        Text("还没有宏，点右侧 ＋ 创建")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(minHeight: 34)

            Spacer(minLength: 0)
            toolbarButtons(vertical: false)
                .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .newGroupAlert(binding: $showGroupAlert, name: $groupName) { model.addMacroGroup(named: $0) }
    }

    /// 分组在横条上显示为文件夹菜单
    private func groupMenu(_ g: MacroGroup) -> some View {
        let members = model.macros(inGroup: g.id)
        return Menu {
            if members.isEmpty {
                Button("（空分组）") {}.disabled(true)
            }
            ForEach(members) { macro in
                Button {
                    model.runMacro(macro)
                } label: {
                    Label(macro.name, systemImage: "play.circle")
                }
            }
            Divider()
            Button("新建宏到该分组…") {
                model.showMacroEditor(nil)
                // 新建后默认归属该分组：通过临时记录
                model.defaultNewMacroGroup = g.id
            }
        } label: {
            Label(g.name, systemImage: "folder")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("分组：\(g.name)")
    }

    // MARK: - 左/右侧竖条

    private var verticalBody: some View {
        VStack(spacing: 6) {
            Label("宏", systemImage: "play.rectangle.on.rectangle")
                .font(.caption.bold())
                .foregroundColor(.secondary)
                .padding(.top, 10)

            toolbarButtons(vertical: true)
                .padding(.horizontal, 6)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    if !ungrouped.isEmpty {
                        groupHeader("未分组", collapsed: false, count: ungrouped.count) {}
                        ForEach(ungrouped) { macro in
                            MacroBarButton(macro: macro, vertical: true)
                        }
                    }
                    ForEach(model.macroGroups) { g in
                        let members = model.macros(inGroup: g.id)
                        groupHeader(g.name, collapsed: collapsedGroups.contains(g.id), count: members.count) {
                            if collapsedGroups.contains(g.id) {
                                collapsedGroups.remove(g.id)
                            } else {
                                collapsedGroups.insert(g.id)
                            }
                        }
                        if !collapsedGroups.contains(g.id) {
                            if members.isEmpty {
                                Text("（空分组）")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(members) { macro in
                                    MacroBarButton(macro: macro, vertical: true)
                                }
                            }
                        }
                    }
                    if model.macros.isEmpty && model.macroGroups.isEmpty {
                        Text("尚未创建宏")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 150)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .newGroupAlert(binding: $showGroupAlert, name: $groupName) { model.addMacroGroup(named: $0) }
    }

    /// 分组标题行（点击折叠/展开）
    private func groupHeader(_ title: String, collapsed: Bool, count: Int,
                             onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                Image(systemName: "folder").font(.caption2)
                Text(title)
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .help(collapsed ? "展开分组" : "折叠分组")
    }

    // MARK: - 工具按钮

    @ViewBuilder
    private func toolbarButtons(vertical: Bool) -> some View {
        Group {
            Menu {
                Button("新建宏…") { model.showMacroEditor(nil) }
                Button("新建分组…") {
                    groupName = ""
                    showGroupAlert = true
                }
            } label: {
                Label("新建", systemImage: "plus")
                    .font(vertical ? .caption : .callout)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                model.macroManagerPresented = true
            } label: {
                Label("管理", systemImage: "slider.horizontal.3")
                    .font(vertical ? .caption : .callout)
            }
            .buttonStyle(.borderless)
            .help("宏管理：排序 / 分组 / 编辑 / 删除")
        }
    }
}

/// 宏栏上的单个宏按钮：点击运行；右键可 运行/编辑/删除
struct MacroBarButton: View {
    @EnvironmentObject var model: AppModel
    let macro: Macro
    let vertical: Bool

    var body: some View {
        Button {
            model.runMacro(macro)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "play.circle")
                Text(macro.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.callout)
            .frame(maxWidth: vertical ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .help(macro.preview.isEmpty ? macro.name : "\(macro.preview)")
        .contextMenu {
            Button("运行") { model.runMacro(macro) }
            Button("编辑…") { model.showMacroEditor(macro) }
            Divider()
            Button("删除", role: .destructive) { model.deleteMacro(id: macro.id) }
        }
    }
}
