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
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.13, repeats: true) { [weak self] timer in
            guard let self, let button = self.statusItem.button else { timer.invalidate(); return }
            self.walkPhase = (self.walkPhase + 1) % 4
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

    /// One frame of the two-paw walk: two paws side by side, one stepping up
    /// (brighter) and one resting (dimmer), alternating by phase.
    private static func walkFrame(phase: Int) -> NSImage {
        let w: CGFloat = 26, h: CGFloat = 18
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(cfg)!

        // Per-phase (left, right) → (vertical lift, opacity).
        let steps: [((CGFloat, CGFloat), (CGFloat, CGFloat))] = [
            ((2, 1.0), (0, 0.45)),   // left steps
            ((0, 0.8), (0, 0.8)),    // both mid
            ((0, 0.45), (2, 1.0)),   // right steps
            ((0, 0.8), (0, 0.8)),    // both mid
        ]
        let (left, right) = steps[phase]

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        func place(cx: CGFloat, lift: CGFloat, alpha: CGFloat) {
            let s = paw.size
            let r = NSRect(x: cx - s.width / 2, y: (h - s.height) / 2 + lift,
                           width: s.width, height: s.height)
            paw.draw(in: r, from: .zero, operation: .sourceOver, fraction: alpha)
        }
        place(cx: 8, lift: left.0, alpha: left.1)
        place(cx: 18, lift: right.0, alpha: right.1)
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
