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

    // MARK: Scheduled meetings

    func createScheduled(title: String, start: Date, durationMinutes: Int, attendees: [String]) async throws {
        switch auth.provider {
        case .zoom: try await zoomScheduled(title: title, start: start, duration: durationMinutes, attendees: attendees)
        case .microsoft: try await teamsScheduled(title: title, start: start, duration: durationMinutes, attendees: attendees)
        case .google: throw AuthError.server("Use GoogleAPI for Google.")
        }
    }

    private func zoomScheduled(title: String, start: Date, duration: Int, attendees: [String]) async throws {
        let token = try await auth.accessToken()
        let fmt = ISO8601DateFormatter()
        var settings: [String: Any] = ["join_before_host": true]
        if !attendees.isEmpty { settings["meeting_invitees"] = attendees.map { ["email": $0] } }
        let body: [String: Any] = [
            "topic": title.isEmpty ? "Meeting" : title,
            "type": 2,                               // scheduled
            "start_time": fmt.string(from: start),
            "duration": duration,
            "settings": settings,
        ]
        var req = URLRequest(url: URL(string: "https://api.zoom.us/v2/users/me/meetings")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
    }

    private func teamsScheduled(title: String, start: Date, duration: Int, attendees: [String]) async throws {
        let token = try await auth.accessToken()
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        let tz = TimeZone.current.identifier
        let body: [String: Any] = [
            "subject": title.isEmpty ? "Meeting" : title,
            "start": ["dateTime": f.string(from: start), "timeZone": tz],
            "end": ["dateTime": f.string(from: end), "timeZone": tz],
            "isOnlineMeeting": true,
            "onlineMeetingProvider": "teamsForBusiness",
            "attendees": attendees.map { ["emailAddress": ["address": $0], "type": "required"] },
        ]
        var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me/events")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
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
