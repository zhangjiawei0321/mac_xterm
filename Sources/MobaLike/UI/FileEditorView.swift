import SwiftUI
import AppKit

/// 一个待编辑的文件（本地或远端临时副本）
struct FileDoc {
    var fileName: String
    /// 可读写的本地路径（本地文件=原路径；远端文件=下载的临时副本）
    var localPath: String
    /// 是否可写（只读时禁止编辑/保存）
    var isWritable: Bool
    /// 远端文件回传信息（非 nil = 保存时上传回远端）
    var remoteRef: (host: String, port: Int, user: String, password: String, remotePath: String)?
}

/// 文件编辑器标签页：显示文件内容，按读写权限只读或可编辑保存（⌘S）
struct FileEditorView: View {
    @EnvironmentObject var model: AppModel
    let tab: TerminalTab

    @State private var content = ""
    @State private var loaded = false
    @State private var errorText: String?
    @State private var savedFlash = false

    private var doc: FileDoc? { tab.fileDoc }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let err = errorText {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundColor(.orange)
                    Text(err)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !loaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .padding(6)
                    .disabled(!(doc?.isWritable ?? false))
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear(perform: load)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.accentColor)
            Text(doc?.fileName ?? "文件")
                .font(.callout.bold())
                .lineLimit(1)
            if doc?.isWritable == false {
                Label("只读", systemImage: "lock")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            if let r = doc?.remoteRef {
                Label("远端 \(r.host)", systemImage: "network")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if savedFlash {
                Label("已保存", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            Spacer()
            Button("保存") { save() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!(doc?.isWritable ?? false))
                .help("保存 (⌘S)")
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func load() {
        guard !loaded else { return }
        guard let doc else { errorText = "文件信息缺失"; loaded = true; return }
        if let data = try? Data(contentsOf: URL(fileURLWithPath: doc.localPath)),
           let text = String(data: data, encoding: .utf8) {
            content = text
            errorText = nil
        } else if let data = try? Data(contentsOf: URL(fileURLWithPath: doc.localPath)) {
            // 非 UTF-8：仅提示，二进制不以文本方式打开
            errorText = "该文件不是 UTF-8 文本，无法在编辑器显示（大小 \(data.count) 字节）"
        } else {
            errorText = "无法读取文件：\(doc.localPath)"
        }
        loaded = true
    }

    private func save() {
        guard let doc, doc.isWritable else { return }
        do {
            try content.write(toFile: doc.localPath, atomically: true, encoding: .utf8)
        } catch {
            errorText = "保存失败：\(error.localizedDescription)"
            return
        }
        if let r = doc.remoteRef {
            // 远端文件：上传回远端
            let client = SftpClient(host: r.host, port: r.port, user: r.user, password: r.password)
            DispatchQueue.global().async {
                let e = client.put(local: doc.localPath, remote: r.remotePath)
                DispatchQueue.main.async {
                    if let e {
                        errorText = "已保存到本地临时文件，但上传远端失败：\(e)"
                    } else {
                        flashSaved()
                    }
                }
            }
        } else {
            flashSaved()
        }
    }

    private func flashSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            savedFlash = false
        }
    }
}

/// 文件标签页占位控制器（不实际使用，仅满足 controller(for:) 类型要求）
@MainActor
final class FileTabStubController: TermSessionController {
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
