import Foundation

/// OAuth client credentials for a provider. `clientSecret` is nil for public
/// clients (Microsoft desktop app).
struct Credentials {
    let clientID: String
    let clientSecret: String?

    static func dir() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/meetpaw")
    }

    static func fileURL(for provider: Provider) -> URL {
        dir().appending(path: provider.credentialsFile)
    }

    static func load(_ provider: Provider) -> Credentials? {
        // 1. A user-supplied file in ~/.config/meetpaw overrides the bundled default
        //    (lets people build from source with their own OAuth apps).
        if let data = try? Data(contentsOf: fileURL(for: provider)),
           let c = fromData(data) {
            return c
        }
        // 2. Credentials bundled with the official build (not committed to the repo).
        return bundled(provider)
    }

    /// Accept a bare {client_id, client_secret?} or Google's {"installed": {...}}.
    private static func fromData(_ data: Data) -> Credentials? {
        if let c = decode(data) { return c }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inner = obj["installed"] as? [String: Any],
           let d = try? JSONSerialization.data(withJSONObject: inner) {
            return decode(d)
        }
        return nil
    }

    /// Reads `credentials-bundled.json` shipped in the app bundle, keyed by
    /// provider ("google" / "zoom" / "microsoft"). Absent in source checkouts.
    private static func bundled(_ provider: Provider) -> Credentials? {
        guard let url = Bundle.module.url(forResource: "credentials-bundled", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = obj[provider.rawValue] as? [String: Any],
              let d = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
        return decode(d)
    }

    private static func decode(_ data: Data) -> Credentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["client_id"] as? String else { return nil }
        return Credentials(clientID: id, clientSecret: obj["client_secret"] as? String)
    }
}
