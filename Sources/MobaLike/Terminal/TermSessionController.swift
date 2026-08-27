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
    private(set) var isOpen = true
    /// 会话开始时间（用于日志时间戳估算、失败判定等）
    var sessionStart = Date()

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    deinit {
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
