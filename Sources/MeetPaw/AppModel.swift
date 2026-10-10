import Foundation
import Observation
import AppKit
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    enum State { case needsCredentials, signedOut, loading, ready, error(String) }

    private(set) var state: State = .signedOut
    private(set) var meetings: [CalendarEvent] = []
    private(set) var createdLink: URL?       // last instant meeting, shown in the glass card
    private(set) var createdProvider: Provider?
    private(set) var creatingLink = false
    private(set) var signedIn: Set<Provider> = []

    /// Signed into at least one provider.
    var isSignedIn: Bool { !signedIn.isEmpty }
    func isSignedIn(_ p: Provider) -> Bool { signedIn.contains(p) }
    func hasCredentials(_ p: Provider) -> Bool { Credentials.load(p) != nil }

    /// Provider used for left-click / New instant meeting.
    var defaultProvider: Provider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "defaultProvider"),
               let p = Provider(rawValue: raw), signedIn.contains(p) { return p }
            return signedIn.sorted { $0.rawValue < $1.rawValue }.first ?? .google
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "defaultProvider") }
    }

    @ObservationIgnored let clients: [Provider: OAuthClient] =
        Dictionary(uniqueKeysWithValues: Provider.allCases.map { ($0, OAuthClient($0)) })
    private var googleAPI: GoogleAPI { GoogleAPI(auth: clients[.google]!) }
    @ObservationIgnored private var refreshTimer: Timer?

    init() {
        Notifier.shared.start()
        Task { await bootstrap() }
        observeWake()
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                state = .error("Launch-at-login change failed: \(error.localizedDescription)")
            }
        }
    }

    private func bootstrap() async {
        var signed: Set<Provider> = []
        for p in Provider.allCases where await clients[p]!.isSignedIn { signed.insert(p) }
        signedIn = signed
        await settle()
    }

    /// Reconcile UI state after a sign-in/out change.
    private func settle() async {
        if signedIn.isEmpty { state = .signedOut; refreshTimer?.invalidate(); return }
        if signedIn.contains(.google) { await refresh(); startTimer() }
        else { state = .ready }   // Phase 2: merge Zoom/Teams upcoming here
    }

    func signIn(_ provider: Provider) {
        Task {
            state = .loading
            do {
                try await clients[provider]!.signIn()
                signedIn.insert(provider)
                await settle()
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func signOut(_ provider: Provider) {
        Task {
            await clients[provider]!.signOut()
            signedIn.remove(provider)
            if provider == .google { meetings = [] }
            await settle()
        }
    }

    func refresh() async {
        guard signedIn.contains(.google) else { return }   // calendar is Google (Phase 1)
        if case .ready = state {} else { state = .loading }
        do {
            meetings = try await googleAPI.upcomingMeetings()
            Notifier.shared.schedule(meetings)
            state = .ready
        } catch AuthError.invalidGrant {
            await clients[.google]!.signOut()
            signedIn.remove(.google)
            meetings = []
            await settle()
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func newInstantMeeting() {
        let provider = defaultProvider
        Task {
            creatingLink = true
            defer { creatingLink = false }
            do {
                let url: URL
                if provider == .google {
                    url = try await googleAPI.createInstantMeeting()
                } else {
                    url = try await ProviderAPI(auth: clients[provider]!).createInstantMeeting()
                }
                createdLink = url
                createdProvider = provider
                copyLink()                       // auto-copy on create
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Schedules an event; returns true on success (used to collapse the form).
    func scheduleMeeting(title: String, start: Date, durationMinutes: Int,
                         attendees: [String], addMeet: Bool) async -> Bool {
        do {
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            try await googleAPI.createEvent(title: title, start: start, end: end,
                                      attendees: attendees, addMeet: addMeet)
            await refresh()
            return true
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    /// Deletes an event (optimistic remove, restores on failure).
    func deleteEvent(_ event: CalendarEvent) {
        let backup = meetings
        meetings.removeAll { $0.id == event.id }
        Notifier.shared.schedule(meetings)
        Task {
            do {
                try await googleAPI.deleteEvent(id: event.id)
            } catch {
                meetings = backup           // restore
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    /// Updates an existing event; returns true on success.
    func updateMeeting(event: CalendarEvent, title: String, start: Date,
                       durationMinutes: Int, attendees: [String], addMeet: Bool) async -> Bool {
        do {
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            try await googleAPI.updateEvent(id: event.id, title: title, start: start, end: end,
                                      attendees: attendees, addMeet: addMeet, hasMeet: event.hasMeet)
            await refresh()
            return true
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    func copyLink() {
        guard let url = createdLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func openCreatedLink() {
        if let url = createdLink { NSWorkspace.shared.open(url) }
    }

    func dismissCreatedLink() { createdLink = nil }

    func join(_ event: CalendarEvent) {
        // Meet link if present, otherwise open the event in Google Calendar.
        if let url = event.openURL { NSWorkspace.shared.open(url) }
    }

    func openCredentialsFolder() {
        let dir = Credentials.dir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
}
