import SwiftUI
import AppKit
import SwiftTerm

/// 用 NSViewControllerRepresentable 承载底层会话控制器，
/// 这样 SwiftUI 会让 AppKit 正确触发 viewWillAppear/viewDidAppear，
/// 从而在首次显示时自动发起连接。
struct TermHostController: NSViewControllerRepresentable {
    let controller: TermSessionController

    func makeNSViewController(context: Context) -> NSViewController {
        return controller
    }

    func updateNSViewController(_ vc: NSViewController, context: Context) {}
}
