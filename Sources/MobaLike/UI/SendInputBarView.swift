import SwiftUI
import AppKit

/// 底部发送输入栏（SecureCRT 风格，多行）：
/// 多行输入，回车=换行，点「发送」一次性发给所选目标（当前窗口/所有窗口/自定义勾选）。
struct SendInputBarView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var targetLabel: String {
        switch model.sendBarMode {
        case 1: return "所有窗口"
        case 2: return "选择的窗口(\(model.sendBarSelectedIDs.count))"
        default: return "当前窗口"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                // 多行输入框（至少约 5 行）
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .focused($focused)
                    .frame(minHeight: 112, maxHeight: 140)   // ≈5-6 行
                    .padding(5)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("在这里输入命令（支持多行，回车换行）…")
                                .font(.callout)
                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                .padding(.leading, 10).padding(.top, 10)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(spacing: 8) {
                    Menu {
                        Button {
                            model.sendBarMode = 0
                        } label: {
                            Label("当前窗口（已点击/激活）", systemImage: model.sendBarMode == 0 ? "checkmark" : "")
                        }
                        Button {
                            model.sendBarMode = 1
                        } label: {
                            Label("所有窗口", systemImage: model.sendBarMode == 1 ? "checkmark" : "")
                        }
                        Button {
                            model.sendBarMode = 2
                        } label: {
                            Label("选择的窗口…", systemImage: model.sendBarMode == 2 ? "checkmark" : "")
                        }
                        if model.sendBarMode == 2 && !model.tabs.isEmpty {
                            Divider()
                            Menu("勾选要发送的窗口") {
                                Button("全选") {
                                    model.sendBarSelectedIDs = Set(model.tabs.map(\.id))
                                }
                                Button("清空") {
                                    model.sendBarSelectedIDs = []
                                }
                                Divider()
                                ForEach(model.tabs) { tab in
                                    Button {
                                        if model.sendBarSelectedIDs.contains(tab.id) {
                                            model.sendBarSelectedIDs.remove(tab.id)
                                        } else {
                                            model.sendBarSelectedIDs.insert(tab.id)
                                        }
                                    } label: {
                                        Label(tab.title,
                                              systemImage: model.sendBarSelectedIDs.contains(tab.id) ? "checkmark.square" : "square")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("发送到：\(targetLabel)", systemImage: "scope")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)

                    Spacer()
                    Button {
                        send()
                    } label: {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                    .help("把输入内容发给所选窗口 (回车为换行，不发送)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { focused = true }
        }
    }

    private func send() {
        let t = text
        guard !t.isEmpty else { return }
        model.sendFromBar(t)
        text = ""
        focused = true
    }
}
