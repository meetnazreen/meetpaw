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
    case invalidGrant          // refresh token dead → must re-sign-in
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Add credentials first."
        case .invalidGrant:  return "Session expired. Please sign in again."
        case .server(let m): return m
        }
    }
}

/// Provider-agnostic OAuth 2.0 installed-app flow (PKCE + loopback redirect).
actor OAuthClient {
    let provider: Provider
    private let config: OAuthConfig
    private var token: StoredToken?

    init(_ provider: Provider) {
        self.provider = provider
        self.config = provider.oauth
        if let data = Keychain.load(account: provider.keychainAccount) {
            token = try? JSONDecoder().decode(StoredToken.self, from: data)
        }
    }

    var isSignedIn: Bool { token != nil }
    var hasCredentials: Bool { Credentials.load(provider) != nil }

    func signOut() {
        token = nil
        Keychain.clear(account: provider.keychainAccount)
    }

    func accessToken() async throws -> String {
        guard let creds = Credentials.load(provider) else { throw AuthError.noCredentials }
        guard var tok = token else { throw AuthError.invalidGrant }
        if tok.isExpired {
            tok = try await refresh(tok, creds: creds)
            persist(tok)
        }
        return tok.accessToken
    }

    // MARK: Sign in

    func signIn() async throws {
        guard let creds = Credentials.load(provider) else { throw AuthError.noCredentials }

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.s256(verifier)
        let state = Self.randomURLSafe(16)

        let listener = try LoopbackListener(port: config.fixedPort)
        let port = try await listener.start()
        // The registered redirect_uri (HTTPS forwarding page for Zoom), else loopback.
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

        let tok = try await exchange(code: code, verifier: verifier, redirect: redirect, creds: creds)
        persist(tok)
    }

    // MARK: Token endpoints

    private func exchange(code: String, verifier: String, redirect: String, creds: Credentials) async throws -> StoredToken {
        var body: [String: String] = [
            "code": code,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
        ]
        if config.usePKCE { body["code_verifier"] = verifier }
        if config.sendScopeOnToken { body["scope"] = config.scopes.joined(separator: " ") }
        let json = try await postToken(body, creds: creds)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            throw AuthError.server("Malformed token response.")
        }
        return StoredToken(accessToken: access, refreshToken: refresh,
                           expiry: Date().addingTimeInterval(expiresIn(json)))
    }

    private func refresh(_ tok: StoredToken, creds: Credentials) async throws -> StoredToken {
        var body: [String: String] = [
            "refresh_token": tok.refreshToken,
            "grant_type": "refresh_token",
        ]
        if config.sendScopeOnToken { body["scope"] = config.scopes.joined(separator: " ") }
        let json = try await postToken(body, creds: creds)
        guard let access = json["access_token"] as? String else {
            throw AuthError.server("Malformed refresh response.")
        }
        // Zoom and Microsoft rotate the refresh token; Google keeps it.
        let newRefresh = (json["refresh_token"] as? String) ?? tok.refreshToken
        return StoredToken(accessToken: access, refreshToken: newRefresh,
                           expiry: Date().addingTimeInterval(expiresIn(json)))
    }

    private func expiresIn(_ json: [String: Any]) -> TimeInterval {
        (json["expires_in"] as? Double) ?? 3600
    }

    private func postToken(_ fields: [String: String], creds: Credentials) async throws -> [String: Any] {
        var fields = fields
        var req = URLRequest(url: URL(string: config.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        switch config.clientAuth {
        case .basicHeader:
            let secret = creds.clientSecret ?? ""
            let basic = Data("\(creds.clientID):\(secret)".utf8).base64EncodedString()
            req.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        case .body:
            fields["client_id"] = creds.clientID
            if let secret = creds.clientSecret { fields["client_secret"] = secret }
        }
        req.httpBody = fields.map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&").data(using: .utf8)

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

    private func persist(_ tok: StoredToken) {
        token = tok
        if let data = try? JSONEncoder().encode(tok) {
            Keychain.save(data, account: provider.keychainAccount)
        }
    }

    // MARK: PKCE helpers

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
