import SwiftUI

/// 新建 / 编辑宏对话框：宏名称 + 多行命令文本
struct MacroEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var commands = ""

    private var editing: Macro? { model.editingMacro }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(editing == nil ? "新建宏" : "编辑宏", systemImage: "scope")
                    .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            Form {
                Section {
                    TextField("宏名称", text: $name)
                } header: {
                    Text("名称")
                }
                Section {
                    TextEditor(text: $commands)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 180)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3))
                        )
                } header: {
                    Text("命令（支持多行，每行一条）")
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Text("运行时自动在末尾补一个回车，最后一条命令会立即执行。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(editing == nil ? "创建" : "保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear {
            name = editing?.name ?? ""
            commands = editing?.commands ?? ""
        }
    }

    private func save() {
        model.saveMacro(id: editing?.id, name: name, commands: commands)
        model.macroEditorPresented = false
        dismiss()
    }
}
