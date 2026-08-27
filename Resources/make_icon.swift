import AppKit

// 生成 MobaLike 应用图标（终端主题）：
// 深蓝→青渐变圆角方块 + 终端窗口(红黄绿点) + 白色提示符 ">_" + 绿色连接指示
// 用法: swiftc make_icon.swift -o /tmp/mkicon && /tmp/mkicon <输出目录>

func draw(_ ctx: NSGraphicsContext, size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()

    // 渐变背景
    let g = NSGradient(colors: [
        NSColor(calibratedRed: 0.05, green: 0.10, blue: 0.22, alpha: 1),
        NSColor(calibratedRed: 0.02, green: 0.45, blue: 0.55, alpha: 1),
    ])!
    g.draw(in: rect, angle: -72)

    // 顶部高光
    NSColor(calibratedWhite: 1, alpha: 0.08).setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: size * 0.72, width: size, height: size * 0.28),
                 xRadius: radius, yRadius: 0).fill()

    // 终端"窗口"
    let m = size * 0.17
    let winRect = NSRect(x: m, y: m, width: size - 2 * m, height: size - 2 * m)
    let win = NSBezierPath(roundedRect: winRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.10, alpha: 0.55).setFill()
    win.fill()

    // 交通灯(红黄绿)
    let dotR = size * 0.02
    let dotY = size - m - size * 0.075
    let colors: [NSColor] = [
        NSColor(calibratedRed: 1.0, green: 0.28, blue: 0.24, alpha: 1),
        NSColor(calibratedRed: 0.97, green: 0.80, blue: 0.10, alpha: 1),
        NSColor(calibratedRed: 0.25, green: 0.84, blue: 0.42, alpha: 1),
    ]
    for (i, c) in colors.enumerated() {
        c.setFill()
        let x = m + size * 0.05 + CGFloat(i) * (dotR * 3.4)
        NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: dotR * 2, height: dotR * 2)).fill()
    }

    // 提示符 ">_"
    let prompt = ">_"
    let font = NSFont.monospacedSystemFont(ofSize: size * 0.30, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1),
    ]
    let str = NSAttributedString(string: prompt, attributes: attrs)
    let ts = str.size()
    let textRect = NSRect(
        x: m + (size - 2 * m - ts.width) / 2,
        y: m + (size - 2 * m - ts.height) / 2,
        width: ts.width, height: ts.height)
    str.draw(in: textRect)

    // 底部绿色连接点
    NSColor(calibratedRed: 0.22, green: 0.86, blue: 0.42, alpha: 1).setFill()
    let dot = size * 0.045
    NSBezierPath(ovalIn: NSRect(x: size - m - dot * 2, y: m + size * 0.02,
                                width: dot, height: dot)).fill()
}

func render(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!, size: size)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let fm = FileManager.default
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let entries: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in entries {
    let path = (iconset as NSString).appendingPathComponent(name)
    try? render(size: size).write(to: URL(fileURLWithPath: path))
    print("wrote \(name)")
}
