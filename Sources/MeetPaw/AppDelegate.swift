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
    private var hotKeys: HotKeys?

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

        // Global hotkeys: ⌘⇧M Google Meet, ⌘⇧Z Zoom, ⌘⇧T Teams.
        hotKeys = HotKeys { [weak self] id in
            let provider: Provider = id == 1 ? .google : id == 2 ? .zoom : .microsoft
            self?.instantMeeting(provider: provider)
        }

        // Close the popovers when the user clicks in any other app/window.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopovers()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.closePopovers()
        }
        // After a sign-out (or other account change from the native menu), re-present
        // the drawer so the user always sees the updated state instead of a blank bar.
        NotificationCenter.default.addObserver(forName: .meetpawReopenDrawer,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.linkPopover.performClose(nil)
            self.show(self.drawerPopover)
        }
    }

    private func closePopovers() {
        if linkPopover.isShown { linkPopover.performClose(nil) }
        if drawerPopover.isShown { drawerPopover.performClose(nil) }
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

        // Left-click signed in → the menu-bar paw walks while generating; the
        // walk timer opens the widget the moment the link is ready.
        drawerPopover.performClose(nil)
        startWalking()
        model.newInstantMeeting()
    }

    /// Global hotkey → create an instant meeting with a specific provider.
    private func instantMeeting(provider: Provider) {
        guard model.hasAccount(provider) else { NSSound.beep(); return }
        NSApp.activate(ignoringOtherApps: true)   // bring the popover forward
        drawerPopover.performClose(nil)
        startWalking()
        model.newInstantMeeting(provider: provider)
        // The walk timer shows the link widget when the link is ready.
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
        // Key so the transient popover dismisses on outside click and text
        // fields accept input.
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: Menu-bar paw-walk (animate the status item image itself)

    /// Cycles the status-item image through two-paw "walking" frames while a
    /// meeting is being created, then restores the single paw.
    private func startWalking() {
        walkTimer?.invalidate()
        walkPhase = 0
        let started = Date()
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] timer in
            guard let self, let button = self.statusItem.button else { timer.invalidate(); return }
            self.walkPhase = (self.walkPhase + 1) % Self.walkFrames
            button.image = Self.walkFrame(phase: self.walkPhase)

            // Keep walking until the link is ready (or it fails), min ~0.5s so
            // the walk is visible, then stop exactly as the widget opens.
            let elapsed = Date().timeIntervalSince(started)
            let ready = self.model.createdLink != nil
            let failed = !self.model.creatingLink && self.model.createdLink == nil
            if elapsed > 0.5 && (ready || failed) {
                timer.invalidate(); self.walkTimer = nil
                button.image = Self.singlePaw()
                if ready { self.show(self.linkPopover) }
                else { self.show(self.drawerPopover) }   // surface the error
            }
        }
    }

    // Fixed icon canvas so the button width never changes (walk vs rest),
    // which keeps the anchored popover from shifting.
    private static let iconW: CGFloat = 30
    private static let iconH: CGFloat = 18

    /// The resting single paw, drawn centered in the fixed-width canvas.
    private static func singlePaw() -> NSImage {
        let img = NSImage(size: NSSize(width: iconW, height: iconH))
        img.lockFocus()
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "MeetPaw")?
            .withSymbolConfiguration(cfg) {
            let s = paw.size
            paw.draw(in: NSRect(x: (iconW - s.width) / 2, y: (iconH - s.height) / 2,
                                width: s.width, height: s.height))
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }

    static let walkFrames = 12

    /// One frame: two paws (left & right foot) rising upward through the icon
    /// and fading, staggered half a cycle apart so one is up while the other
    /// is down — a walking-up loop. No tilt.
    private static func walkFrame(phase: Int) -> NSImage {
        let w = iconW, h = iconH
        let t = CGFloat(phase) / CGFloat(walkFrames)

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        for i in 0..<2 {
            let p = (t + CGFloat(i) * 0.5).truncatingRemainder(dividingBy: 1) // 0 back → 1 forward
            let x: CGFloat = (i == 0) ? 8 : 22    // wider apart so they don't touch
            let y = 2 + p * (h - 4)
            let alpha = pow(sin(.pi * p), 0.6)    // fade in, hold, fade out
            let size = 7 + 9 * p                  // grows as the paw steps forward

            let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
            guard let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) else { continue }
            let s = paw.size
            paw.draw(in: NSRect(x: x - s.width / 2, y: y - s.height / 2, width: s.width, height: s.height),
                     from: .zero, operation: .sourceOver, fraction: alpha)
        }
        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
