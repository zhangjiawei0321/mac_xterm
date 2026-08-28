import SwiftUI
import AppKit

/// 新建 / 编辑会话对话框（SSH / 串口两页）
struct NewSessionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = SessionConfig(name: "", kind: .ssh)
    @State private var kind: SessionKind = .ssh
    @State private var devices: [String] = SerialPort.listDevices()
    @State private var openAfterSave = true
    @State private var customBaudEnabled = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, host, port, username, password, keyPath, device, baud
    }

    private let baudOptions = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    private var isEditing: Bool { model.editingSession != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(isEditing ? "编辑会话" : "新建会话", systemImage: "plus.square.on.square")
                    .font(.title3.bold())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            if !isEditing {
                Picker("会话类型", selection: $kind) {
                    Text("SSH").tag(SessionKind.ssh)
                    Text("Telnet").tag(SessionKind.telnet)
                    Text("串口 (Serial)").tag(SessionKind.serial)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .onChange(of: kind) { oldKind, newKind in
                    draft.kind = newKind
                    // 只有当端口还是旧类型的默认值（即用户未手工改过）时，才切到新类型的默认端口
                    if draft.port == oldKind.defaultPort {
                        draft.port = newKind.defaultPort
                    }
                }
            }

            switch kind {
            case .ssh:
                sshForm
            case .telnet:
                telnetForm
            case .serial:
                serialForm
            case .local:
                EmptyView()
            }

            Divider()

            HStack {
                Toggle("保存后立即连接", isOn: $openAfterSave)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "保存" : "创建") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 500)
        .onAppear {
            if let editing = model.editingSession {
                draft = editing
                kind = editing.kind
                if !draft.serial.device.isEmpty && !devices.contains(draft.serial.device) {
                    devices.append(draft.serial.device)
                }
            } else {
                kind = model.newSessionKind
                draft = SessionConfig(name: "", kind: kind)
                draft.port = kind.defaultPort   // SSH=22 / Telnet=23
            }
            // 打开即聚焦主要输入框，无需先点击输入框
            DispatchQueue.main.async {
                focusedField = (kind == .ssh || kind == .telnet) ? .host : .name
            }
        }
    }

    // MARK: - 表单行：点击整行即可聚焦输入

    private func focusFieldRow(_ label: String, _ field: Field,
                               _ text: Binding<String>, secure: Bool = false,
                               prompt: String = "") -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(prompt))
                } else {
                    TextField("", text: text, prompt: Text(prompt))
                }
            }
            .textFieldStyle(.roundedBorder)
            .focused($focusedField, equals: field)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    // MARK: - SSH 表单

    private var sshForm: some View {
        Form {
            Section("SSH 连接") {
                focusFieldRow("会话名称", .name, $draft.name, prompt: autoName)
                focusFieldRow("主机", .host, $draft.host)
                HStack(spacing: 8) {
                    Text("端口")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("端口", value: portBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .focused($focusedField, equals: .port)
                    Text("用户名")
                        .foregroundColor(.secondary)
                    TextField("", text: $draft.username)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .username)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .username }
                focusFieldRow("密码", .password, $draft.password, secure: true)
            }

            Section("密钥认证") {
                Toggle("使用密钥文件", isOn: $draft.useKey)
                if draft.useKey {
                    HStack {
                        Text("密钥路径")
                            .foregroundColor(.secondary)
                        TextField("", text: $draft.keyPath)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .keyPath)
                        Button("选择…") { chooseKeyFile() }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .keyPath }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Telnet 表单

    private var telnetForm: some View {
        Form {
            Section("Telnet 连接") {
                focusFieldRow("会话名称", .name, $draft.name, prompt: autoName)
                focusFieldRow("主机", .host, $draft.host)
                HStack(spacing: 8) {
                    Text("端口")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    TextField("端口", value: portBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 96)
                        .focused($focusedField, equals: .port)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { focusedField = .port }
                Text("登录账号/密码由远端 Telnet 交互提示，直接在终端里输入即可。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 串口表单

    private var serialForm: some View {
        Form {
            Section("串口连接") {
                HStack {
                    Text("设备")
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Picker("设备", selection: $draft.serial.device) {
                        ForEach(devices, id: \.self) { dev in
                            Text(dev).tag(dev)
                        }
                    }
                    .labelsHidden()
                    Button {
                        devices = SerialPort.listDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("刷新串口列表")
                }
                focusFieldRow("会话名称", .name, $draft.name, prompt: autoName)
            }

            Section("参数") {
                if customBaudEnabled {
                    HStack(spacing: 8) {
                        Text("波特率")
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .trailing)
                        TextField("", value: baudBinding, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .baud)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { focusedField = .baud }
                    Toggle("自定义波特率", isOn: $customBaudEnabled)
                } else {
                    Picker("波特率", selection: $draft.serial.baudRate) {
                        ForEach(baudOptions, id: \.self) { b in
                            Text("\(b)").tag(b)
                        }
                        Divider()
                        Text("自定义…").tag(-1)
                    }
                    .onChange(of: draft.serial.baudRate) { newValue in
                        if newValue == -1 {
                            customBaudEnabled = true
                            draft.serial.baudRate = 115200
                            focusedField = .baud
                        }
                    }
                }
                Picker("数据位", selection: $draft.serial.dataBits) {
                    ForEach([5, 6, 7, 8], id: \.self) { b in
                        Text("\(b) bits").tag(b)
                    }
                }
                Picker("校验位", selection: $draft.serial.parity) {
                    ForEach(Parity.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                Picker("停止位", selection: $draft.serial.stopBits) {
                    Text("1 位").tag(1)
                    Text("2 位").tag(2)
                }
                Picker("流控", selection: $draft.serial.flowControl) {
                    ForEach(FlowControl.allCases) { f in
                        Text(f.displayName).tag(f)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 动作

    /// 自动生成会话名：SSH=主机名:(用户名)，串口=设备名:(波特率)，Telnet=主机名
    private var autoName: String {
        switch kind {
        case .ssh:
            guard !draft.host.isEmpty else { return "" }
            return draft.username.isEmpty ? draft.host : "\(draft.host):(\(draft.username))"
        case .telnet:
            guard !draft.host.isEmpty else { return "" }
            return draft.host
        case .serial:
            guard !draft.serial.device.isEmpty else { return "" }
            let base = (draft.serial.device as NSString).lastPathComponent
            return "\(base):(\(draft.serial.baudRate))"
        case .local:
            return "本地终端"
        }
    }

    /// UInt16 <-> Int 的绑定桥接（TextField 数值格式化只对 Int 方便）
    private var portBinding: Binding<Int> {
        Binding(
            get: { Int(draft.port) },
            set: { draft.port = UInt16(clamping: $0) }
        )
    }

    /// 自定义波特率编辑绑定
    private var baudBinding: Binding<Int> {
        Binding(
            get: { draft.serial.baudRate <= 0 ? 115200 : draft.serial.baudRate },
            set: { draft.serial.baudRate = max($0, 1) }
        )
    }

    private func defaultName(for k: SessionKind) -> String {
        switch k {
        case .ssh: return "SSH 会话"
        case .telnet: return "Telnet 会话"
        case .serial: return "串口会话"
        case .local: return "本地终端"
        }
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                draft.keyPath = url.path
                draft.useKey = true
            }
        }
    }

    private func save() {
        // 名称兜底：优先用自动名（主机名/设备名后缀），都没有才用通用名
        if draft.name.isEmpty {
            draft.name = autoName
            if draft.name.isEmpty { draft.name = defaultName(for: kind) }
        }
        draft.kind = kind

        if let editingID = model.editingSession?.id {
            var updated = draft
            updated.id = editingID
            model.updateSession(updated)
        } else {
            model.addSession(draft, toFolder: model.pendingParentID)
            if openAfterSave {
                openSessionAfterCreate(draft)
            }
        }
        dismiss()
    }

    private func openSessionAfterCreate(_ config: SessionConfig) {
        model.openSession(config: config)
    }
}
