import SwiftUI
import AppKit

/// Loads each provider's logo SVG once (user drops them in Resources);
/// falls back to an SF Symbol if the file isn't there yet.
enum ProviderLogo {
    private static var cache: [Provider: NSImage] = [:]
    static func image(_ p: Provider) -> NSImage? {
        if let c = cache[p] { return c }
        guard let url = Bundle.module.url(forResource: p.logoResource, withExtension: "svg"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[p] = img
        return img
    }
}

struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 20
    var body: some View {
        if let logo = ProviderLogo.image(provider) {
            Image(nsImage: logo).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: provider.fallbackSymbol)
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Signed-out screen: one button per provider.
struct ProviderSignIn: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            Text("Sign in to get started")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.bottom, 2)
            ForEach(Provider.allCases) { provider in
                row(provider)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func row(_ provider: Provider) -> some View {
        let hasCreds = model.hasCredentials(provider)
        Button {
            if hasCreds { model.signIn(provider) } else { model.openCredentialsFolder() }
        } label: {
            HStack(spacing: 10) {
                ProviderLogoView(provider: provider, size: 20)
                Text(hasCreds ? "Sign in with \(provider.name)" : "Add \(provider.name) credentials…")
                    .fontWeight(.medium)
                Spacer()
                if !hasCreds {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
