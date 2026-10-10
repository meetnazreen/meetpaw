import Foundation

/// Calendar + Meet REST calls. Plain HTTPS/JSON, no Google SDK.
struct GoogleAPI {
    let auth: GoogleAuth

    /// Upcoming events in the next 24h that have a Meet link, soonest first.
    func upcomingMeetings() async throws -> [CalendarEvent] {
        let token = try await auth.accessToken()
        let now = ISO8601DateFormatter().string(from: Date())
        let tomorrow = ISO8601DateFormatter().string(from: Date().addingTimeInterval(24 * 3600))

        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        comps.queryItems = [
            .init(name: "timeMin", value: now),
            .init(name: "timeMax", value: tomorrow),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "maxResults", value: "20"),
        ]
        let data = try await get(comps.url!, token: token)
        let events = try JSONDecoder().decode(EventsResponse.self, from: data).items ?? []
        return events.filter { $0.meetURL != nil && !$0.isDeclinedByMe }
    }

    /// Creates an instant Meet link. Tries the Meet REST API first; if that
    /// fails (e.g. 403 on some consumer accounts), falls back to inserting a
    /// 1-hour Calendar event with a Meet conference attached.
    func createInstantMeeting() async throws -> URL {
        let token = try await auth.accessToken()
        if let url = try? await meetSpace(token: token) { return url }
        return try await calendarConference(token: token)
    }

    private func meetSpace(token: String) async throws -> URL {
        var req = URLRequest(url: URL(string: "https://meet.googleapis.com/v2/spaces")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.server(String(data: data, encoding: .utf8) ?? "Meet API failed.")
        }
        guard let uri = try JSONDecoder().decode(MeetSpace.self, from: data).meetingUri,
              let url = URL(string: uri) else {
            throw AuthError.server("Meet API returned no meeting URL.")
        }
        return url
    }

    private func calendarConference(token: String) async throws -> URL {
        let now = Date()
        let fmt = ISO8601DateFormatter()
        let body: [String: Any] = [
            "summary": "Instant meeting",
            "start": ["dateTime": fmt.string(from: now)],
            "end": ["dateTime": fmt.string(from: now.addingTimeInterval(3600))],
            "conferenceData": [
                "createRequest": [
                    "requestId": UUID().uuidString,
                    "conferenceSolutionKey": ["type": "hangoutsMeet"],
                ]
            ],
        ]
        // conferenceDataVersion=1 is REQUIRED or no Meet link is created (silently).
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events?conferenceDataVersion=1")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.server(String(data: data, encoding: .utf8) ?? "Could not create meeting.")
        }
        guard let url = try JSONDecoder().decode(CalendarEvent.self, from: data).meetURL else {
            throw AuthError.server("Calendar created an event but no Meet link.")
        }
        return url
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
            throw AuthError.invalidGrant
        }
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.server(String(data: data, encoding: .utf8) ?? "Request failed.")
        }
        return data
    }
}
