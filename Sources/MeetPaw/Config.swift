import Foundation

/// Google OAuth client credentials. Not secret-sensitive for a "Desktop app"
/// client type (the secret isn't confidential in installed apps), but we keep
/// it out of the repo anyway so every user wires their own GCP project.
struct Credentials: Codable {
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }

    /// Looked up at ~/.config/meetpaw/credentials.json
    static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".config/meetpaw/credentials.json")
    }

    static func load() -> Credentials? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        // Supports either a bare {client_id, client_secret} or Google's
        // downloaded {"installed": {...}} client_secret_*.json shape.
        if let c = try? JSONDecoder().decode(Credentials.self, from: data) {
            return c
        }
        struct Wrapper: Codable { let installed: Credentials }
        return try? JSONDecoder().decode(Wrapper.self, from: data).installed
    }
}
