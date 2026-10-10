import SwiftUI
import AppKit

struct MenuContent: View {
    @Bindable var model: AppModel
    @State private var showSchedule = false
    @State private var scheduleSession = 0   // bump to reset the form each open

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: model.state)
        }
        .frame(width: 360)
        .tint(.meetpaw)
        .animation(.spring(duration: 0.3), value: model.createdLink)
    }

    private var isSignedIn: Bool {
        switch model.state {
        case .signedOut, .needsCredentials: return false
        default: return true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            if let logo = AppLogo.image {
                Image(nsImage: logo).resizable().scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text("MeetPaw").font(.headline)
            Spacer()
            Menu {
                if isSignedIn {
                    Button { Task { await model.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                Toggle(isOn: $model.launchAtLogin) {
                    Label("Launch at login", systemImage: "power")
                }
                Divider()
                if isSignedIn {
                    Button(role: .destructive) { model.signOut() } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
                Button { NSApp.terminate(nil) } label: {
                    Label("Quit MeetPaw", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Menu")
        }
        .padding(12)
    }

    // MARK: State-driven body

    @ViewBuilder
    private func body(for state: AppModel.State) -> some View {
        switch state {
        case .needsCredentials:
            message("Add your Google OAuth credentials to get started.",
                    systemImage: "key.fill") {
                Button("Open credentials folder…") { model.openCredentialsFolder() }
                Text("Drop your client_secret JSON as credentials.json, then relaunch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .signedOut:
            message("Sign in with Google to see your meetings.",
                    systemImage: "person.crop.circle") {
                Button("Sign in with Google") { model.signIn() }
                    .buttonStyle(.borderedProminent)
            }
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

    private var meetingsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                model.newInstantMeeting()
            } label: {
                HStack {
                    if model.creatingLink {
                        ProgressView().controlSize(.small)
                        Text("Creating…")
                    } else {
                        Label("New instant meeting", systemImage: "video.fill.badge.plus")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.creatingLink)
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
                if showSchedule {
                    ScheduleForm(model: model) { showSchedule = false }
                        .id(scheduleSession)   // new identity each open → reset state
                        // Form drops in from the top.
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    upcoming
                        // List is pushed down and out, and springs back up.
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .clipped()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: showSchedule)
    }

    @ViewBuilder
    private var upcoming: some View {
        if model.meetings.isEmpty {
            Text("No upcoming meetings in the next 24 hours.")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.bottom, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("UPCOMING").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.meetings) { event in
                            MeetingRow(event: event) { model.join(event) }
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
    let event: CalendarEvent
    let join: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            // Icon before the title, muted.
            Image(systemName: event.hasMeet ? "video.fill" : "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.summary ?? "(No title)").lineLimit(1)
                Text(timeLabel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: join) {
                Text(event.hasMeet ? "Join" : "Open")
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
    let copy: () -> Void
    let join: () -> Void
    let dismiss: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MeetLogo.image.map { Image(nsImage: $0).resizable().scaledToFit().frame(height: 18) }
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
