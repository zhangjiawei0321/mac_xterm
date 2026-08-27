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

    private let baudOptions = [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
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
                    Text("串口 (Serial)").tag(SessionKind.serial)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .onChange(of: kind) { newKind in
                    draft.kind = newKind
                    if draft.name.isEmpty {
                        draft.name = defaultName(for: newKind)
                    }
                }
            }

            switch kind {
            case .ssh:
                sshForm
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
                draft.name = defaultName(for: kind)
            }
        }
    }

    // MARK: - SSH 表单

    private var sshForm: some View {
        Form {
            Section("SSH 连接") {
                TextField("会话名称", text: $draft.name)
                TextField("主机（IP 或域名）", text: $draft.host)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    TextField("端口", value: portBinding, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                    Spacer()
                    TextField("用户名", text: $draft.username)
                        .textFieldStyle(.roundedBorder)
                }
                SecureField("密码（可留空，留空则在终端内输入）", text: $draft.password)
                    .textFieldStyle(.roundedBorder)
            }

            Section("密钥认证") {
                Toggle("使用密钥文件", isOn: $draft.useKey)
                if draft.useKey {
                    HStack {
                        TextField("密钥路径", text: $draft.keyPath)
                            .textFieldStyle(.roundedBorder)
                        Button("选择…") { chooseKeyFile() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - 串口表单

    private var serialForm: some View {
        Form {
            Section("串口连接") {
                HStack {
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
                TextField("会话名称", text: $draft.name)
            }

            Section("参数") {
                Picker("波特率", selection: $draft.serial.baudRate) {
                    ForEach(baudOptions, id: \.self) { b in
                        Text("\(b)").tag(b)
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

    /// UInt16 <-> Int 的绑定桥接（TextField 数值格式化只对 Int 方便）
    private var portBinding: Binding<Int> {
        Binding(
            get: { Int(draft.port) },
            set: { draft.port = UInt16(clamping: $0) }
        )
    }

    private func defaultName(for k: SessionKind) -> String {
        switch k {
        case .ssh: return "SSH 会话"
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
        // 名称兜底
        if draft.name.isEmpty {
            switch kind {
            case .ssh:
                draft.name = draft.username.isEmpty ? draft.host : "\(draft.username)@\(draft.host)"
            case .serial:
                draft.name = (draft.serial.device as NSString).lastPathComponent
            case .local:
                draft.name = "本地终端"
            }
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
