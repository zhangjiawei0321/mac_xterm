import SwiftUI
import AppKit

/// 底部发送输入栏（SecureCRT 风格）：输入一行，回车一次性发给当前窗口（或发给所有窗口）
struct SendInputBarView: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentColor)
                TextField("输入命令，回车发送到当前窗口", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { send() }
                Toggle("发给所有窗口", isOn: $model.sendBarBroadcast)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .controlSize(.small)
                    .help("勾选后，发送内容会同时发往所有已打开的终端窗口")
                Text(model.sendBarBroadcast ? "将发送到所有已打开终端" : "发送到当前（点击的）窗口")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Button("发送") { send() }
                    .buttonStyle(.bordered)
                    .disabled(text.isEmpty)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
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
