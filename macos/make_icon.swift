// 生成应用图标：渐变底 + 📚 表情符号
// 用法: make_icon <像素尺寸> <输出png路径>
import AppKit

func makeIcon(size: Int, path: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { fatalError("无法创建位图") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let bg = NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.225, yRadius: CGFloat(size) * 0.225)
    bg.addClip()

    let g = NSGradient(colors: [
        NSColor(calibratedRed: 0.44, green: 0.36, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.24, green: 0.55, blue: 0.98, alpha: 1),
    ])!
    g.draw(in: rect, angle: -60)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: CGFloat(size) * 0.58),
    ]
    let str = NSAttributedString(string: "📚", attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: (CGFloat(size) - sz.width) / 2, y: (CGFloat(size) - sz.height) / 2))

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 编码失败") }
    try! png.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    fputs("用法: make_icon <尺寸> <输出路径>\n", stderr)
    exit(1)
}
makeIcon(size: size, path: args[2])
