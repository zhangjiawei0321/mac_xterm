import SwiftUI

/// 主窗口最底部的宏栏：横向宏按钮 + 新建/管理入口。
/// 点击宏按钮 = 把宏的多行命令发给当前活动终端。
struct MacroBarView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "play.rectangle.on.rectangle")
                Text("宏")
            }
            .font(.callout.bold())
            .foregroundColor(.secondary)
            .padding(.leading, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.macros) { macro in
                        MacroBarButton(macro: macro)
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

            Button {
                model.showMacroEditor(nil)
            } label: {
                Label("新建宏", systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("新建一个宏")

            Button {
                model.macroManagerPresented = true
            } label: {
                Label("管理", systemImage: "slider.horizontal.3")
                    .font(.callout)
            }
            .buttonStyle(.borderless)
            .help("宏管理：排序 / 编辑 / 删除")

            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

/// 宏栏上的单个宏按钮：点击运行；右键可 运行/编辑/删除
struct MacroBarButton: View {
    @EnvironmentObject var model: AppModel
    let macro: Macro

    var body: some View {
        Button {
            model.runMacro(macro)
        } label: {
            Label(macro.name, systemImage: "play.circle")
                .font(.callout)
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
