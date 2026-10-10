import Foundation

/// A meeting provider MeetPaw can sign into.
enum Provider: String, CaseIterable, Identifiable, Codable, Hashable {
    case google, zoom, microsoft
    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google Meet"
        case .zoom: return "Zoom"
        case .microsoft: return "Microsoft Teams"
        }
    }

    /// SVG in Resources (the user drops these in); falls back to an SF Symbol.
    var logoResource: String {
        switch self {
        case .google: return "google"
        case .zoom: return "zoom"
        case .microsoft: return "teams"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .google: return "video.fill"
        case .zoom: return "video.circle.fill"
        case .microsoft: return "person.2.fill"
        }
    }

    /// Zoom's asset is a full-bleed app icon (fills the circle); the Meet and
    /// Teams logos are glyphs that need padding (fit).
    var avatarFills: Bool { self == .zoom }

    var keychainAccount: String { rawValue }
    var credentialsFile: String {
        switch self {
        case .google: return "credentials.json"   // unchanged, keeps existing sign-in
        case .zoom: return "zoom.json"
        case .microsoft: return "microsoft.json"
        }
    }

    var oauth: OAuthConfig {
        switch self {
        case .google:
            return OAuthConfig(
                authURL: "https://accounts.google.com/o/oauth2/v2/auth",
                tokenURL: "https://oauth2.googleapis.com/token",
                scopes: ["openid", "email",
                         "https://www.googleapis.com/auth/calendar.events",
                         "https://www.googleapis.com/auth/meetings.space.created"],
                redirectHost: "127.0.0.1", fixedPort: nil, usePKCE: true,
                clientAuth: .body, sendScopeOnToken: false,
                extraAuthParams: ["access_type": "offline", "prompt": "select_account consent"])
        case .zoom:
            return OAuthConfig(
                authURL: "https://zoom.us/oauth/authorize",
                tokenURL: "https://zoom.us/oauth/token",
                scopes: ["meeting:write:meeting"],          // granular user-managed scope
                redirectHost: "127.0.0.1", fixedPort: 8765, usePKCE: true,
                clientAuth: .basicHeader, sendScopeOnToken: false,
                extraAuthParams: [:],
                // Zoom rejects http loopback; use an HTTPS page that forwards
                // the code to the local listener on 127.0.0.1:8765.
                redirectOverride: "https://meetnazreen.github.io/meetpaw/oauth/zoom.html")
        case .microsoft:
            return OAuthConfig(
                authURL: "https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize",
                tokenURL: "https://login.microsoftonline.com/organizations/oauth2/v2.0/token",
                scopes: ["OnlineMeetings.ReadWrite", "Calendars.ReadWrite", "offline_access", "User.Read"],
                redirectHost: "localhost", fixedPort: nil, usePKCE: true,
                clientAuth: .body, sendScopeOnToken: true,
                extraAuthParams: ["prompt": "select_account"])
        }
    }
}

struct OAuthConfig {
    enum ClientAuth { case body, basicHeader }   // Zoom wants HTTP Basic
    let authURL: String
    let tokenURL: String
    let scopes: [String]
    let redirectHost: String        // "127.0.0.1" or "localhost"
    let fixedPort: Int?             // Zoom needs an exact registered port
    let usePKCE: Bool
    let clientAuth: ClientAuth
    let sendScopeOnToken: Bool      // Microsoft wants scope on the token request
    let extraAuthParams: [String: String]
    var redirectOverride: String? = nil   // HTTPS redirect that forwards to loopback
}
