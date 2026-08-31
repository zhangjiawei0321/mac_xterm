import SwiftUI
import AppKit
import SwiftTerm

/// 用 NSViewControllerRepresentable 承载底层会话控制器。
///
/// 关键点：控制器在单屏/分屏之间会被**反复挂载**（同一个 NSViewController 的 view
/// 由不同的 representable 承载）。直接返回控制器本身会让 SwiftUI 在重复挂载时
/// 无法重新安置旧 view，导致某个格空白。因此这里用一个**稳定容器**：
/// 每次更新时把控制器的 view 从旧宿主摘下、重新贴进当前容器，保证复用可靠。
struct TermHostController: NSViewControllerRepresentable {
    let controller: TermSessionController

    func makeNSViewController(context: Context) -> NSViewController {
        let host = NSViewController()
        host.view = NSView(frame: .zero)
        return host
    }

    func updateNSViewController(_ vc: NSViewController, context: Context) {
        // 建立父子关系：保证 viewAppear 事件正常触发（会话借此启动/聚焦）
        if !vc.children.contains(where: { $0 === controller }) {
            vc.addChild(controller)
        }
        let v = controller.view       // 触发 loadView（首次会自动发起连接）
        if v.superview !== vc.view {
            v.removeFromSuperview()
            v.frame = vc.view.bounds
            v.autoresizingMask = [.width, .height]
            vc.view.addSubview(v)
        }
        // 聚焦由 AppModel 的激活格统一控制（点格聚焦 / 切分屏聚焦），这里不抢焦点
    }
}
