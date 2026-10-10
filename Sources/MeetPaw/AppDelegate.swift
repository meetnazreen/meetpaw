import AppKit
import SwiftUI
import QuartzCore

/// Owns the menu-bar status item and two popovers.
/// Left-click  → paw-step animation + instant meeting shown in a compact widget.
/// Right-click / control-click (or when signed out) → the full drawer.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let linkPopover = NSPopover()
    private let drawerPopover = NSPopover()
    private var walkTimer: Timer?
    private var walkPhase = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.singlePaw()
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        linkPopover.behavior = .transient
        let linkHost = NSHostingController(rootView: LinkWidget(model: model) { [weak self] in
            self?.linkPopover.performClose(nil)
        })
        linkHost.sizingOptions = [.preferredContentSize]
        linkPopover.contentViewController = linkHost

        drawerPopover.behavior = .transient
        let drawerHost = NSHostingController(rootView: MenuContent(model: model))
        drawerHost.sizingOptions = [.preferredContentSize]
        drawerPopover.contentViewController = drawerHost
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        // Right-click, control-click, or not yet signed in → the full drawer.
        if isSecondary || !model.isSignedIn {
            linkPopover.performClose(nil)
            let wasShown = drawerPopover.isShown
            toggle(drawerPopover)
            // Refresh the meetings list each time the drawer is opened.
            if !wasShown && model.isSignedIn {
                Task { await model.refresh() }
            }
            return
        }

        // Left-click signed in → the menu-bar paw walks while generating,
        // then the widget slides up.
        drawerPopover.performClose(nil)
        startWalking()
        model.newInstantMeeting()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self else { return }
            self.show(self.linkPopover)
        }
    }

    // MARK: Popover helpers

    private func toggle(_ popover: NSPopover) {
        if popover.isShown { popover.performClose(nil) } else { show(popover) }
    }

    private func show(_ popover: NSPopover) {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Menu-bar paw-walk (animate the status item image itself)

    /// Cycles the status-item image through two-paw "walking" frames while a
    /// meeting is being created, then restores the single paw.
    private func startWalking() {
        walkTimer?.invalidate()
        walkPhase = 0
        let started = Date()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] timer in
            guard let self, let button = self.statusItem.button else { timer.invalidate(); return }
            self.walkPhase = (self.walkPhase + 1) % Self.walkFrames
            button.image = Self.walkFrame(phase: self.walkPhase)
            // Stop once generation finishes (but play at least ~0.6s).
            if !self.model.creatingLink && Date().timeIntervalSince(started) > 0.6 {
                timer.invalidate(); self.walkTimer = nil
                button.image = Self.singlePaw()
            }
        }
    }

    /// The resting single-paw menu-bar image.
    private static func singlePaw() -> NSImage {
        let img = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "MeetPaw")!
        img.isTemplate = true
        return img
    }

    static let walkFrames = 10

    /// One frame of a forward-marching paw trail: three prints move left→right,
    /// each growing and brightening mid-stride then shrinking/fading, zig-zagging
    /// up and down with alternating tilt — like real footprints.
    private static func walkFrame(phase: Int) -> NSImage {
        let w: CGFloat = 30, h: CGFloat = 18
        let prints = 3
        let t = CGFloat(phase) / CGFloat(walkFrames)

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        for i in 0..<prints {
            // Progress of this print across the width (staggered + looping).
            let p = (t + CGFloat(i) / CGFloat(prints)).truncatingRemainder(dividingBy: 1)
            let bell = sin(.pi * p)               // 0 at edges, 1 mid-stride
            let x = 3 + p * (w - 6)
            let lift = (i % 2 == 0 ? 1 : -1) * 3 * bell   // alternating up/down gait
            let tilt: CGFloat = (i % 2 == 0 ? -16 : 16)
            let size = 8 + 7 * bell               // smaller at edges, bigger mid
            let alpha = 0.2 + 0.8 * bell

            let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { continue }

            NSGraphicsContext.saveGraphicsState()
            let xf = NSAffineTransform()
            xf.translateX(by: x, yBy: h / 2 + lift)
            xf.rotate(byDegrees: tilt)
            xf.concat()
            let s = paw.size
            paw.draw(in: NSRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height),
                     from: .zero, operation: .sourceOver, fraction: alpha)
            NSGraphicsContext.restoreGraphicsState()
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
