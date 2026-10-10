import AppKit
import SwiftUI

/// Owns the menu-bar status item and the popover.
/// Left-click  → instant meeting (generate + copy + show link widget).
/// Right-click / control-click → open the drawer without creating anything.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "MeetPaw")
            button.image?.isTemplate = true
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        popover.behavior = .transient
        let host = NSHostingController(rootView: MenuContent(model: model))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    @objc private func handleClick() {
        if popover.isShown { popover.performClose(nil); return }

        let event = NSApp.currentEvent
        let isSecondary = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true

        // Left-click while signed in = one-click instant meeting.
        if !isSecondary && model.isSignedIn && !model.creatingLink {
            model.newInstantMeeting()
        }
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
