import Foundation
import Observation
import AppKit
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    enum State { case signedOut, loading, ready, error(String) }

    private(set) var state: State = .signedOut
    private(set) var meetings: [AccountEvent] = []       // merged across accounts
    private(set) var accounts: [Account] = []
    private(set) var createdLink: URL?
    private(set) var createdProvider: Provider?
    private(set) var creatingLink = false
    var signingIn = false                                // separate from list loading

    var selectedAccountID: String?                       // nil = All accounts
    var defaultAccountID: String? {
        didSet { UserDefaults.standard.set(defaultAccountID, forKey: "defaultAccountID") }
    }

    var isSignedIn: Bool { !accounts.isEmpty }
    func hasCredentials(_ p: Provider) -> Bool { Credentials.load(p) != nil }

    /// Events shown for the current account filter.
    var visibleMeetings: [AccountEvent] {
        guard let sel = selectedAccountID else { return meetings }
        return meetings.filter { $0.account.id == sel }
    }

    var defaultAccount: Account? {
        accounts.first { $0.id == defaultAccountID } ?? accounts.first
    }

    @ObservationIgnored private var clients: [String: OAuthClient] = [:]
    @ObservationIgnored private var refreshTimer: Timer?

    init() {
        defaultAccountID = UserDefaults.standard.string(forKey: "defaultAccountID")
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

    // MARK: Bootstrap / accounts

    private func bootstrap() async {
        await migrateLegacyGoogleIfNeeded()
        accounts = AccountStore.load()
        for a in accounts { clients[a.id] = OAuthClient(provider: a.provider, keychainKey: a.id) }
        await settle()
    }

    /// Migrate the old single-account Google token (Keychain "google") into the
    /// new per-account model so an existing user stays signed in.
    private func migrateLegacyGoogleIfNeeded() async {
        guard AccountStore.load().isEmpty,
              let data = Keychain.load(account: "google"),
              let token = try? JSONDecoder().decode(StoredToken.self, from: data) else { return }
        let email = await OAuthClient.identity(provider: .google, token: token)
        let account = Account(provider: .google, email: email)
        Keychain.save(data, account: account.id)
        AccountStore.add(account)
        if account.id != "google" { Keychain.clear(account: "google") }
        if defaultAccountID == nil { defaultAccountID = account.id }
    }

    private func settle() async {
        if accounts.isEmpty { state = .signedOut; refreshTimer?.invalidate(); return }
        await refresh()
        startTimer()
    }

    func addAccount(_ provider: Provider) {
        guard !signingIn else { return }
        Task {
            signingIn = true
            defer { signingIn = false }
            do {
                let token = try await OAuthClient.authorize(provider: provider)
                let email = await OAuthClient.identity(provider: provider, token: token)
                let account = Account(provider: provider, email: email)
                if let data = try? JSONEncoder().encode(token) {
                    Keychain.save(data, account: account.id)
                }
                AccountStore.add(account)
                accounts = AccountStore.load()
                clients[account.id] = OAuthClient(provider: provider, keychainKey: account.id)
                if defaultAccountID == nil { defaultAccountID = account.id }
                await refresh()
                startTimer()
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func signOut(_ account: Account) {
        Task {
            await clients[account.id]?.signOut()
            clients[account.id] = nil
            AccountStore.remove(account)
            accounts = AccountStore.load()
            meetings.removeAll { $0.account.id == account.id }
            if selectedAccountID == account.id { selectedAccountID = nil }
            if defaultAccountID == account.id { defaultAccountID = accounts.first?.id }
            await settle()
        }
    }

    // MARK: Events (Google calendars for now; Zoom/Teams lists later)

    func refresh() async {
        let googleAccounts = accounts.filter { $0.provider == .google }
        guard !googleAccounts.isEmpty else {
            meetings = []
            state = accounts.isEmpty ? .signedOut : .ready
            return
        }
        if case .ready = state {} else { state = .loading }

        let pairs = googleAccounts.compactMap { a in clients[a.id].map { (a, $0) } }
        var all: [AccountEvent] = []
        await withTaskGroup(of: [AccountEvent].self) { group in
            for (account, client) in pairs {
                group.addTask {
                    do {
                        let events = try await GoogleAPI(auth: client).upcomingMeetings()
                        return events.map { AccountEvent(account: account, event: $0) }
                    } catch { return [] }   // one account failing must not drop others
                }
            }
            for await part in group { all += part }
        }
        all.sort { ($0.event.startDate ?? .distantFuture) < ($1.event.startDate ?? .distantFuture) }
        meetings = all
        Notifier.shared.schedule(all.map(\.event))
        state = .ready
    }

    // MARK: Instant meeting (default account's provider)

    func newInstantMeeting() {
        guard let account = defaultAccount, let client = clients[account.id] else {
            state = .error("No account selected."); return
        }
        Task {
            creatingLink = true
            defer { creatingLink = false }
            do {
                let url: URL
                if account.provider == .google {
                    url = try await GoogleAPI(auth: client).createInstantMeeting()
                } else {
                    url = try await ProviderAPI(auth: client).createInstantMeeting()
                }
                createdLink = url
                createdProvider = account.provider
                copyLink()
            } catch {
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    // MARK: Schedule / edit / delete (Google account)

    /// The Google account to schedule on: the selected one if it's Google, else
    /// the default Google account.
    private var scheduleAccount: Account? {
        if let sel = selectedAccountID, let a = accounts.first(where: { $0.id == sel }), a.provider == .google { return a }
        if let d = defaultAccount, d.provider == .google { return d }
        return accounts.first { $0.provider == .google }
    }

    func scheduleMeeting(title: String, start: Date, durationMinutes: Int,
                         attendees: [String], addMeet: Bool) async -> Bool {
        guard let account = scheduleAccount, let client = clients[account.id] else {
            state = .error("Connect a Google account to schedule."); return false
        }
        do {
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            try await GoogleAPI(auth: client).createEvent(title: title, start: start, end: end,
                                                          attendees: attendees, addMeet: addMeet)
            await refresh()
            return true
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    func updateMeeting(_ item: AccountEvent, title: String, start: Date,
                       durationMinutes: Int, attendees: [String], addMeet: Bool) async -> Bool {
        guard let client = clients[item.account.id] else { return false }
        do {
            let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
            try await GoogleAPI(auth: client).updateEvent(id: item.event.id, title: title, start: start,
                                end: end, attendees: attendees, addMeet: addMeet, hasMeet: item.event.hasMeet)
            await refresh()
            return true
        } catch {
            state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            return false
        }
    }

    func deleteEvent(_ item: AccountEvent) {
        guard let client = clients[item.account.id] else { return }
        let backup = meetings
        meetings.removeAll { $0.id == item.id }
        Notifier.shared.schedule(meetings.map(\.event))
        Task {
            do {
                try await GoogleAPI(auth: client).deleteEvent(id: item.event.id)
            } catch {
                meetings = backup
                state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    // MARK: Link helpers

    func copyLink() {
        guard let url = createdLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    func openCreatedLink() { if let url = createdLink { NSWorkspace.shared.open(url) } }
    func dismissCreatedLink() { createdLink = nil }

    func join(_ item: AccountEvent) {
        if let url = item.event.openURL { NSWorkspace.shared.open(url) }
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
