import SwiftUI
import AppKit
import SwiftTerm

/// 用 NSViewControllerRepresentable 承载底层会话控制器。
///
/// 可靠挂载策略：终端不会在单一的 update 时机被挂载（那时宿主 bounds 可能还是 0，
/// 会导致单屏/分屏切换后空白），而是由宿主容器在**每次 layout / 加入窗口时**
/// 以当时的正确尺寸把终端视图贴上去——布局一旦稳定，终端必然可见。
/// 控制器作为子控制器挂载，保证 viewDidAppear（会话启动）正常触发。
struct TermHostController: NSViewControllerRepresentable {
    let controller: TermSessionController

    /// 终端宿主容器：跟踪控制器，并在自身 layout / 入窗时重贴终端视图
    final class HostView: NSView {
        weak var controller: TermSessionController?

        override func layout() {
            super.layout()
            attachTerminal()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachTerminal()
        }

        /// 把控制器的终端视图贴满本容器（从旧宿主摘下）
        func attachTerminal() {
            guard let controller else { return }
            let v = controller.view   // 触发 loadView（首次自动发起连接）
            if v.superview !== self {
                v.removeFromSuperview()
                v.autoresizingMask = [.width, .height]
                addSubview(v)
            }
            v.frame = bounds
        }
    }

    func makeNSViewController(context: Context) -> NSViewController {
        let host = NSViewController()
        let hv = HostView(frame: .zero)
        hv.controller = controller
        host.view = hv
        return host
    }

    func updateNSViewController(_ vc: NSViewController, context: Context) {
        // 建立父子关系：保证 viewAppear 事件正常触发（会话借此启动/聚焦）
        if !vc.children.contains(where: { $0 === controller }) {
            vc.addChild(controller)
        }
        if let hv = vc.view as? HostView {
            hv.controller = controller
            hv.attachTerminal()
        }
        // 聚焦由 AppModel 的激活格统一控制（点格聚焦 / 切分屏聚焦），这里不抢焦点
    }
}
