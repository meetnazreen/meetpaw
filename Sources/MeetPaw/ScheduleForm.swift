import SwiftUI

struct ScheduleForm: View {
    @Bindable var model: AppModel
    let onDone: () -> Void

    @State private var title = ""
    @State private var start = defaultStart()
    @State private var durationMinutes = 30
    @State private var addMeet = true
    @State private var emails: [String] = []
    @State private var emailDraft = ""
    @State private var emailInvalid = false
    @State private var submitting = false

    private let durations = [15, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Meeting title", text: $title)
                .textFieldStyle(.plain)
                .glassField()

            // iOS-style inline calendar for the date.
            labeled("Date") {
                DatePicker("", selection: $start, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
            }

            HStack(alignment: .bottom, spacing: 12) {
                labeled("Time") {
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact).labelsHidden()
                }
                labeled("Duration") {
                    Picker("", selection: $durationMinutes) {
                        ForEach(durations, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            }

            // Attendees as chips.
            VStack(alignment: .leading, spacing: 6) {
                if !emails.isEmpty {
                    ChipFlow(emails: emails) { remove($0) }
                }
                TextField("Add guest email, press return", text: $emailDraft)
                    .textFieldStyle(.plain)
                    .glassField()
                    .onSubmit(addEmail)
                if emailInvalid {
                    Text("Enter a valid email address.")
                        .font(.caption).foregroundStyle(.red)
                }
            }

            Toggle(isOn: $addMeet) {
                Label("Add Google Meet link", systemImage: "video")
            }

            HStack(spacing: 14) {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button(action: submit) {
                    if submitting { ProgressView().controlSize(.small) }
                    else { Text("Schedule") }
                }
                .buttonStyle(.borderedProminent).tint(.meetpaw)
                .disabled(title.isEmpty || submitting)
            }
            .controlSize(.large)
        }
        .controlSize(.large)
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 12).padding(.bottom, 12)
    }

    @ViewBuilder
    private func labeled(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Actions

    private func addEmail() {
        let candidate = emailDraft.trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty else { return }
        guard Self.isValidEmail(candidate) else { emailInvalid = true; return }
        if !emails.contains(candidate) { emails.append(candidate) }
        emailDraft = ""
        emailInvalid = false
    }

    private func remove(_ email: String) { emails.removeAll { $0 == email } }

    private func submit() {
        addEmail()                       // fold in any typed-but-unadded email
        guard !emailInvalid else { return }
        submitting = true
        Task {
            let ok = await model.scheduleMeeting(title: title, start: start,
                                                  durationMinutes: durationMinutes,
                                                  attendees: emails, addMeet: addMeet)
            submitting = false
            if ok { onDone() }
        }
    }

    static func isValidEmail(_ s: String) -> Bool {
        let pattern = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        return s.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func defaultStart() -> Date {
        // Next quarter-hour.
        let now = Date().addingTimeInterval(5 * 60)
        let cal = Calendar.current
        let minute = cal.component(.minute, from: now)
        let rounded = (minute / 15 + 1) * 15
        return cal.date(bySetting: .minute, value: rounded % 60, of: now) ?? now
    }
}

extension View {
    /// A taller text field with a Liquid Glass background (material fallback).
    @ViewBuilder
    func glassField() -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        let padded = self.padding(.horizontal, 10).padding(.vertical, 8)
        if #available(macOS 26.0, *) {
            padded.glassEffect(.regular, in: shape)
        } else {
            padded.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.quaternary))
        }
    }
}

/// Wrapping row of removable email chips.
struct ChipFlow: View {
    let emails: [String]
    let remove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(emails, id: \.self) { email in
                HStack(spacing: 4) {
                    Text(email).font(.caption)
                    Button { remove(email) } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.meetpaw.opacity(0.15), in: Capsule())
            }
        }
    }
}

/// Minimal flow layout that wraps subviews to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
