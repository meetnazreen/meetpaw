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

    /// A round avatar pre-rasterized to an exact pixel size — safe inside
    /// `Menu` labels (which otherwise ignore a SwiftUI image's frame).
    static func avatarImage(_ p: Provider, size: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: size, height: size))
        out.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: rect).fill()
        NSBezierPath(ovalIn: rect).addClip()
        if let logo = image(p) {
            let s = logo.size
            if p.avatarFills {
                let scale = max(size / s.width, size / s.height) * 1.14
                let w = s.width * scale, h = s.height * scale
                logo.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h),
                          from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                let box = size * 0.64
                let scale = min(box / s.width, box / s.height)
                let w = s.width * scale, h = s.height * scale
                logo.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h),
                          from: .zero, operation: .sourceOver, fraction: 1)
            }
        }
        out.unlockFocus()
        return out
    }

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
    // Fill only the provider's own full-bleed asset (Zoom); sign-in glyph
    // overrides (google_g, microsoft_logo) always fit.
    private var fills: Bool {
        provider.avatarFills && (resource == nil || resource == provider.logoResource)
    }

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

    var subtitle = "Connect Google, Zoom, or Microsoft Teams to start and join meetings."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
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
        let atCap = hasCreds && !model.canAddAccount(provider)
        Button {
            if hasCreds { model.addAccount(provider) } else { model.openCredentialsFolder() }
        } label: {
            HStack(spacing: 12) {
                ProviderLogoView(provider: provider, size: 34, resource: provider.signInLogoResource)
                VStack(alignment: .leading, spacing: 2) {
                    Text(atCap ? "\(provider.signInName) — max \(AppModel.maxAccountsPerProvider) accounts"
                         : hasCreds ? "Sign in with \(provider.signInName)"
                         : "Add \(provider.signInName) credentials…")
                        .fontWeight(.medium)
                    Text(hasCreds ? provider.signInBlurb
                         : "Add your \(provider.signInName) OAuth credentials to connect.")
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if !hasCreds { Image(systemName: "folder").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .glassCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .disabled(atCap)
        .opacity(atCap ? 0.5 : 1)
    }
}
