import SwiftUI
import AppKit

/// 宏栏方向：底部横向 / 左/右侧纵向
enum MacroBarOrientation {
    case horizontal, vertical
}

/// 宏栏：横条（底部）或竖条（左/右）。点击宏按钮 = 把宏的多行命令发给当前活动终端。
struct MacroBarView: View {
    @EnvironmentObject var model: AppModel
    let orientation: MacroBarOrientation

    @State private var showGroupAlert = false
    @State private var groupName = ""

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
                    ForEach(model.barMacros) { macro in
                        MacroBarButton(macro: macro, vertical: false)
                    }
                    if model.macros.isEmpty {
                        Text("还没有宏，点右侧 ＋ 创建")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 4)
            }

            Spacer(minLength: 0)
            toolbarButtons(vertical: false)
                .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .newGroupAlert(binding: $showGroupAlert, name: $groupName) { model.addMacroGroup(named: $0) }
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
                VStack(spacing: 4) {
                    ForEach(model.barMacros) { macro in
                        MacroBarButton(macro: macro, vertical: true)
                    }
                    if model.macros.isEmpty {
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
        .frame(width: 132)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .newGroupAlert(binding: $showGroupAlert, name: $groupName) { model.addMacroGroup(named: $0) }
    }

    /// 新建分组的工具栏按钮
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
