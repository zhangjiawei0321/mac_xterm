import SwiftUI
import AppKit

/// 原生 NSTextField 纯数字输入框。
/// 完全绕开 SwiftUI `TextField` 在 macOS 14 上「成批落屏 / 输入显示延迟」的回归
/// （底部 TextEditor 不卡正是因为底层是原生 NSTextView；这里同样走原生路径）。
/// 仅在输入内容真正变化时回写绑定；数字输入每个字符即时显示。
struct NativeDigitField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.isBordered = true
        f.bezelStyle = .roundedBezel
        f.placeholderString = "0"
        f.delegate = context.coordinator
        f.target = context.coordinator
        f.action = #selector(Coordinator.didCommit)
        f.focusRingType = .default
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        // 只在非编辑状态下同步外部值（如步进器修改），避免打断正在输入的会话
        if nsView.stringValue != text && nsView.currentEditor() == nil {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeDigitField
        init(_ parent: NativeDigitField) { self.parent = parent }

        private func sanitize(_ value: String) -> String {
            value.filter { $0.isNumber && $0.isASCII }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            let value = f.stringValue
            let filtered = sanitize(value)
            if filtered != value {
                f.stringValue = filtered   // 过滤非法字符；纯数字输入不触发，不打断
            }
            parent.text = filtered
        }

        @objc func didCommit(_ sender: Any?) {
            guard let f = sender as? NSTextField else { return }
            f.stringValue = sanitize(f.stringValue)
            parent.text = f.stringValue
            parent.onCommit()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            f.stringValue = sanitize(f.stringValue)
            parent.text = f.stringValue
            parent.onCommit()
        }
    }
}
