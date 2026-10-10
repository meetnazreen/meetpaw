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
        case .noCredentials: return "Add Google credentials first."
        case .invalidGrant:  return "Session expired. Please sign in again."
        case .server(let m): return m
        }
    }
}

/// OAuth 2.0 installed-app flow with PKCE + loopback redirect.
actor GoogleAuth {
    // calendar.events (read+write) rather than readonly: the instant-meeting
    // fallback (events.insert) needs write access when the Meet API 403s.
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.events",
        "https://www.googleapis.com/auth/meetings.space.created",
    ]

    private var token: StoredToken?

    init() {
        if let data = Keychain.load() {
            token = try? JSONDecoder().decode(StoredToken.self, from: data)
        }
    }

    var isSignedIn: Bool { token != nil }

    func signOut() {
        token = nil
        Keychain.clear()
    }

    /// Returns a valid access token, refreshing if needed.
    func accessToken() async throws -> String {
        guard let creds = Credentials.load() else { throw AuthError.noCredentials }
        guard var tok = token else { throw AuthError.invalidGrant }
        if tok.isExpired {
            tok = try await refresh(tok, creds: creds)
            persist(tok)
        }
        return tok.accessToken
    }

    // MARK: Sign in

    func signIn() async throws {
        guard let creds = Credentials.load() else { throw AuthError.noCredentials }

        let verifier = Self.randomURLSafe(64)
        let challenge = Self.s256(verifier)
        let state = Self.randomURLSafe(16)

        let listener = try LoopbackListener()
        let port = try await listener.start()
        let redirect = "http://127.0.0.1:\(port)"

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: creds.clientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
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
        let body = [
            "code": code,
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
            "redirect_uri": redirect,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ]
        let json = try await postToken(body)
        guard let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            throw AuthError.server("Malformed token response.")
        }
        return StoredToken(accessToken: access, refreshToken: refresh,
                           expiry: Date().addingTimeInterval(expiresIn))
    }

    private func refresh(_ tok: StoredToken, creds: Credentials) async throws -> StoredToken {
        let body = [
            "client_id": creds.clientID,
            "client_secret": creds.clientSecret,
            "refresh_token": tok.refreshToken,
            "grant_type": "refresh_token",
        ]
        let json = try await postToken(body)
        guard let access = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Double else {
            throw AuthError.server("Malformed refresh response.")
        }
        // Google keeps the same refresh token on refresh.
        return StoredToken(accessToken: access, refreshToken: tok.refreshToken,
                           expiry: Date().addingTimeInterval(expiresIn))
    }

    private func postToken(_ fields: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = fields.map { "\($0.key)=\(Self.formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            if (json["error"] as? String) == "invalid_grant" { throw AuthError.invalidGrant }
            throw AuthError.server(json["error_description"] as? String ?? "Token request failed (\(http.statusCode)).")
        }
        return json
    }

    private func persist(_ tok: StoredToken) {
        token = tok
        if let data = try? JSONEncoder().encode(tok) { Keychain.save(data) }
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
