// Renders the app icon (white paw on a blue squircle) into AppIcon.iconset.
// Run: swift Scripts/makeicon.swift <output.iconset dir>
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ size: Int) -> Data? {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: s, height: s)

    // Squircle gradient background.
    let inset = s * 0.08
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset),
                            xRadius: s * 0.22, yRadius: s * 0.22)
    // Accent oklch(64.6% .222 41.116) ≈ #EA580C, with a slightly deeper stop.
    NSGradient(colors: [NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1),
                        NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 1)])?
        .draw(in: path, angle: -90)

    // White paw symbol centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.52, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let ps = paw.size
        paw.draw(in: NSRect(x: (s - ps.width) / 2, y: (s - ps.height) / 2,
                            width: ps.width, height: ps.height))
    }
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: size, height: size)
    return rep.representation(using: .png, properties: [:])
}

// Sizes iconutil expects (1x and 2x).
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                   ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                   ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    if let data = render(px) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/icon_\(name).png"))
    }
}
print("✅ wrote \(outDir)")
