import SwiftUI
import AppKit

struct MenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            body(for: model.state)
            Divider()
            footer
        }
        .frame(width: 320)
        .tint(.meetpaw)
        .animation(.spring(duration: 0.3), value: model.createdLink)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint.fill")
                .foregroundStyle(.tint)
            Text("MeetPaw").font(.headline)
            Spacer()
            if case .ready = model.state {
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
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
            .padding(12)

            if let link = model.createdLink {
                GlassLinkCard(url: link,
                              copy: { model.copyLink() },
                              join: { model.openCreatedLink() },
                              dismiss: { model.dismissCreatedLink() })
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.scale.combined(with: .opacity))
            }

            if model.meetings.isEmpty {
                Text("No upcoming meetings in the next 24 hours.")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.bottom, 12)
            } else {
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

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Toggle("Launch at login", isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                if case .signedOut = model.state {} else if case .needsCredentials = model.state {} else {
                    Button("Sign out") { model.signOut() }.buttonStyle(.borderless)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .font(.callout)
        .padding(12)
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
        Button(action: join) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summary ?? "(No title)").lineLimit(1)
                    Text(timeLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "video.fill").foregroundStyle(.tint)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
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
                Image(systemName: "video.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
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
                }
                Button {
                    copy()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied!" : "Copy link",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                Spacer()
            }
            .controlSize(.small)
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
