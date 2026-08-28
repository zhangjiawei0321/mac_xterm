import SwiftUI

/// 新建 / 编辑宏对话框：宏名称 + 多行命令文本
struct MacroEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var commands = ""
    @State private var lineDelayMs = 0

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
                Section {
                    HStack(spacing: 8) {
                        Text("行间延迟")
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        TextField("行间延迟", value: $lineDelayMs, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Stepper("", value: $lineDelayMs, in: 0...10000, step: 100)
                            .labelsHidden()
                        Text("毫秒，0 = 一次整体下发")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text("多行命令默认是整段一次下发；shell 会逐行执行，等一条前台命令跑完才跑下一条。若某些设备/命令需要「第一条完成后再发第二条」，把延迟调到 200~1000ms 即可。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("执行节奏")
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
            lineDelayMs = editing?.lineDelayMs ?? 0
        }
    }

    private func save() {
        model.saveMacro(id: editing?.id, name: name, commands: commands, lineDelayMs: lineDelayMs)
        model.macroEditorPresented = false
        dismiss()
    }
}
