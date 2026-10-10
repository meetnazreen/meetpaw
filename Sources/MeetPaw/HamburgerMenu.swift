import SwiftUI
import AppKit

/// The hamburger as a real AppKit NSMenu — the only way to get native
/// right-aligned keyboard shortcuts (keyEquivalent) alongside checkmarks + logos.
struct HamburgerMenu: NSViewRepresentable {
    var model: AppModel
    var onAddAccount: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Menu")
        let button = NSButton(image: image ?? NSImage(), target: context.coordinator,
                              action: #selector(Coordinator.open(_:)))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.model = model
        context.coordinator.onAddAccount = onAddAccount
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model, onAddAccount: onAddAccount) }

    @MainActor
    final class Coordinator: NSObject {
        var model: AppModel
        var onAddAccount: () -> Void
        init(model: AppModel, onAddAccount: @escaping () -> Void) {
            self.model = model; self.onAddAccount = onAddAccount
        }

        @objc func open(_ sender: NSButton) {
            let menu = build()
            menu.popUp(positioning: nil,
                       at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
        }

        @objc func fire(_ item: NSMenuItem) {
            (item.representedObject as? () -> Void)?()
        }

        private func build() -> NSMenu {
            let menu = NSMenu()
            let add = item("Add account…", symbol: "plus.circle.fill", accent: true) { [self] in onAddAccount() }
            menu.addItem(add)
            if model.isSignedIn {
                menu.addItem(item("Refresh", symbol: "arrow.clockwise") { [self] in Task { await model.refresh() } })
            }

            if !model.accounts.isEmpty {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: "Accounts"))
                for a in model.accounts {
                    // No avatar in the Accounts section.
                    menu.addItem(item("\(a.email) — Sign out") { [self] in model.signOut(a) })
                }
            }

            if model.signedProviders.count > 1 {
                menu.addItem(.separator())
                menu.addItem(.sectionHeader(title: "Default meeting provider"))
                for p in model.signedProviders {
                    let it = item(p.name, image: ProviderLogo.avatarImage(p, size: 16)) { [self] in model.setDefaultProvider(p) }
                    it.state = model.defaultProvider == p ? .on : .off
                    it.keyEquivalent = key(for: p)
                    it.keyEquivalentModifierMask = [.command, .shift]   // renders ⇧⌘<key>, right-aligned
                    menu.addItem(it)
                }
            }

            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Settings"))
            let launch = item("Launch at login", symbol: "power") { [self] in model.launchAtLogin.toggle() }
            launch.state = model.launchAtLogin ? .on : .off
            menu.addItem(launch)
            menu.addItem(item("Quit MeetPaw", symbol: "xmark.circle") { NSApp.terminate(nil) })
            return menu
        }

        private func item(_ title: String, symbol: String? = nil, image: NSImage? = nil,
                          accent: Bool = false, action: @escaping () -> Void) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: #selector(fire(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = action
            if let image { it.image = image }
            else if let symbol {
                var img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                if accent {
                    let cfg = NSImage.SymbolConfiguration(paletteColors: [NSColor(Color.meetpaw)])
                    img = img?.withSymbolConfiguration(cfg)
                }
                it.image = img
            }
            if accent {
                it.attributedTitle = NSAttributedString(string: title, attributes: [
                    .foregroundColor: NSColor(Color.meetpaw),
                    .font: NSFont.menuFont(ofSize: 0),
                ])
            }
            return it
        }

        private func key(for p: Provider) -> String {
            switch p {
            case .google: return "m"
            case .zoom: return "z"
            case .microsoft: return "t"
            }
        }
    }
}
