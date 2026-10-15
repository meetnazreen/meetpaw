// DMG window background — white with a light grid, a soft orange glow behind a
// centered "Install MeetPaw" title, and a centered drag instruction.
// Run: swift Scripts/makedmgbg.swift <out.png> [scale]   (scale 1 or 2)
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmgbg.png"
let s: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 1) : 1
let W = 620 * s, H = 420 * s
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// White ground.
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// Light grid.
NSColor(white: 0.93, alpha: 1).setStroke()
let grid = NSBezierPath(); grid.lineWidth = 1
let step = 31 * s
var gx: CGFloat = 0; while gx <= W { grid.move(to: .init(x: gx, y: 0)); grid.line(to: .init(x: gx, y: H)); gx += step }
var gy: CGFloat = 0; while gy <= H { grid.move(to: .init(x: 0, y: gy)); grid.line(to: .init(x: W, y: gy)); gy += step }
grid.stroke()

let titleTop = 78 * s

// Centered text with its vertical center at yFromTop.
func text(_ str: String, size: CGFloat, color: NSColor, weight: NSFont.Weight, yFromTop: CGFloat) {
  let ps = NSMutableParagraphStyle(); ps.alignment = .center
  let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: ps]
  let ns = NSString(string: str)
  let h = ns.size(withAttributes: attr).height
  ns.draw(in: NSRect(x: 0, y: (H - yFromTop) - h/2, width: W, height: h), withAttributes: attr)
}
text("Install MeetPaw", size: 30 * s, color: NSColor(white: 0.1, alpha: 1), weight: .bold, yFromTop: titleTop)
text("Drag the MeetPaw icon onto the Applications folder.", size: 13.5 * s, color: NSColor(white: 0.5, alpha: 1), weight: .medium, yFromTop: 116 * s)

img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
  try? png.write(to: URL(fileURLWithPath: out)); print("✅ wrote \(out) @\(s)x")
}
