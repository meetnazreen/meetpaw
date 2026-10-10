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
    private(set) var creatingLink = false

    @ObservationIgnored private let auth = GoogleAuth()
    @ObservationIgnored private lazy var api = GoogleAPI(auth: auth)
    @ObservationIgnored private var refreshTimer: Timer?

    init() {
        if Credentials.load() == nil {
            state = .needsCredentials
            return
        }
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
        if await auth.isSignedIn {
            await refresh()
            startTimer()
        } else {
            state = .signedOut
        }
    }

    func signIn() {
        Task {
            state = .loading
            do {
                try await auth.signIn()
                await refresh()
                startTimer()
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func signOut() {
        Task {
            await auth.signOut()
            meetings = []
            state = .signedOut
            refreshTimer?.invalidate()
        }
    }

    func refresh() async {
        guard await auth.isSignedIn else { state = .signedOut; return }
        state = .loading
        do {
            meetings = try await api.upcomingMeetings()
            Notifier.shared.schedule(meetings)
            state = .ready
        } catch AuthError.invalidGrant {
            await auth.signOut()
            state = .signedOut
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func newInstantMeeting() {
        Task {
            creatingLink = true
            defer { creatingLink = false }
            do {
                let url = try await api.createInstantMeeting()
                createdLink = url
                copyLink()                       // auto-copy on create
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
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
        if let url = event.meetURL { NSWorkspace.shared.open(url) }
    }

    func openCredentialsFolder() {
        let dir = Credentials.fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
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
