// Draws AppIcon.icns: a fuel-gauge style dial in the menu bar colors.
// Run from this folder: swift make_icon.swift

import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Draws the icon on a 1024×1024 canvas, scaled to `px` pixels.
func render(px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Body on Apple's macOS icon grid: 824pt rounded square, 100pt margin.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(starting: color(0x34373D), ending: color(0x141518))!.draw(in: bodyPath, angle: -90)

    // Dial: four arc segments, red (empty) on the left to green (plenty) on the right.
    let center = NSPoint(x: 512, y: 470)
    let radius: CGFloat = 270
    let segments: [(UInt32, CGFloat, CGFloat)] = [
        (0xFF4245, 210, 172), (0xFF9230, 168, 112), (0xC99A00, 108, 62), (0x30D158, 58, -30),
    ]
    for (hex, start, end) in segments {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        arc.lineWidth = 70
        arc.lineCapStyle = .butt
        color(hex).setStroke()
        arc.stroke()
    }

    // Needle pointing into the green.
    let angle: CGFloat = 25 * .pi / 180
    let tip = NSPoint(x: center.x + cos(angle) * 225, y: center.y + sin(angle) * 225)
    let needle = NSBezierPath()
    needle.move(to: center)
    needle.line(to: tip)
    needle.lineWidth = 30
    needle.lineCapStyle = .round
    NSColor.white.setStroke()
    needle.stroke()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84)).fill()

    // "GB" under the hub.
    let label = NSAttributedString(string: "GB", attributes: [
        .font: NSFont.systemFont(ofSize: 150, weight: .black),
        .foregroundColor: NSColor.white,
    ])
    let size = label.size()
    label.draw(at: NSPoint(x: 512 - size.width / 2, y: 200))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(px: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", "AppIcon.icns", iconset.path]
try! iconutil.run()
iconutil.waitUntilExit()
try! FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "Wrote AppIcon.icns" : "iconutil failed")
