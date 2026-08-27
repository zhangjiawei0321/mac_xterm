import SwiftUI

/// 会话提示弹窗的统一宿主：根据 prompt 类型渲染三种小窗
struct SessionPromptSheet: View {
    let prompt: SessionPrompt

    var body: some View {
        switch prompt {
        case .username(let cfg):
            UsernameSheet(config: cfg)
        case .savePassword(let cfg):
            SavePasswordSheet(config: cfg)
        case .retryPassword(let cfg):
            RetryPasswordSheet(config: cfg)
        }
    }
}

/// 未填 SSH 用户名：连接前手动输入（不默认用 Mac 用户名）
struct UsernameSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let config: SessionConfig
    @State private var username = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Label("需要登录用户名", systemImage: "person.fill.questionmark")
                .font(.title3.bold())
            Text("会话「\(config.name)」（\(config.host)）未填写用户名。\n请输入登录用户名，不会默认使用 Mac 本机用户名。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            TextField("用户名", text: $username)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack(spacing: 12) {
                Button("取消") {
                    model.resolveUsername("", cancelled: true, for: config)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("连接") {
                    model.resolveUsername(username, cancelled: false, for: config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(username.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// 交互登录成功后，询问是否保存密码（重输一次确认）
struct SavePasswordSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let config: SessionConfig
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Label("登录成功", systemImage: "checkmark.seal.fill")
                .font(.title3.bold())
                .foregroundColor(.green)
            Text("是否把「\(config.name)」的密码保存下来？\n保存后下次连接可自动登录，不再要求输入。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            SecureField("密码（重新输入一次以保存）", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack(spacing: 12) {
                Button("不保存") {
                    model.resolveSavePassword("", cancelled: true, for: config)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") {
                    model.resolveSavePassword(password, cancelled: false, for: config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// 自动登录失败（密码错误/不可达等）：重输密码后重连
struct RetryPasswordSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let config: SessionConfig
    @State private var password = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Label("登录失败", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.bold())
                .foregroundColor(.orange)
            Text("「\(config.name)」自动登录被拒绝：密码可能已更改或错误。\n重新输入后会自动更新并重连。")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            SecureField("新密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
            HStack(spacing: 12) {
                Button("取消") {
                    model.resolveRetryPassword("", cancelled: true, for: config)
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("更新并重连") {
                    model.resolveRetryPassword(password, cancelled: false, for: config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
