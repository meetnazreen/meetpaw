// Square app logo (no rounded corners) for the Google consent-screen upload.
// Run: swift Scripts/makelogo.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "meetpaw-logo.png"
let s: CGFloat = 512
let img = NSImage(size: NSSize(width: s, height: s))
img.lockFocus()
let rect = NSRect(x: 0, y: 0, width: s, height: s)

// Full-bleed accent gradient (oklch(64.6% .222 41.116) ≈ #EA580C).
NSGradient(colors: [NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1),
                    NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 1)])?
    .draw(in: rect, angle: -90)

// White paw centered.
let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.52, weight: .bold)
    .applying(.init(paletteColors: [.white]))
if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let ps = paw.size
    paw.draw(in: NSRect(x: (s - ps.width) / 2, y: (s - ps.height) / 2, width: ps.width, height: ps.height))
}
img.unlockFocus()

if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("✅ wrote \(out)")
}
