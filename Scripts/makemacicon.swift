// macOS-style app icon: rounded squircle + drop shadow on transparent canvas.
// Run: swift Scripts/makemacicon.swift <output.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "meetpaw-macicon.png"
let canvas: CGFloat = 1024
let img = NSImage(size: NSSize(width: canvas, height: canvas))
img.lockFocus()
let ctx = NSGraphicsContext.current!

// macOS icon proportions: ~82% squircle with padding, continuous-ish corners.
let side = canvas * 0.816
let origin = (canvas - side) / 2
let iconRect = NSRect(x: origin, y: origin, width: side, height: side)
let radius = side * 0.2237   // Apple's superellipse corner ratio
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

// Drop shadow under the squircle.
ctx.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.shadowBlurRadius = canvas * 0.045
shadow.shadowOffset = NSSize(width: 0, height: -canvas * 0.016)
shadow.set()
NSColor.white.setFill()        // shape to cast the shadow
squircle.fill()
ctx.restoreGraphicsState()

// Accent gradient fill (oklch(64.6% .222 41.116) ≈ #EA580C), clipped to squircle.
ctx.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1),
                    NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 1)])?
    .draw(in: iconRect, angle: -90)

// Subtle top highlight for depth, like real macOS icons.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])?
    .draw(in: NSRect(x: iconRect.minX, y: iconRect.midY, width: side, height: side / 2), angle: -90)
ctx.restoreGraphicsState()

// White paw centered.
let cfg = NSImage.SymbolConfiguration(pointSize: side * 0.52, weight: .bold)
    .applying(.init(paletteColors: [.white]))
if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let ps = paw.size
    paw.draw(in: NSRect(x: (canvas - ps.width) / 2, y: (canvas - ps.height) / 2,
                        width: ps.width, height: ps.height))
}
img.unlockFocus()

if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out))
    print("✅ wrote \(out)")
}
