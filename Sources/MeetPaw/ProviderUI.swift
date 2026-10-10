import SwiftUI
import AppKit

/// Loads each provider's logo SVG once (user drops them in Resources);
/// falls back to an SF Symbol if the file isn't there yet.
enum ProviderLogo {
    private static var cache: [String: NSImage] = [:]
    static func image(named resource: String) -> NSImage? {
        if let c = cache[resource] { return c }
        for ext in ["svg", "png"] {
            if let url = Bundle.module.url(forResource: resource, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                cache[resource] = img
                return img
            }
        }
        return nil
    }
    static func image(_ p: Provider) -> NSImage? { image(named: p.logoResource) }

    /// Small, aspect-correct image for native menu items.
    static func menuIcon(_ p: Provider) -> Image? {
        guard let img = image(p) else { return nil }
        let box: CGFloat = 16
        let s = img.size
        let scale = min(box / s.width, box / s.height)
        let w = s.width * scale, h = s.height * scale
        let copy = NSImage(size: NSSize(width: box, height: box))
        copy.lockFocus()
        img.draw(in: NSRect(x: (box - w) / 2, y: (box - h) / 2, width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: 1)
        copy.unlockFocus()
        return Image(nsImage: copy)
    }
}

/// Round avatar: the provider logo fills the circle (white backs any transparency).
struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 20
    var resource: String? = nil     // override (e.g. Google "G" on sign-in)

    private var logo: NSImage? {
        ProviderLogo.image(named: resource ?? provider.logoResource)
    }
    // A custom resource (the G favicon) is a glyph → fit; only Zoom fills.
    private var fills: Bool { resource == nil && provider.avatarFills }

    var body: some View {
        ZStack {
            Circle().fill(.white)
            if let logo {
                if fills {
                    Image(nsImage: logo).resizable().scaledToFill().scaleEffect(1.14)
                } else {
                    Image(nsImage: logo).resizable().scaledToFit()
                        .frame(width: size * 0.64, height: size * 0.64)
                }
            } else {
                Image(systemName: provider.fallbackSymbol)
                    .font(.system(size: size * 0.5)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.black.opacity(0.06)))
    }
}

/// Simple account list: small avatar + email. "All accounts" + each one.
struct AccountSwitcher: View {
    @Bindable var model: AppModel
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            row(id: nil, title: "All accounts", avatar: nil)
            ForEach(model.accounts) { account in
                row(id: account.id, title: account.email,
                    avatar: AnyView(ProviderLogoView(provider: account.provider, size: 20)))
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func row(id: String?, title: String, avatar: AnyView?) -> some View {
        let selected = model.selectedAccountID == id
        Button {
            model.selectedAccountID = id
            onSelect()
        } label: {
            HStack(spacing: 8) {
                if let avatar { avatar } else { Color.clear.frame(width: 20, height: 20) }
                Text(title).lineLimit(1)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.caption).foregroundStyle(.tint) }
            }
            .padding(.vertical, 6).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Sign-in / add-account screen: one button per provider.
struct ProviderSignIn: View {
    @Bindable var model: AppModel
    var title = "Sign in to get started"

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.callout).foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Provider.allCases) { provider in
                row(provider)
            }
        }
        .padding(16)
        .disabled(model.signingIn)
        .opacity(model.signingIn ? 0.6 : 1)
    }

    @ViewBuilder
    private func row(_ provider: Provider) -> some View {
        let hasCreds = model.hasCredentials(provider)
        Button {
            if hasCreds { model.addAccount(provider) } else { model.openCredentialsFolder() }
        } label: {
            HStack(spacing: 10) {
                ProviderLogoView(provider: provider, size: 28, resource: provider.signInLogoResource)
                Text(hasCreds ? "Sign in with \(provider.signInName)" : "Add \(provider.signInName) credentials…")
                    .fontWeight(.medium)
                Spacer()
                if !hasCreds {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .glassCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}
