// Open Graph share image (1200×630) for MeetPaw.
// Run: swift Scripts/makeog.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "og.png"
let W: CGFloat = 1200, H: CGFloat = 630
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// White ground.
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Soft orange glow top-left.
let glow = NSGradient(colors: [NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 0.22),
                               NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 0)])
glow?.draw(in: NSBezierPath(ovalIn: NSRect(x: -180, y: H-520, width: 900, height: 820)), relativeCenterPosition: .zero)

// App-icon squircle with paw, left.
let iconSize: CGFloat = 150
let iconRect = NSRect(x: 96, y: H/2 - iconSize/2, width: iconSize, height: iconSize)
let squircle = NSBezierPath(roundedRect: iconRect, xRadius: iconSize*0.24, yRadius: iconSize*0.24)
NSGradient(colors: [NSColor(calibratedRed: 0.976, green: 0.451, blue: 0.086, alpha: 1),
                    NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 1)])?.draw(in: squircle, angle: -90)
let pcfg = NSImage.SymbolConfiguration(pointSize: iconSize*0.52, weight: .bold).applying(.init(paletteColors: [.white]))
if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?.withSymbolConfiguration(pcfg) {
    let ps = paw.size
    paw.draw(in: NSRect(x: iconRect.midX - ps.width/2, y: iconRect.midY - ps.height/2, width: ps.width, height: ps.height))
}

// Text block, right of icon.
let ink = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1)
let muted = NSColor(calibratedRed: 0.42, green: 0.45, blue: 0.50, alpha: 1)
let tx: CGFloat = 96
func draw(_ s: String, font: NSFont, color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .left
    NSString(string: s).draw(in: NSRect(x: tx, y: y, width: W - tx*2, height: 200),
        withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
}
draw("MeetPaw", font: .systemFont(ofSize: 58, weight: .bold), color: ink, y: H/2 + 86)
draw("Instant meeting links, in one click.", font: .systemFont(ofSize: 52, weight: .semibold), color: ink, y: H/2 - 10)
draw("Google Meet · Zoom · Microsoft Teams — in your menu bar.", font: .systemFont(ofSize: 30, weight: .regular), color: muted, y: H/2 - 92)

img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out)); print("✅ wrote \(out)")
}
