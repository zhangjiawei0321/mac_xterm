import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 侧栏里的远端文件浏览器（SFTP，仿 MobaXterm）：
/// 列目录 / 进文件夹 / 返回上级 / 拖拽上传 / 下载 / 新建文件夹 / 删除 / 重命名
struct SftpBrowserView: View {
    @EnvironmentObject var model: AppModel

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: SftpEntry?
    @State private var renameName = ""
    @State private var renamePresented = false
    @State private var confirmDelete: SftpEntry?

    private var sorted: [SftpEntry] {
        model.sftpEntries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            pathBar
            Divider()
            content
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            loadFileURLs(providers) { urls in
                if !urls.isEmpty { model.sftpUpload(urls, into: nil) }
            }
            return true
        }
        .alert("新建文件夹", isPresented: $showNewFolder) {
            TextField("文件夹名称", text: $newFolderName)
            Button("创建") { model.sftpNewFolder(newFolderName) }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: $renamePresented) {
            TextField("新名称", text: $renameName)
            Button("确定") {
                if let e = renameTarget { model.sftpRename(e, to: renameName) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("删除", isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let e = confirmDelete { model.sftpDelete(e) }
                confirmDelete = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(confirmDelete.map { "确定删除「\($0.name)」吗？\($0.isDirectory ? "（目录需为空）" : "")" } ?? "")
        }
    }

    // MARK: - 头

    private var header: some View {
        HStack(spacing: 6) {
            Label("远端文件", systemImage: "externaldrive.connected.to.line.below")
                .font(.callout.bold())
                .foregroundColor(.secondary)
            Spacer()
            if model.sftpBusy {
                ProgressView().controlSize(.small)
            }
            Button { model.sftpRefresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(model.sftpBusy)
            .help("刷新")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var pathBar: some View {
        HStack(spacing: 5) {
            Button { model.sftpGoUp() } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(model.sftpPath == "/" || model.sftpBusy)
            .help("上级目录")
            Text(model.sftpPath)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Menu {
                Button("新建文件夹…") { showNewFolder = true }
                Button("上传文件…") { chooseUpload(into: nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .help("更多操作")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        if let msg = model.sftpMessage {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 26))
                    .foregroundColor(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                if !model.sftpEntries.isEmpty {
                    Button("重试") { model.sftpRefresh() }
                        .controlSize(.small)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.sftpEntries.isEmpty {
            VStack(spacing: 8) {
                if model.sftpBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "folder")
                        .font(.system(size: 26))
                        .foregroundColor(.secondary)
                    Text("空目录")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sorted) { entry in
                        row(entry)
                    }
                }
            }
        }
    }

    private func row(_ e: SftpEntry) -> some View {
        HStack(spacing: 6) {
            Image(systemName: e.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 12))
                .foregroundColor(e.isDirectory ? .accentColor : .secondary)
            Text(e.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if !e.isDirectory {
                Text(e.sizeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture {
            if e.isDirectory { model.sftpEnter(e) }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            // 拖文件到文件夹行 = 上传进该文件夹
            let target = model.sftpFullPath(e.name)
            loadFileURLs(providers) { urls in
                if !urls.isEmpty { model.sftpUpload(urls, into: e.isDirectory ? target : nil) }
            }
            return true
        }
        .contextMenu {
            if e.isDirectory {
                Button("打开") { model.sftpEnter(e) }
                Button("上传文件到此处…") { chooseUpload(into: model.sftpFullPath(e.name)) }
            } else {
                Button("下载到…") { model.sftpDownload(e) }
            }
            Divider()
            Button("重命名…") {
                renameTarget = e
                renameName = e.name
                renamePresented = true
            }
            Button("删除", role: .destructive) { confirmDelete = e }
        }
    }

    // MARK: - 工具

    /// 选择本地文件上传
    private func chooseUpload(into path: String?) {
        let op = NSOpenPanel()
        op.canChooseFiles = true
        op.canChooseDirectories = true
        op.allowsMultipleSelection = true
        op.canCreateDirectories = false
        op.prompt = "上传"
        op.begin { resp in
            guard resp == .OK else { return }
            model.sftpUpload(op.urls, into: path)
        }
    }

    /// 解析拖入的文件 URL
    private func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
        var urls: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            p.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                } else if let url = item as? URL {
                    urls.append(url)
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(urls) }
    }
}
