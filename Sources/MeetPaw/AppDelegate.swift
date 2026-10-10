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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "MeetPaw")
            button.image?.isTemplate = true
            button.wantsLayer = true
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
            toggle(drawerPopover)
            return
        }

        // Left-click signed in → paw step + instant meeting in the compact widget.
        drawerPopover.performClose(nil)
        animatePaw()
        model.newInstantMeeting()
        show(linkPopover)
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

    // MARK: Paw-step animation

    /// A quick two-step "paw tap": tilt + bounce left, then right.
    private func animatePaw() {
        guard let layer = statusItem.button?.layer else { return }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)   // rotate/scale about center

        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        tilt.values = [0, -0.22, 0.22, -0.12, 0]
        tilt.keyTimes = [0, 0.25, 0.55, 0.8, 1]

        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 0.82, 1.12, 0.96, 1.0]
        bounce.keyTimes = [0, 0.25, 0.55, 0.8, 1]

        let group = CAAnimationGroup()
        group.animations = [tilt, bounce]
        group.duration = 0.45
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pawStep")
    }
}
