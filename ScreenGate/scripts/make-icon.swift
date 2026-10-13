import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = destination.appendingPathComponent("ScreenGate.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        let frame = NSRect(x: p * 0.07, y: p * 0.07, width: p * 0.86, height: p * 0.86)
        let background = NSBezierPath(roundedRect: frame, xRadius: p * 0.2, yRadius: p * 0.2)
        NSColor(calibratedRed: 0.21, green: 0.38, blue: 0.86, alpha: 1).setFill(); background.fill()
        if let symbol = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil) {
            let configured = symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: p * 0.56, weight: .regular)) ?? symbol
            configured.isTemplate = false
            NSColor.white.set()
            let tinted = NSImage(size: configured.size)
            tinted.lockFocus(); configured.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.setFill(); NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop); tinted.unlockFocus()
            tinted.draw(in: NSRect(x: p * 0.26, y: p * 0.22, width: p * 0.48, height: p * 0.56))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(filename))
    }
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.appendingPathComponent("ScreenGate.icns").path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: iconset)
