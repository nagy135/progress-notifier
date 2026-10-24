import AppKit

// A native vector drawing keeps every icon size sharp without external assets.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    context.imageInterpolation = .high

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.14, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.25, alpha: 1),
               ending: NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.11, alpha: 1))!
        .draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.1).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    let center = NSPoint(x: 512, y: 542)
    let track = NSBezierPath(ovalIn: NSRect(x: 254, y: 284, width: 516, height: 516))
    track.lineWidth = 58
    NSColor.white.withAlphaComponent(0.09).setStroke()
    track.stroke()
    let progress = NSBezierPath()
    progress.appendArc(withCenter: center, radius: 258, startAngle: 90, endAngle: -190, clockwise: true)
    progress.lineWidth = 58
    progress.lineCapStyle = .round
    NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.72, alpha: 1).setStroke()
    progress.stroke()

    for (x, height) in [(393.0, 100.0), (487.0, 160.0), (581.0, 220.0)] {
        NSColor(calibratedRed: 0.90, green: 0.98, blue: 0.96, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: 420, width: 50, height: height), xRadius: 22, yRadius: 22).fill()
    }
    let bar = NSRect(x: 312, y: 192, width: 400, height: 26)
    NSColor.white.withAlphaComponent(0.09).setFill()
    NSBezierPath(roundedRect: bar, xRadius: 13, yRadius: 13).fill()
    NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.72, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: bar.minX, y: bar.minY, width: 280, height: bar.height), xRadius: 13, yRadius: 13).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
try render(1024).write(to: output.appendingPathComponent("AppIcon.png"))
