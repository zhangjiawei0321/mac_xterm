import SwiftUI
import AppKit

/// 临时输入延迟诊断面板（定位「每满4个字符才落屏」发生在哪一层，测完即删）。
/// ① 纯净原生 NSTextField：无绑定、无代理，纯 AppKit，完全不受 SwiftUI 更新影响
/// ② 产品所用 NativeDigitField（有绑定写回 + 代理过滤）
/// ③ SwiftUI TextField（系统默认 roundedBorder）
struct InputDiagView: View {
    @State private var b = ""
    @State private var c = ""

    /// 纯原生、零干预
    struct RawNativeProbe: NSViewRepresentable {
        func makeNSView(context: Context) -> NSTextField {
            let f = NSTextField()
            f.isBordered = true
            f.bezelStyle = .roundedBezel
            f.placeholderString = "1234"
            return f
        }
        func updateNSView(_ nsView: NSTextField, context: Context) {}
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("① 纯净原生(无绑定)")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
                RawNativeProbe().frame(width: 200, height: 24)
            }
            HStack(spacing: 8) {
                Text("② 产品NativeDigitField")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
                NativeDigitField(text: $b).frame(width: 200, height: 24)
            }
            HStack(spacing: 8) {
                Text("③ SwiftUI TextField")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(width: 150, alignment: .leading)
                TextField("", text: $c)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200, height: 24)
            }
            Text("依次在每个框连打 1234 再删掉打 123：①纯原生卡不卡、②产品框卡不卡、③SwiftUI框卡不卡。底部发送栏(TextEditor ④)已知不卡。")
                .font(.caption2).foregroundColor(.secondary)
        }
    }
}
