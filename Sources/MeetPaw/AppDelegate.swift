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

        // Left-click signed in → paw-walk animation + instant meeting widget.
        drawerPopover.performClose(nil)
        showPawSteps()
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

    // MARK: Paw-walk overlay

    /// A transient, click-through window under the menu-bar icon that plays the
    /// two-paw walk-in, then fades itself out.
    private func showPawSteps() {
        guard let buttonWindow = statusItem.button?.window else { return }
        let bf = buttonWindow.frame
        let size = NSSize(width: 120, height: 64)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.contentViewController = NSHostingController(rootView: PawStepView())
        panel.setFrameOrigin(NSPoint(x: bf.midX - size.width / 2, y: bf.minY - size.height))
        panel.orderFrontRegardless()

        // Hold, then fade the whole panel out and close it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.close() })
        }
    }
}
