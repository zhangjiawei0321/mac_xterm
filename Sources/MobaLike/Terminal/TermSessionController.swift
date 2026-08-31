import Foundation
import AppKit

/// 标签页连接状态（用于标签标题后缀等表现）
enum TabStatus: Equatable {
    case connecting
    case connected
    case disconnected
}

/// 一个打开的标签页。持有底层的 AppKit 会话控制器并保持其存活，
/// 这样切换标签页时不会中断连接。
@MainActor
final class TerminalTab: ObservableObject, Identifiable {
    let id = UUID()
    let kind: SessionKind
    /// 会话配置（重连/更新密码时会被替换）
    private(set) var session: SessionConfig?     // local 终端为 nil
    @Published var title: String
    @Published var status: TabStatus = .connecting
    /// 会话版本号：重连（更换控制器）时 +1，用于强制重建终端视图
    @Published var revision = 0
    /// 底层会话控制器（懒创建；由 AppModel 统一创建并缓存）
    fileprivate(set) var controller: TermSessionController?
    /// 若为文件标签页（kind == .file），这里保存待编辑的文件信息
    var fileDoc: FileDoc?

    init(kind: SessionKind, session: SessionConfig?, title: String) {
        self.kind = kind
        self.session = session
        self.title = title
    }

    func attach(controller: TermSessionController) {
        self.controller = controller
        controller.onTitleChange = { [weak self] newTitle in
            self?.title = newTitle
        }
        controller.onStateChange = { [weak self] connected in
            self?.status = connected ? .connected : .disconnected
            if !connected {
                if let base = self?.session?.defaultTabTitle ?? self?.title {
                    if !base.hasSuffix("（已断开）") {
                        self?.title = base + "（已断开）"
                    }
                }
            }
        }
    }

    func close() {
        controller?.closeSession()
        controller = nil
        status = .disconnected
    }

    /// 以新配置重连（例如密码错误后更新密码再重连）：
    /// 关闭旧控制器、替换配置、重置状态并强制重建视图。
    func reconnect(with config: SessionConfig) {
        controller?.closeSession()
        controller = nil
        session = config
        title = config.defaultTabTitle
        status = .connecting
        revision += 1
    }
}

/// 会话控制器基类：负责创建终端视图、启动/关闭会话
@MainActor
class TermSessionController: NSViewController {
    var onTitleChange: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    /// 输出被送入终端时回调（用于日志环形缓存捕获）
    var onOutput: ((Data) -> Void)?
    private(set) var isOpen = true
    /// 会话开始时间（用于日志时间戳估算、失败判定等）
    var sessionStart = Date()

    // 终端视图的事件的本地监听（右键即时菜单 / 断开后按 R 重连）
    private var rightClickMonitor: Any?
    private var keyMonitor: Any?
    private var handlersInstalled = false
    /// PTY 尺寸变更防抖任务（拖拽分屏/缩放窗口时避免终端刷屏）
    private var resizeWork: DispatchWorkItem?

    /// PTY 窗口尺寸防抖：把多个连续 sizeChanged 合并为一次（等 ~150ms 停止变化后发送）
    func debouncedPtyResize(_ block: @escaping () -> Void) {
        resizeWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            self?.resizeWork = nil
            block()
        }
        resizeWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installTerminalEventHandlers()
    }

    /// 视图出现后把键盘焦点交给终端，方便直接输入
    func focusTerminal() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let f = self.view.window?.firstResponder, f === self.view {
                return
            }
            self.view.window?.makeFirstResponder(self.view)
        }
    }

    // MARK: - 事件监听（右键菜单 + R 重连）

    /// 安装：右键落在本终端 → 弹出“即时构建”的菜单；会话断开时按 R 重连。
    /// 用本地事件监听实现，避免 AppKit 方法无法被子类重写的问题。
    private func installTerminalEventHandlers() {
        guard !handlersInstalled, view != nil else { return }
        handlersInstalled = true

        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let view = self.view
            guard let window = view.window else { return event }
            guard let content = window.contentView as NSView? else { return event }
            let loc = content.convert(event.locationInWindow, from: nil)
            guard let hit = content.hitTest(loc), self.isSelfOrDescendant(hit, of: view) else { return event }
            let menu = self.buildTerminalContextMenu()
            menu.popUp(positioning: nil, at: event.locationInWindow, in: content)
            return nil
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let view = self.view
            guard let window = view.window else { return event }
            var target = false
            if let fr = window.firstResponder as? NSView {
                target = (fr === view) || self.isSelfOrDescendant(fr, of: view)
            }
            guard target else { return event }

            // ⌘V：粘贴（无论连接与否都可粘贴输入）
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "v" {
                self.pasteClipboard()
                return nil
            }

            guard !self.isOpen else { return event }   // 其余按键：连接时放行
            // 断开的会话：只把 R 用作重连；其它按键放行（不吞，避免影响搜索框等）
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if chars.contains("r") {
                self.onReconnectRequested?(self)
                return nil
            }
            return event
        }
    }

    private func removeTerminalEventHandlers() {
        if let m = rightClickMonitor {
            NSEvent.removeMonitor(m)
            rightClickMonitor = nil
        }
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        handlersInstalled = false
    }

    private func isSelfOrDescendant(_ maybe: NSView?, of root: NSView) -> Bool {
        var cur = maybe
        while let c = cur {
            if c === root { return true }
            cur = c.superview
        }
        return false
    }

    /// 关闭会话（子类实现：终止进程 / 关闭串口）
    func closeSession() {
        isOpen = false
    }

    /// 子类在进程退出时调用
    func markTerminated() {
        guard isOpen else { return }
        isOpen = false
        onStateChange?(false)
    }

    /// 通知标签页更新连接中状态
    func markStarted() {
        onStateChange?(true)
    }

    // MARK: - 会话菜单动作（子类实现）

    /// 把文本粘入会话（等价于在终端里输入）
    func sendInput(_ text: String) {}

    /// 清除终端显示与回滚（日志）
    func clearLog() {}

    /// 导出会话日志文本（保存日志用）；timestamped 为真时附带时间戳
    func exportLogData(timestamped: Bool) -> Data? { nil }

    /// 用于保存日志的默认文件名
    var logDefaultName: String { "会话" }

    /// 复制当前选中文本到剪贴板
    func copySelection() {}

    /// 复制终端全部文本（缓冲区）到剪贴板
    func copyAll() {}

    /// 当前是否存在选中文本（决定“拷贝”菜单是否可用）
    var hasSelection: Bool { false }

    /// 搜索终端输出，返回命中列表（子类实现）
    func searchLineHits(_ query: String) -> [TerminalSearchHit] { [] }

    /// 跳转到搜索结果：先滚动到目标行，再高亮该关键词（子类实现）
    func jumpToSearchLine(_ query: String, hitIndex: Int, row: Int) {}

    /// 会话断开后，用户按 R 触发重连时回调（子类转发给顶层）
    var onReconnectRequested: ((TermSessionController) -> Void)?

    /// 应用终端外观（背景色等，读取设置）
    func applyAppearance() {}

    /// 把 UTF-8 文本数据放入剪贴板
    func copyBufferToPasteboard(_ data: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let s = String(data: data, encoding: .utf8) {
            pb.setString(s, forType: .string)
        }
    }

    // MARK: - 原生右键菜单（在右键那一刻构建，状态最新）

    /// 由 TerminalMenuViews 在右键时调用，返回带当前选中状态的菜单
    func buildTerminalContextMenu() -> NSMenu {
        let m = NSMenu()
        let paste = NSMenuItem(title: "粘贴",
                               action: #selector(pasteAction(_:)), keyEquivalent: "")
        paste.target = self
        m.addItem(paste)
        m.addItem(.separator())
        let copySel = NSMenuItem(title: "拷贝选中文本",
                                 action: #selector(copySelectionAction(_:)), keyEquivalent: "")
        copySel.target = self
        copySel.isEnabled = hasSelection    // 构建时读取 = 右键那一刻的选中状态
        m.addItem(copySel)
        let copyAll = NSMenuItem(title: "复制全部",
                                 action: #selector(copyAllAction(_:)), keyEquivalent: "")
        copyAll.target = self
        m.addItem(copyAll)
        m.addItem(.separator())
        let clear = NSMenuItem(title: "清除日志",
                               action: #selector(clearLogAction(_:)), keyEquivalent: "")
        clear.target = self
        m.addItem(clear)
        let save = NSMenuItem(title: "保存日志…",
                              action: #selector(saveLogAction(_:)), keyEquivalent: "")
        save.target = self
        m.addItem(save)
        return m
    }

    /// 粘贴剪贴板文本进会话（= 输入到终端）
    func pasteClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        sendInput(text)
    }

    @objc private func pasteAction(_ sender: Any?) { pasteClipboard() }

    @objc private func copySelectionAction(_ sender: Any?) { copySelection() }
    @objc private func copyAllAction(_ sender: Any?) { copyAll() }
    @objc private func clearLogAction(_ sender: Any?) { clearLog() }
    @objc private func saveLogAction(_ sender: Any?) {
        saveLogPanel()
    }

    /// 保存日志到文件（供右键菜单 / 标签页菜单共用）
    func saveLogPanel() {
        guard let data = exportLogData(timestamped: UserDefaults.standard.bool(forKey: "logTimestamped")) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = logDefaultName
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    deinit {
        // 移除事件监听（deinit 非隔离上下文，直接调用线程安全的 removeMonitor）
        if let r = rightClickMonitor {
            NSEvent.removeMonitor(r)
        }
        if let k = keyMonitor {
            NSEvent.removeMonitor(k)
        }
        resizeWork?.cancel()
        SessionRegistry.shared.unregister(self)
    }
}

/// 全局会话注册表：应用退出时统一终止所有子进程/串口。
/// 普通线程安全类（非 MainActor），通过 assumeIsolated 在调用线程为主线程时同步执行关闭。
final class SessionRegistry {
    static let shared = SessionRegistry()
    private let lock = NSLock()
    private var controllers = NSHashTable<AnyObject>.weakObjects()

    private init() {}

    func register(_ c: TermSessionController) {
        lock.lock()
        controllers.add(c)
        lock.unlock()
    }

    func unregister(_ c: TermSessionController) {
        lock.lock()
        controllers.remove(c)
        lock.unlock()
    }

    func terminateAll() {
        lock.lock()
        let list = controllers.allObjects
        lock.unlock()

        let closeAll: @MainActor () -> Void = {
            for obj in list {
                (obj as? TermSessionController)?.closeSession()
            }
        }
        if Thread.isMainThread {
            MainActor.assumeIsolated { closeAll() }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { closeAll() }
            }
        }
    }
}
