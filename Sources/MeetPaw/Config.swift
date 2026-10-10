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
        guard let data = try? Data(contentsOf: fileURL(for: provider)) else { return nil }
        // Accept a bare {client_id, client_secret?} or Google's {"installed": {...}}.
        if let c = decode(data) { return c }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let inner = obj["installed"] as? [String: Any],
           let d = try? JSONSerialization.data(withJSONObject: inner) {
            return decode(d)
        }
        return nil
    }

    private static func decode(_ data: Data) -> Credentials? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = obj["client_id"] as? String else { return nil }
        return Credentials(clientID: id, clientSecret: obj["client_secret"] as? String)
    }
}
