import Foundation

/// Instant-meeting creation for Zoom and Microsoft Teams (Phase 1).
/// Google keeps its own richer GoogleAPI; this covers the new providers.
struct ProviderAPI {
    let auth: OAuthClient

    func createInstantMeeting() async throws -> URL {
        switch auth.provider {
        case .zoom: return try await zoomInstant()
        case .microsoft: return try await teamsInstant()
        case .google: throw AuthError.server("Use GoogleAPI for Google.")
        }
    }

    private func zoomInstant() async throws -> URL {
        let token = try await auth.accessToken()
        var req = URLRequest(url: URL(string: "https://api.zoom.us/v2/users/me/meetings")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(#"{"type":1}"#.utf8)   // type 1 = instant meeting

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        guard let s = try JSONDecoder().decode(ZoomMeeting.self, from: data).joinURL,
              let url = URL(string: s) else {
            throw AuthError.server("Zoom returned no join URL.")
        }
        return url
    }

    private func teamsInstant() async throws -> URL {
        let token = try await auth.accessToken()
        let now = ISO8601DateFormatter()
        let body: [String: Any] = [
            "startDateTime": now.string(from: Date()),
            "endDateTime": now.string(from: Date().addingTimeInterval(3600)),
            "subject": "Instant meeting",
        ]
        var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/onlineMeetings")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        guard let s = try JSONDecoder().decode(TeamsMeeting.self, from: data).joinWebUrl,
              let url = URL(string: s) else {
            throw AuthError.server("Teams returned no join URL.")
        }
        return url
    }

    static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.server(String(data: data, encoding: .utf8) ?? "Request failed.")
        }
    }
}

struct ZoomMeeting: Codable {
    let joinURL: String?
    enum CodingKeys: String, CodingKey { case joinURL = "join_url" }
}

struct TeamsMeeting: Codable {
    let joinWebUrl: String?
}
