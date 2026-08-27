import AppKit
import SwiftTerm

/// 终端外观：背景颜色预设（不同配色背景 + 对应前景），对打开的终端实时生效
enum TerminalAppearance {
    struct Preset {
        let key: String
        let title: String
        let bg: NSColor
        let fg: NSColor
    }

    static let options: [Preset] = [
        Preset(key: "default", title: "系统默认（跟随深浅色）",
               bg: NSColor.textBackgroundColor, fg: NSColor.textColor),
        Preset(key: "classicBlack", title: "经典黑",
               bg: NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1),
               fg: NSColor(calibratedWhite: 0.92, alpha: 1)),
        Preset(key: "deepNavy", title: "深夜蓝",
               bg: NSColor(calibratedRed: 0.035, green: 0.09, blue: 0.19, alpha: 1),
               fg: NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.97, alpha: 1)),
        Preset(key: "forestGreen", title: "墨绿",
               bg: NSColor(calibratedRed: 0.03, green: 0.14, blue: 0.08, alpha: 1),
               fg: NSColor(calibratedRed: 0.75, green: 0.95, blue: 0.82, alpha: 1)),
        Preset(key: "darkTeal", title: "青黑",
               bg: NSColor(calibratedRed: 0.02, green: 0.11, blue: 0.13, alpha: 1),
               fg: NSColor(calibratedRed: 0.72, green: 0.95, blue: 0.92, alpha: 1)),
        Preset(key: "graphite", title: "石墨灰",
               bg: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.15, alpha: 1),
               fg: NSColor(calibratedWhite: 0.9, alpha: 1)),
        Preset(key: "warmWhite", title: "暖白",
               bg: NSColor(calibratedRed: 0.96, green: 0.94, blue: 0.90, alpha: 1),
               fg: NSColor(calibratedRed: 0.18, green: 0.18, blue: 0.18, alpha: 1)),
    ]

    static var currentKey: String {
        UserDefaults.standard.string(forKey: "terminalBackground") ?? "default"
    }

    /// MobaXterm 风格的高饱和 16 色调色板（ANSI 色彩输出更鲜艳）
    static func vividPalette() -> [Color] {
        func c(_ r: UInt16, _ g: UInt16, _ b: UInt16) -> Color { Color(red8: r, green8: g, blue8: b) }
        return [
            c(0, 0, 0), c(205, 0, 0), c(0, 205, 0), c(205, 205, 0),
            c(0, 0, 238), c(205, 0, 205), c(0, 205, 205), c(229, 229, 229),
            c(127, 127, 127), c(255, 0, 0), c(0, 255, 0), c(255, 255, 0),
            c(92, 92, 255), c(255, 0, 255), c(0, 255, 255), c(255, 255, 255),
        ]
    }

    static func apply(to view: TerminalView) {
        view.installColors(vividPalette())
        let key = currentKey
        if let preset = options.first(where: { $0.key == key }), key != "default" {
            view.nativeBackgroundColor = preset.bg
            view.nativeForegroundColor = preset.fg
        } else {
            view.configureNativeColors()   // 系统默认
        }
    }
}
