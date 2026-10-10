import SwiftUI
import AppKit

/// Loads each provider's logo SVG once (user drops them in Resources);
/// falls back to an SF Symbol if the file isn't there yet.
enum ProviderLogo {
    private static var cache: [Provider: NSImage] = [:]
    static func image(_ p: Provider) -> NSImage? {
        if let c = cache[p] { return c }
        for ext in ["svg", "png"] {
            if let url = Bundle.module.url(forResource: p.logoResource, withExtension: ext),
               let img = NSImage(contentsOf: url) {
                cache[p] = img
                return img
            }
        }
        return nil
    }
}

/// Round white badge with the provider logo centered inside.
struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 20
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Group {
                if let logo = ProviderLogo.image(provider) {
                    Image(nsImage: logo).resizable().scaledToFit()
                } else {
                    Image(systemName: provider.fallbackSymbol)
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.black.opacity(0.06)))
    }
}

/// Account switcher: avatar + email, platform below. "All accounts" + each one.
struct AccountSwitcher: View {
    @Bindable var model: AppModel
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            allRow
            ForEach(model.accounts) { account in
                row(id: account.id,
                    avatar: AnyView(ProviderLogoView(provider: account.provider, size: 34)),
                    title: account.email, subtitle: account.provider.name)
            }
        }
        .padding(12)
    }

    private var allRow: some View {
        row(id: nil,
            avatar: AnyView(
                ZStack {
                    Circle().fill(.white)
                    Image(systemName: "person.2.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                }.frame(width: 34, height: 34).overlay(Circle().strokeBorder(.black.opacity(0.06)))),
            title: "All accounts",
            subtitle: "\(model.accounts.count) account\(model.accounts.count == 1 ? "" : "s")")
    }

    @ViewBuilder
    private func row(id: String?, avatar: AnyView, title: String, subtitle: String) -> some View {
        let selected = model.selectedAccountID == id
        Button {
            model.selectedAccountID = id
            onSelect()
        } label: {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: 12)
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
                ProviderLogoView(provider: provider, size: 28)
                Text(hasCreds ? "Sign in with \(provider.name)" : "Add \(provider.name) credentials…")
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
