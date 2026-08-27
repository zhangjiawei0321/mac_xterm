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
    let session: SessionConfig?     // local 终端为 nil
    @Published var title: String
    @Published var status: TabStatus = .connecting
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
}

/// 会话控制器基类：负责创建终端视图、启动/关闭会话
@MainActor
class TermSessionController: NSViewController {
    var onTitleChange: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    private(set) var isOpen = true

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    deinit {
        SessionRegistry.shared.unregister(self)
    }
}

/// 全局会话注册表：应用退出时统一终止所有子进程/串口
final class SessionRegistry {
    static let shared = SessionRegistry()
    private var controllers = NSHashTable<AnyObject>.weakObjects()

    private init() {}

    func register(_ c: TermSessionController) {
        controllers.add(c)
    }

    func unregister(_ c: TermSessionController) {
        controllers.remove(c)
    }

    func terminateAll() {
        for obj in controllers.allObjects {
            (obj as? TermSessionController)?.closeSession()
        }
    }
}
