import Foundation

/// Runnable check (`MeetPaw --selftest`) with no test framework.
/// Verifies the event filtering/parsing that would silently break the list.
enum SelfTest {
    static func run() {
        let json = """
        { "items": [
          { "id": "a", "summary": "Timed w/ Meet",
            "start": { "dateTime": "2026-10-10T15:00:00+08:00" },
            "hangoutLink": "https://meet.google.com/aaa-bbbb-ccc" },
          { "id": "b", "summary": "All-day offsite",
            "start": { "date": "2026-10-11" },
            "conferenceData": { "entryPoints": [ { "entryPointType": "video", "uri": "https://meet.google.com/ddd-eeee-fff" } ] } },
          { "id": "c", "summary": "Declined standup",
            "start": { "dateTime": "2026-10-10T16:00:00.000Z" },
            "hangoutLink": "https://meet.google.com/ggg-hhhh-iii",
            "attendees": [ { "self": true, "responseStatus": "declined" } ] },
          { "id": "d", "summary": "No video call",
            "start": { "dateTime": "2026-10-10T17:00:00+08:00" } }
        ] }
        """
        let events = try! JSONDecoder().decode(EventsResponse.self, from: Data(json.utf8)).items!
        let filtered = events.filter { $0.meetURL != nil && !$0.isDeclinedByMe }

        // a (timed+link) and b (all-day+video entry) survive; c declined, d no link.
        assert(filtered.map(\.id) == ["a", "b"], "filter: \(filtered.map(\.id))")
        // all-day event parses to nil startDate without throwing.
        assert(events[1].startDate == nil, "all-day should have nil startDate")
        // timed event with fractional seconds parses.
        assert(events[2].startDate != nil, "fractional-seconds dateTime failed to parse")
        // timed event without fractional seconds parses.
        assert(events[0].startDate != nil, "non-fractional dateTime failed to parse")

        print("✅ SelfTest passed")
    }
}
