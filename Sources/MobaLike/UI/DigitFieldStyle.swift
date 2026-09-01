import SwiftUI
import AppKit

/// 数字输入框统一样式：
/// - 用 .plain（而非 macOS 14 在 Form 里明显输入延迟的 .roundedBorder）；
/// - 自绘圆角边框保持观感；
/// - 关闭自动更正/智能处理，避免系统对数字/字母的文本替换路径介入。
extension View {
    func digitFieldStyle(_ width: CGFloat? = nil) -> some View {
        self
            .textFieldStyle(.plain)
            .disableAutocorrection(true)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .frame(width: width)
    }
}
