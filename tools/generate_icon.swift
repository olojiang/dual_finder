import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: "release/DualFinder.iconset")

let fileManager = FileManager.default
try? fileManager.removeItem(at: output)
try fileManager.createDirectory(at: output, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512]

func drawIcon(size: Int) throws -> Data {
    let imageSize = NSSize(width: size, height: size)
    let image = NSImage(size: imageSize)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: imageSize).fill()

    let scale = CGFloat(size) / 1024.0
    let bounds = NSRect(x: 96 * scale, y: 96 * scale, width: 832 * scale, height: 832 * scale)
    let radius = 210 * scale
    let body = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.24, alpha: 1.0).setFill()
    body.fill()

    let top = NSRect(x: 154 * scale, y: 686 * scale, width: 716 * scale, height: 116 * scale)
    NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.86, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: top, xRadius: 46 * scale, yRadius: 46 * scale).fill()

    let leftPane = NSRect(x: 168 * scale, y: 236 * scale, width: 322 * scale, height: 400 * scale)
    let rightPane = NSRect(x: 534 * scale, y: 236 * scale, width: 322 * scale, height: 400 * scale)
    NSColor(calibratedWhite: 0.96, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: leftPane, xRadius: 54 * scale, yRadius: 54 * scale).fill()
    NSBezierPath(roundedRect: rightPane, xRadius: 54 * scale, yRadius: 54 * scale).fill()

    NSColor(calibratedRed: 0.14, green: 0.64, blue: 0.42, alpha: 1.0).setFill()
    for index in 0..<3 {
        let y = (548 - CGFloat(index) * 104) * scale
        NSBezierPath(roundedRect: NSRect(x: 220 * scale, y: y, width: 218 * scale, height: 34 * scale), xRadius: 17 * scale, yRadius: 17 * scale).fill()
        NSBezierPath(roundedRect: NSRect(x: 586 * scale, y: y, width: 218 * scale, height: 34 * scale), xRadius: 17 * scale, yRadius: 17 * scale).fill()
    }

    NSColor(calibratedRed: 0.98, green: 0.67, blue: 0.23, alpha: 1.0).setFill()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 466 * scale, y: 448 * scale))
    arrow.line(to: NSPoint(x: 512 * scale, y: 504 * scale))
    arrow.line(to: NSPoint(x: 558 * scale, y: 448 * scale))
    arrow.line(to: NSPoint(x: 532 * scale, y: 448 * scale))
    arrow.line(to: NSPoint(x: 532 * scale, y: 338 * scale))
    arrow.line(to: NSPoint(x: 492 * scale, y: 338 * scale))
    arrow.line(to: NSPoint(x: 492 * scale, y: 448 * scale))
    arrow.close()
    arrow.fill()

    image.unlockFocus()
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DualFinderIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render icon"])
    }
    return png
}

for size in sizes {
    let normal = try drawIcon(size: size)
    try normal.write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))

    let retina = try drawIcon(size: size * 2)
    try retina.write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

print("Generated iconset at \(output.path)")
