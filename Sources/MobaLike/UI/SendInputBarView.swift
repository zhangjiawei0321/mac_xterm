import SwiftUI
import AppKit

/// 底部发送输入栏（SecureCRT 风格，多行）：
/// 多行输入，回车=换行，点「发送」一次性发给所选目标。
/// 目标：当前窗口 / 所有窗口 / 自定义勾选（弹出面板，悬停即可逐个打勾）。
struct SendInputBarView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @State private var pickerPresented = false

    private var targetLabel: String {
        switch model.sendBarMode {
        case 1: return "所有窗口"
        case 2: return "选择 \(model.sendBarSelectedIDs.count) 个"
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
                    .frame(minHeight: 112, maxHeight: 140)
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
                        Button { model.sendBarMode = 0 } label: {
                            Label("当前窗口（已点击/激活）", systemImage: model.sendBarMode == 0 ? "checkmark.circle.fill" : "circle")
                        }
                        Button { model.sendBarMode = 1 } label: {
                            Label("所有窗口", systemImage: model.sendBarMode == 1 ? "checkmark.circle.fill" : "circle")
                        }
                        Button {
                            model.sendBarMode = 2
                            pickerPresented = true
                        } label: {
                            Label("选择的窗口…", systemImage: model.sendBarMode == 2 ? "checkmark.circle.fill" : "circle")
                        }
                    } label: {
                        Label("发送到：\(targetLabel)", systemImage: "scope")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()   // 避免 borderless 菜单撑满整行，把后续按钮挤到右侧

                    if model.sendBarMode == 2 {
                        Button {
                            pickerPresented.toggle()
                        } label: {
                            Label("勾选窗口", systemImage: "checklist")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .popover(isPresented: $pickerPresented, arrowEdge: .bottom) {
                            windowPicker
                        }
                    }

                    Button {
                        send()
                    } label: {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                    .help("把输入内容发给所选窗口 (回车为换行，不发送)")

                    Spacer()
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

    // MARK: - 窗口选择面板（悬停/点击均可勾选，不关闭面板）

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("选择要发送的窗口").font(.callout.bold())
                Spacer()
                Button("全选") { model.sendBarSelectedIDs = Set(model.tabs.map(\.id)) }
                    .controlSize(.small)
                Button("清空") { model.sendBarSelectedIDs = [] }
                    .controlSize(.small)
                Button("完成") { pickerPresented = false }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.tabs) { tab in
                        windowRow(tab)
                    }
                    if model.tabs.isEmpty {
                        Text("还没有打开的窗口")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(10)
        .frame(width: 320)
    }

    private func windowRow(_ tab: TerminalTab) -> some View {
        let on = model.sendBarSelectedIDs.contains(tab.id)
        return HStack(spacing: 6) {
            Text(model.tabNumber(of: tab.id).map { "\($0)" } ?? "?")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(minWidth: 14)
            Image(systemName: tab.kind.iconName)
                .font(.system(size: 10))
                .foregroundColor(tab.status == .disconnected ? .secondary : .accentColor)
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Image(systemName: on ? "checkmark.square.fill" : "square")
                .foregroundColor(on ? .accentColor : .secondary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .background(on ? Color.accentColor.opacity(0.10) : Color.clear)
        .onTapGesture { toggle(tab.id) }   // 点击打勾（面板不关闭，可连续多选）
    }

    private func toggle(_ id: UUID) {
        if model.sendBarSelectedIDs.contains(id) {
            model.sendBarSelectedIDs.remove(id)
        } else {
            model.sendBarSelectedIDs.insert(id)
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
