import SwiftUI
import AppKit

struct MenuContent: View {
    @Bindable var model: AppModel
    @State private var showSchedule = false
    @State private var scheduleSession = 0   // bump to reset the form each open
    @State private var showInstant = false   // drawer instant-meeting widget
    @State private var editingEvent: AccountEvent?    // non-nil → editing
    @State private var showAddAccount = false
    @State private var showAccountSwitcher = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showAddAccount {
                addAccountScreen
            } else if showAccountSwitcher {
                AccountSwitcher(model: model) { showAccountSwitcher = false }
            } else {
                body(for: model.state)
            }
        }
        .frame(width: 360)
        .tint(.meetpaw)
        .animation(.spring(duration: 0.3), value: model.createdLink)
    }

    private var addAccountScreen: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.cancelSignIn(); showAddAccount = false } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, 10)
            ProviderSignIn(model: model, title: "Add an account")
        }
        .onChange(of: model.accounts) { _, _ in showAddAccount = false }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let logo = AppLogo.wordmarkWhite {
                Image(nsImage: logo).resizable().scaledToFit()
                    .frame(height: 20)
                    .accessibilityLabel("MeetPaw")
            } else {
                Text("MeetPaw").font(.headline)
            }
            Spacer()
            if model.isSignedIn { accountDropdown }
            hamburger
        }
        .padding(12)
    }

    // Account filter toggle → opens the rich AccountSwitcher panel.
    private var accountDropdown: some View {
        Button {
            showAddAccount = false
            showAccountSwitcher.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(selectedLabel).lineLimit(1).font(.callout)
                Image(systemName: showAccountSwitcher ? "chevron.up" : "chevron.down").font(.caption2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: 140)
        }
        .buttonStyle(.plain)
    }

    private var selectedLabel: String {
        guard let sel = model.selectedAccountID,
              let a = model.accounts.first(where: { $0.id == sel }) else { return "All accounts" }
        return a.shortEmail
    }

    private var hamburger: some View {
        HamburgerMenu(model: model,
                      onAddAccount: { showAccountSwitcher = false; showAddAccount = true })
            .frame(width: 22, height: 22)
    }

    // MARK: State-driven body

    @ViewBuilder
    private func body(for state: AppModel.State) -> some View {
        switch state {
        case .signedOut:
            ProviderSignIn(model: model)
        case .loading:
            HStack { ProgressView().controlSize(.small); Text("Loading…") }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80)
        case .ready:
            meetingsList
        case .error(let msg):
            message(msg, systemImage: "exclamationmark.triangle.fill") {
                Button("Try again") { Task { await model.refresh() } }
            }
        }
    }

    @ViewBuilder
    private var meetingsList: some View {
        if showInstant {
            // Creating/created an instant meeting from the drawer → show only
            // the link widget, hide everything else.
            LinkWidget(model: model, fillWidth: true) {
                showInstant = false
                model.dismissCreatedLink()
            }
            .padding(.top, 6)
        } else {
            meetingsListMain
        }
    }

    private var meetingsListMain: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                showInstant = true
                model.newInstantMeeting()
            } label: {
                Label("New instant meeting", systemImage: "video.fill.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 12).padding(.top, 12)

            Button {
                if !showSchedule { scheduleSession += 1 }   // fresh fields on open
                showSchedule.toggle()
            } label: {
                Label("Schedule meeting", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).tint(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)

            ZStack(alignment: .top) {
                if showSchedule || editingEvent != nil {
                    ScheduleForm(model: model, editing: editingEvent) {
                        showSchedule = false; editingEvent = nil
                    }
                    .id(scheduleSession)   // new identity each open → reset state
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    upcoming
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showSchedule)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: editingEvent?.id)
    }

    @ViewBuilder
    private var accountErrorBanner: some View {
        if !model.accountErrors.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(model.accounts.filter { model.accountErrors[$0.id] != nil }) { a in
                    Text("⚠️ \(a.provider.name): \((model.accountErrors[a.id] ?? "").prefix(90))")
                        .font(.caption2).foregroundStyle(.orange).lineLimit(2)
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var upcoming: some View {
        let items = model.visibleMeetings
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                accountErrorBanner
                Text("No upcoming meetings in the next 24 hours.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                accountErrorBanner
                Text("UPCOMING").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            SwipeToDelete(onDelete: { model.deleteEvent(item) }) {
                                MeetingRow(item: item,
                                           showAccount: model.selectedAccountID == nil && model.accounts.count > 1,
                                           join: { model.join(item) },
                                           edit: { scheduleSession += 1; editingEvent = item })
                            }
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func message(_ text: String, systemImage: String,
                         @ViewBuilder actions: () -> some View) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.largeTitle).foregroundStyle(.secondary)
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }
}

struct MeetingRow: View {
    let item: AccountEvent
    var showAccount = false
    let join: () -> Void
    let edit: () -> Void
    @State private var hovering = false

    private var event: CalendarEvent { item.event }

    var body: some View {
        HStack(spacing: 10) {
            // Icon before the title, muted.
            Image(systemName: event.hasMeet ? "video.fill" : "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary ?? "(No title)").lineLimit(1)
                HStack(spacing: 6) {
                    Text(timeLabel)
                    if showAccount {
                        Text("· \(item.account.shortEmail)").lineLimit(1)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: edit) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Edit")
            Button(action: join) {
                Text(event.hasMeet ? "Join" : "Open")
                    .frame(width: 42)
            }
            .buttonStyle(.bordered)
            .tint(event.hasMeet ? .meetpaw : .secondary)
            .controlSize(.small)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: join)   // whole row is clickable
        .onHover { hovering = $0 }
    }

    private var timeLabel: String {
        guard let date = event.startDate else { return "All day" }
        let f = DateFormatter()
        f.doesRelativeDateFormatting = true
        f.dateStyle = .none
        f.timeStyle = .short
        let time = f.string(from: date)
        let mins = Int(date.timeIntervalSinceNow / 60)
        if mins < 0 { return "In progress · \(time)" }
        if mins < 60 { return "in \(mins) min · \(time)" }
        return time
    }
}

/// Liquid Glass card showing a freshly created meeting link.
struct GlassLinkCard: View {
    let url: URL
    var provider: Provider = .google
    let copy: () -> Void
    let join: () -> Void
    let dismiss: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderLogoView(provider: provider, size: 18)
                Text("New meeting ready")
                    .font(.subheadline).fontWeight(.semibold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(url.absoluteString.replacingOccurrences(of: "https://", with: ""))
                .font(.system(.callout, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button(action: join) {
                    Label("Join", systemImage: "arrow.up.forward.app")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.meetpaw)
                Button {
                    copy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy link",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .controlSize(.large)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 16)
    }
}

extension Color {
    /// App accent: oklch(64.6% .222 41.116) ≈ #EA580C
    static let meetpaw = Color(red: 0.918, green: 0.345, blue: 0.047)
}

/// The Google Meet logo, loaded once from the bundled SVG (NSImage renders SVG).
enum MeetLogo {
    static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "meet", withExtension: "svg") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// The MeetPaw app icon, loaded once from the bundled PNG.
enum AppLogo {
    static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "appicon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// White wordmark (paw + "MeetPaw") for the dark drawer header.
    static let wordmarkWhite: NSImage? = {
        guard let url = Bundle.module.url(forResource: "logo-white", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

extension View {
    /// Liquid Glass on macOS 26+, graceful material fallback below.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.regularMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
