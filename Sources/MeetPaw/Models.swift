import Foundation

// MARK: - Calendar events.list

struct EventsResponse: Codable {
    let items: [CalendarEvent]?
}

struct CalendarEvent: Codable, Identifiable {
    let id: String
    let summary: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let hangoutLink: String?
    let conferenceData: ConferenceData?
    let attendees: [Attendee]?

    /// The URL to click "Join" — prefer explicit video entry point, else hangoutLink.
    var meetURL: URL? {
        if let ep = conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" }),
           let uri = ep.uri, let url = URL(string: uri) {
            return url
        }
        if let link = hangoutLink, let url = URL(string: link) { return url }
        return nil
    }

    /// Start time for timed events; all-day events have `date` not `dateTime`.
    var startDate: Date? {
        guard let dt = start?.dateTime else { return nil }
        return parseRFC3339(dt)
    }

    var isDeclinedByMe: Bool {
        attendees?.contains { $0.`self` == true && $0.responseStatus == "declined" } ?? false
    }
}

struct EventDateTime: Codable {
    let dateTime: String?   // timed events
    let date: String?       // all-day events
}

struct ConferenceData: Codable {
    let entryPoints: [EntryPoint]?
}

struct EntryPoint: Codable {
    let entryPointType: String?
    let uri: String?
}

struct Attendee: Codable {
    let `self`: Bool?
    let responseStatus: String?
}

// MARK: - Meet spaces.create

struct MeetSpace: Codable {
    let meetingUri: String?
}

/// Google sends dateTime with or without fractional seconds; try both.
func parseRFC3339(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
