// DMG window background (620x420 @2x) — white with a light grid, an arrow,
// and a drag-to-install instruction. Run: swift Scripts/makedmgbg.swift <out.png>
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmgbg.png"
let W: CGFloat = 1240, H: CGFloat = 840     // 620x420 at 2x
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()

// White ground.
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// Light grid.
NSColor(white: 0.93, alpha: 1).setStroke()
let grid = NSBezierPath(); grid.lineWidth = 1
let step: CGFloat = 62
var gx: CGFloat = 0; while gx <= W { grid.move(to: .init(x: gx, y: 0)); grid.line(to: .init(x: gx, y: H)); gx += step }
var gy: CGFloat = 0; while gy <= H { grid.move(to: .init(x: 0, y: gy)); grid.line(to: .init(x: W, y: gy)); gy += step }
grid.stroke()

// Arrow between the icons (icon row is at y_top=215 → y from bottom = H-430=410).
let cy = H - 430
let accent = NSColor(calibratedRed: 0.918, green: 0.345, blue: 0.047, alpha: 1)
accent.setStroke(); accent.setFill()
let shaft = NSBezierPath(); shaft.lineWidth = 12; shaft.lineCapStyle = .round
let ax0: CGFloat = 505, ax1: CGFloat = 720
shaft.move(to: .init(x: ax0, y: cy)); shaft.line(to: .init(x: ax1, y: cy)); shaft.stroke()
let head = NSBezierPath()
head.move(to: .init(x: ax1 + 34, y: cy))
head.line(to: .init(x: ax1 - 10, y: cy + 30))
head.line(to: .init(x: ax1 - 10, y: cy - 30))
head.close(); head.fill()

// Text (centered).
func text(_ s: String, size: CGFloat, color: NSColor, yTop: CGFloat, weight: NSFont.Weight) {
  let ps = NSMutableParagraphStyle(); ps.alignment = .center
  let h = size * 1.35
  NSString(string: s).draw(in: NSRect(x: 0, y: H - yTop - h, width: W, height: h),
    withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight),
                     .foregroundColor: color, .paragraphStyle: ps])
}
text("Install MeetPaw", size: 52, color: NSColor(white: 0.1, alpha: 1), yTop: 66, weight: .bold)
text("Drag the MeetPaw icon onto the Applications folder.", size: 29, color: NSColor(white: 0.5, alpha: 1), yTop: 700, weight: .medium)

img.unlockFocus()
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
  try? png.write(to: URL(fileURLWithPath: out)); print("✅ wrote \(out)")
}
