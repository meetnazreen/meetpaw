import Foundation
import Network
import CryptoKit
import AppKit

struct StoredToken: Codable {
    var accessToken: String
    var refreshToken: String
    var expiry: Date
    var isExpired: Bool { Date() >= expiry.addingTimeInterval(-60) }
}

enum AuthError: Error, LocalizedError {
    case noCredentials
    case invalidGrant
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Add credentials first."
        case .invalidGrant:  return "Session expired. Please sign in again."
        case .server(let m): return m
        }
    }
}

/// One signed-in account's token holder. OAuth flow + identity lookup are
/// static (they run before an account id exists).
actor OAuthClient {
    let provider: Provider
    let keychainKey: String        // == Account.id
    private var token: StoredToken?

    init(provider: Provider, keychainKey: String) {
        self.provider = provider
        self.keychainKey = keychainKey
        if let data = Keychain.load(account: keychainKey) {
            token = try? JSONDecoder().decode(StoredToken.self, from: data)
        }
    }

    var isSignedIn: Bool { token != nil }

    func signOut() {
        token = nil
        Keychain.clear(account: keychainKey)
    }

    func accessToken() async throws -> String {
        guard let creds = Credentials.load(provider) else { throw AuthError.noCredentials }
        guard var tok = token else { throw AuthError.invalidGrant }
        if tok.isExpired {
            tok = try await Self.refresh(tok, provider: provider, creds: creds)
            token = tok
            if let data = try? JSONEncoder().encode(tok) { Keychain.save(data, account: keychainKey) }
        }
        return tok.accessToken
    }

    // MARK: - Static OAuth flow (no persistence)

    /// Runs the full interactive OAuth and returns the token.
    static func authorize(provider: Provider) async throws -> StoredToken {
        guard let creds = Credentials.load(provider) else { throw AuthError.noCredentials }
        let config = provider.oauth

        let verifier = randomURLSafe(64)
        let challenge = s256(verifier)
        let state = randomURLSafe(16)

        let listener = try LoopbackListener(port: config.fixedPort)
        let port = try await listener.start()
        let redirect = config.redirectOverride ?? "http://\(config.redirectHost):\(port)"

        var comps = URLComponents(string: config.authURL)!
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: creds.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
        ]
        if config.usePKCE {
            items.append(.init(name: "code_challenge", value: challenge))
            items.append(.init(name: "code_challenge_method", value: "S256"))
        }
        for (k, v) in config.extraAuthParams { items.append(.init(name: k, value: v)) }
        comps.queryItems = items
        NSWorkspace.shared.open(comps.url!)

        let callback = try await listener.waitForCallback()
        guard callback.state == state else { throw AuthError.server("State mismatch (possible CSRF).") }
        guard let code = callback.code else {
            throw AuthError.server(callback.error ?? "No authorization code returned.")
        }
        return try await exchange(code: code, verifier: verifier, redirect: redirect,
                                  provider: provider, creds: creds)
    }

    /// Looks up the account's email (identity) for display + dedupe.
    static func identity(provider: Provider, token: StoredToken) async -> String {
        switch provider {
        case .google:
            if let e = try? await getJSON("https://www.googleapis.com/oauth2/v3/userinfo",
                                          token.accessToken)["email"] as? String { return e }
            if let id = try? await getJSON("https://www.googleapis.com/calendar/v3/calendars/primary",
                                           token.accessToken)["id"] as? String { return id }
            return "Google account"
        case .microsoft:
            if let j = try? await getJSON("https://graph.microsoft.com/v1.0/me", token.accessToken) {
                return (j["mail"] as? String) ?? (j["userPrincipalName"] as? String) ?? "Microsoft account"
            }
            return "Microsoft account"
        case .zoom:
            if let j = try? await getJSON("https://api.zoom.us/v2/users/me", token.accessToken),
               let e = j["email"] as? String { return e }
            return "Zoom account"
        }
    }

    // MARK: - Token endpoints (static)

    private static func exchange(code: String, verifier: String, redirect: String,
                                 provider: Provider, creds: Credentials) async throws -> StoredToken {
        let config = provider.oauth
        var body: [String: String] = [
            "code": code, "redirect_uri": redirect, "grant_type": "authorization_code",
        ]
        if config.usePKCE { body["code_verifier"] = verifier }
        if config.sendScopeOnToken { body["scope"] = config.scopes.joined(separator: " ") }
        let json = try await postToken(body, provider: provider, creds: creds)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw AuthError.server("Malformed token response.")
        }
        return StoredToken(accessToken: access, refreshToken: refresh,
                           expiry: Date().addingTimeInterval(expiresIn(json)))
    }

    private static func refresh(_ tok: StoredToken, provider: Provider, creds: Credentials) async throws -> StoredToken {
        let config = provider.oauth
        var body: [String: String] = ["refresh_token": tok.refreshToken, "grant_type": "refresh_token"]
        if config.sendScopeOnToken { body["scope"] = config.scopes.joined(separator: " ") }
        let json = try await postToken(body, provider: provider, creds: creds)
        guard let access = json["access_token"] as? String else {
            throw AuthError.server("Malformed refresh response.")
        }
        let newRefresh = (json["refresh_token"] as? String) ?? tok.refreshToken   // Zoom/MS rotate
        return StoredToken(accessToken: access, refreshToken: newRefresh,
                           expiry: Date().addingTimeInterval(expiresIn(json)))
    }

    private static func expiresIn(_ json: [String: Any]) -> TimeInterval {
        (json["expires_in"] as? Double) ?? 3600
    }

    private static func postToken(_ fields: [String: String], provider: Provider, creds: Credentials) async throws -> [String: Any] {
        let config = provider.oauth
        var fields = fields
        var req = URLRequest(url: URL(string: config.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        switch config.clientAuth {
        case .basicHeader:
            let basic = Data("\(creds.clientID):\(creds.clientSecret ?? "")".utf8).base64EncodedString()
            req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        case .body:
            fields["client_id"] = creds.clientID
            if let secret = creds.clientSecret { fields["client_secret"] = secret }
        }
        req.httpBody = fields.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            if (json["error"] as? String) == "invalid_grant" { throw AuthError.invalidGrant }
            throw AuthError.server(json["error_description"] as? String
                                   ?? json["error"] as? String
                                   ?? "Token request failed (\(http.statusCode)).")
        }
        return json
    }

    private static func getJSON(_ url: String, _ token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.server("identity lookup failed")
        }
        return json
    }

    // MARK: - PKCE helpers

    private static func randomURLSafe(_ n: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return Data(bytes).base64URL()
    }
    private static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL()
    }
    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

extension Data {
    func base64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
