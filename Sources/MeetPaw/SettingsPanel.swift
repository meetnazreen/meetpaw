import SwiftUI
import AppKit

/// Custom hamburger panel — full layout control (right-aligned shortcut badges,
/// avatars, leading checkmarks) that a native menu can't provide.
struct SettingsPanel: View {
    @Bindable var model: AppModel
    let addAccount: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: onClose) { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 4)
            row(icon: "plus.circle.fill", title: "Add account…", tint: .meetpaw) { onClose(); addAccount() }
            row(icon: "arrow.clockwise", title: "Refresh") { Task { await model.refresh() } }

            if !model.accounts.isEmpty {
                header("ACCOUNTS")
                ForEach(model.accounts) { a in
                    HStack(spacing: 8) {
                        ProviderLogoView(provider: a.provider, size: 20)
                        Text(a.email).lineLimit(1)
                        Spacer()
                        Button("Sign out") { model.signOut(a) }
                            .buttonStyle(.plain).foregroundStyle(.red).font(.callout)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 12)
                }
            }

            if model.signedProviders.count > 1 {
                header("DEFAULT MEETING PROVIDER")
                ForEach(model.signedProviders) { p in
                    Button { model.setDefaultProvider(p) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.caption).foregroundStyle(.tint)
                                .frame(width: 14)
                                .opacity(model.defaultProvider == p ? 1 : 0)
                            ProviderLogoView(provider: p, size: 20)
                            Text(p.name)
                            Spacer()
                            shortcutBadge(shortcut(p))
                        }
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            header("SETTINGS")
            HStack {
                Toggle(isOn: $model.launchAtLogin) {
                    Label("Launch at login", systemImage: "power")
                }
                .toggleStyle(.checkbox)
            }
            .padding(.vertical, 4).padding(.horizontal, 12)
            row(icon: "xmark.circle", title: "Quit MeetPaw") { NSApp.terminate(nil) }
        }
        .padding(.vertical, 8)
    }

    // MARK: Pieces

    @ViewBuilder
    private func row(icon: String, title: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.caption2).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.15)))
    }

    private func shortcut(_ p: Provider) -> String {
        switch p {        // ⌘ first, per request
        case .google: return "⌘⇧M"
        case .zoom: return "⌘⇧Z"
        case .microsoft: return "⌘⇧T"
        }
    }
}
