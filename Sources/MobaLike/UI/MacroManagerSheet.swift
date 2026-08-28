import SwiftUI

/// 宏管理：列表（拖动或上下按钮排序）+ 编辑 / 删除 / 运行 / 新建
struct MacroManagerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var list: [Macro] { model.macros }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("宏管理")
                    .font(.title3.bold())
                Text("拖动行或点 ▲▼ 排序")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("新建宏") { model.showMacroEditor(nil) }
                    .buttonStyle(.bordered)
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            if list.isEmpty {
                Spacer()
                Text("还没有宏，点击「新建宏」创建第一条")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(Array(list.enumerated()), id: \.element.id) { idx, macro in
                        HStack(spacing: 10) {
                            Image(systemName: "play.circle")
                                .foregroundColor(.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(macro.name)
                                    .fontWeight(.medium)
                                if !macro.preview.isEmpty {
                                    Text(macro.preview)
                                        .font(.callout.monospaced())
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()

                            Button {
                                model.moveMacroUp(macro.id)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx == 0)
                            .help("上移")

                            Button {
                                model.moveMacroDown(macro.id)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx == list.count - 1)
                            .help("下移")

                            Button {
                                model.deleteMacro(id: macro.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("删除")
                        }
                        .padding(.vertical, 2)
                        .contextMenu {
                            Button("运行") { model.runMacro(macro) }
                            Button("编辑…") { model.showMacroEditor(macro) }
                            Divider()
                            Button("删除", role: .destructive) { model.deleteMacro(id: macro.id) }
                        }
                    }
                    .onMove { model.moveMacro(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 400)
    }
}
