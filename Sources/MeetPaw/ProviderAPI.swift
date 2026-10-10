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

    // MARK: Upcoming meetings (Phase 2)

    func upcomingMeetings() async throws -> [CalendarEvent] {
        switch auth.provider {
        case .zoom: return try await zoomUpcoming()
        case .microsoft: return try await teamsUpcoming()
        case .google: return []
        }
    }

    private func zoomUpcoming() async throws -> [CalendarEvent] {
        let token = try await auth.accessToken()
        var req = URLRequest(url: URL(string: "https://api.zoom.us/v2/users/me/meetings?type=upcoming&page_size=30")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        let list = try JSONDecoder().decode(ZoomMeetingList.self, from: data)
        let cutoff = Date().addingTimeInterval(24 * 3600)
        return (list.meetings ?? []).compactMap { m in
            guard let s = m.start_time, let start = parseRFC3339(s), start < cutoff,
                  let join = m.join_url else { return nil }
            return CalendarEvent.external(id: "zoom-\(m.id ?? 0)", title: m.topic ?? "Zoom meeting",
                start: start, end: start.addingTimeInterval(TimeInterval((m.duration ?? 30) * 60)), joinURL: join)
        }
    }

    private func teamsUpcoming() async throws -> [CalendarEvent] {
        let token = try await auth.accessToken()
        let f = ISO8601DateFormatter()
        let start = f.string(from: Date())
        let end = f.string(from: Date().addingTimeInterval(24 * 3600))
        let url = "https://graph.microsoft.com/v1.0/me/calendarView?startDateTime=\(start)&endDateTime=\(end)&$orderby=start/dateTime&$top=30"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)
        let list = try JSONDecoder().decode(GraphEvents.self, from: data)
        let gf = DateFormatter()
        gf.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
        gf.timeZone = TimeZone(identifier: "UTC")
        return (list.value ?? []).compactMap { e in
            guard let dt = e.start?.dateTime, let when = gf.date(from: dt) else { return nil }
            let join = e.onlineMeeting?.joinUrl ?? e.webLink
            guard let join else { return nil }
            return CalendarEvent.external(id: "teams-\(e.id ?? UUID().uuidString)",
                title: e.subject ?? "Teams meeting", start: when, end: nil, joinURL: join)
        }
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

    func deleteMeeting(rawID: String) async throws {
        let token = try await auth.accessToken()
        let url: String
        switch auth.provider {
        case .zoom: url = "https://api.zoom.us/v2/meetings/\(rawID)"
        case .microsoft: url = "https://graph.microsoft.com/v1.0/me/events/\(rawID)"
        case .google: throw AuthError.server("Use GoogleAPI for Google.")
        }
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.check(resp, data)   // 204 on success
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

struct ZoomMeetingList: Codable {
    let meetings: [ZoomListItem]?
}
struct ZoomListItem: Codable {
    let id: Int?
    let topic: String?
    let start_time: String?
    let duration: Int?
    let join_url: String?
}

struct GraphEvents: Codable {
    let value: [GraphEvent]?
}
struct GraphEvent: Codable {
    let id: String?
    let subject: String?
    let webLink: String?
    let start: GraphDateTime?
    let onlineMeeting: GraphOnlineMeeting?
}
struct GraphDateTime: Codable { let dateTime: String? }
struct GraphOnlineMeeting: Codable { let joinUrl: String? }
