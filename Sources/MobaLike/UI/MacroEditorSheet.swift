import SwiftUI

/// 新建 / 编辑宏对话框：宏名称 + 多行命令文本
struct MacroEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var commands = ""
    @State private var lineDelayMs = 0
    @State private var lineDelayText = "0"
    @State private var groupId: UUID?

    private var editing: Macro? { model.editingMacro }

    /// 重名实时提示：输入过程中即时检查（排除编辑中的自己；空名自动命名不报错）
    private var duplicateName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if model.macroNameExists(name, excluding: editing?.id) {
            return "已有同名宏「\(trimmed)」，宏名不能重复"
        }
        return nil
    }

    /// 重名时禁止保存
    private var canSave: Bool { duplicateName == nil }

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
                    if let dup = duplicateName {
                        Label(dup, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("留空将自动命名（宏 1、宏 2…），不可重名。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("该名称可以使用。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("名称")
                }
                Section {
                    HStack(spacing: 8) {
                        Text("分组")
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        Picker("", selection: $groupId) {
                            Text("未分组").tag(UUID?.none)
                            ForEach(model.macroGroups) { g in
                                Text(g.name).tag(UUID?.some(g.id))
                            }
                        }
                        .labelsHidden()
                    }
                } header: {
                    Text("归属")
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
                        NativeDigitField(text: $lineDelayText) { commitLineDelay() }
                            .frame(width: 90)
                        Stepper("", value: Binding(
                            get: { lineDelayMs },
                            set: { lineDelayMs = $0; lineDelayText = String($0) }
                        ), in: 0...10000, step: 100)
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
                    .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear {
            name = editing?.name ?? ""
            commands = editing?.commands ?? ""
            lineDelayMs = editing?.lineDelayMs ?? 0
            lineDelayText = String(lineDelayMs)
            if let editing {
                groupId = editing.groupId
            } else {
                groupId = model.defaultNewMacroGroup   // 从宏栏分组菜单新建时预选分组
                model.defaultNewMacroGroup = nil
            }
        }
    }

    /// 行间延迟提交：回车 / 失焦 / 保存时写回（避免逐键触发表单重绘导致卡顿），限 0…10000ms
    private func commitLineDelay() {
        lineDelayMs = min(max(Int(lineDelayText) ?? 0, 0), 10_000)
    }

    private func save() {
        guard canSave else { return }
        commitLineDelay()
        let saved = model.saveMacro(id: editing?.id, name: name,
                                    commands: commands, lineDelayMs: lineDelayMs, groupId: groupId)
        guard saved else { return }   // 服务端防御：重名时不保存
        model.macroEditorPresented = false
        dismiss()
    }
}
