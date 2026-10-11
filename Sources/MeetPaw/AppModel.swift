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
    private(set) var accountErrors: [String: String] = [:]   // account.id → fetch error
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

    /// Distinct providers the user is signed into (order of first appearance).
    var signedProviders: [Provider] {
        var seen: [Provider] = []
        for a in accounts where !seen.contains(a.provider) { seen.append(a.provider) }
        return seen
    }

    var defaultProvider: Provider { defaultAccount?.provider ?? .google }

    func setDefaultProvider(_ p: Provider) {
        if let a = accounts.first(where: { $0.provider == p }) { defaultAccountID = a.id }
    }

    @ObservationIgnored private var clients: [String: OAuthClient] = [:]
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

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

    static let maxAccountsPerProvider = 5

    func canAddAccount(_ provider: Provider) -> Bool {
        accounts.filter { $0.provider == provider }.count < Self.maxAccountsPerProvider
    }

    func addAccount(_ provider: Provider) {
        guard !signingIn else { return }
        guard canAddAccount(provider) else {
            state = .error("Up to \(Self.maxAccountsPerProvider) \(provider.name) accounts.")
            return
        }
        signInTask = Task {
            signingIn = true
            defer { signingIn = false }
            do {
                let token = try await OAuthClient.authorize(provider: provider)
                try Task.checkCancellation()
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
            } catch is CancellationError {
                // user backed out — stay quiet
            } catch {
                if !Task.isCancelled {
                    state = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
            }
        }
    }

    /// Cancel an in-flight sign-in (e.g. user closed the browser / hit Back).
    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        signingIn = false
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
        guard !accounts.isEmpty else { meetings = []; state = .signedOut; return }
        if case .ready = state {} else { state = .loading }

        struct Fetched { let account: Account; let events: [AccountEvent]; let error: String? }
        let pairs = accounts.compactMap { a in clients[a.id].map { (a, $0) } }
        var all: [AccountEvent] = []
        var errors: [String: String] = [:]
        await withTaskGroup(of: Fetched.self) { group in
            for (account, client) in pairs {
                group.addTask {
                    do {
                        let events: [CalendarEvent]
                        if account.provider == .google {
                            events = try await GoogleAPI(auth: client).upcomingMeetings()
                        } else {
                            events = try await ProviderAPI(auth: client).upcomingMeetings()
                        }
                        return Fetched(account: account,
                                       events: events.map { AccountEvent(account: account, event: $0) },
                                       error: nil)
                    } catch {
                        let msg = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        return Fetched(account: account, events: [], error: msg)
                    }
                }
            }
            for await part in group {
                all += part.events
                if let e = part.error { errors[part.account.id] = e }
            }
        }
        accountErrors = errors
        all.sort { ($0.event.startDate ?? .distantFuture) < ($1.event.startDate ?? .distantFuture) }
        meetings = all
        Notifier.shared.schedule(all.map(\.event))
        state = .ready
    }

    // MARK: Instant meeting (default account's provider)

    /// Does an account exist for this provider (for global-hotkey gating)?
    func hasAccount(_ provider: Provider) -> Bool {
        accounts.contains { $0.provider == provider }
    }

    func newInstantMeeting(provider: Provider? = nil) {
        let account: Account? = {
            if let provider { return accounts.first { $0.provider == provider } }
            return defaultAccount
        }()
        guard let account, let client = clients[account.id] else {
            state = .error("No account for that provider."); return
        }
        Task {
            creatingLink = true
            createdLink = nil                 // clear old link → widget shows spinner instantly
            createdProvider = account.provider
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

    /// Events across all connected calendars that overlap the given slot.
    func conflicts(start: Date, durationMinutes: Int, excluding id: String? = nil) -> [AccountEvent] {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return meetings.filter { item in
            if let id, item.id == id { return false }
            guard let s = item.event.startDate else { return false }
            let e = item.event.endDate ?? s.addingTimeInterval(30 * 60)
            return start < e && s < end          // half-open overlap
        }
    }

    /// Account preselected in the schedule form: the header-selected one, else default.
    var formAccount: Account? {
        if let sel = selectedAccountID, let a = accounts.first(where: { $0.id == sel }) { return a }
        return defaultAccount
    }

    func scheduleMeeting(on account: Account, title: String, start: Date, durationMinutes: Int,
                         attendees: [String], addMeet: Bool) async -> Bool {
        guard let client = clients[account.id] else { return false }
        do {
            if account.provider == .google {
                let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
                try await GoogleAPI(auth: client).createEvent(title: title, start: start, end: end,
                                                              attendees: attendees, addMeet: addMeet)
            } else {
                try await ProviderAPI(auth: client).createScheduled(title: title, start: start,
                                                    durationMinutes: durationMinutes, attendees: attendees)
            }
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
                switch item.account.provider {
                case .google:
                    try await GoogleAPI(auth: client).deleteEvent(id: item.event.id)
                case .zoom:
                    try await ProviderAPI(auth: client).deleteMeeting(rawID: strip("zoom-", item.event.id))
                case .microsoft:
                    try await ProviderAPI(auth: client).deleteMeeting(rawID: strip("teams-", item.event.id))
                }
            } catch {
                meetings = backup    // restore the row; don't blank the whole UI
                accountErrors[item.account.id] =
                    "Delete failed: " + ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    private func strip(_ prefix: String, _ id: String) -> String {
        id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : id
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
