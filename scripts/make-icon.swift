#!/usr/bin/env swift
// Draws the app icon and writes Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// Needs only AppKit and `iconutil` (both ship with macOS). Re-run it after
// changing the drawing; the .icns is committed so a normal build doesn't need it.
import AppKit

func draw(size s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // macOS icon grid: the artwork fills ~82% of the canvas.
    let inset = s * 0.09
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.025
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
        NSColor(calibratedRed: 0.27, green: 0.20, blue: 0.80, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)

    // Magic Mouse: a tall, smooth capsule.
    let w = tile.width * 0.36, h = tile.width * 0.64
    let mouse = NSRect(x: tile.midX - w / 2, y: tile.midY - h / 2 - tile.height * 0.02, width: w, height: h)
    let body = NSBezierPath(roundedRect: mouse, xRadius: w / 2, yRadius: w / 2)
    NSColor.white.setFill()
    body.fill()

    // Touch point on the surface plus a ripple: the "tap".
    let center = NSPoint(x: mouse.midX, y: mouse.maxY - h * 0.34)
    let ring = NSBezierPath(ovalIn: NSRect(x: center.x - w * 0.34, y: center.y - w * 0.34, width: w * 0.68, height: w * 0.68))
    ring.lineWidth = w * 0.045
    NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 0.55).setStroke()
    ring.stroke()
    let dot = NSBezierPath(ovalIn: NSRect(x: center.x - w * 0.15, y: center.y - w * 0.15, width: w * 0.30, height: w * 0.30))
    NSColor(calibratedRed: 0.30, green: 0.35, blue: 0.95, alpha: 1).setFill()
    dot.fill()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let work = FileManager.default.temporaryDirectory.appendingPathComponent("MagicTap-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]
for (name, px) in sizes {
    let png = draw(size: px).representation(using: .png, properties: [:])!
    try png.write(to: work.appendingPathComponent("icon_\(name).png"))
}

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", work.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: work)
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(out.path)")
