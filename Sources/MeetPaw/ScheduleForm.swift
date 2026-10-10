import SwiftUI

struct ScheduleForm: View {
    @Bindable var model: AppModel
    var editing: AccountEvent?           // non-nil → edit mode
    let onDone: () -> Void

    @State private var title: String
    @State private var start: Date
    @State private var durationMinutes: Int
    @State private var addMeet: Bool
    @State private var emails: [String]
    @State private var emailDraft = ""
    @State private var emailInvalid = false
    @State private var submitting = false
    @State private var account: Account?

    private let durations = [15, 30, 45, 60]

    init(model: AppModel, editing: AccountEvent? = nil, onDone: @escaping () -> Void) {
        self._model = Bindable(wrappedValue: model)
        self.editing = editing
        self.onDone = onDone
        _account = State(initialValue: editing?.account ?? model.formAccount ?? model.accounts.first)
        let event = editing?.event
        _title = State(initialValue: event?.summary ?? "")
        _start = State(initialValue: event?.startDate ?? Self.defaultStart())
        _addMeet = State(initialValue: event?.hasMeet ?? true)
        _emails = State(initialValue: event?.attendeeEmails ?? [])
        var dur = 30
        if let s = event?.startDate, let e = event?.endDate {
            let m = Int(e.timeIntervalSince(s) / 60)
            dur = [15, 30, 45, 60].contains(m) ? m : 30
        }
        _durationMinutes = State(initialValue: dur)
    }

    private var isEditing: Bool { editing != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Which account (and provider) to create under.
            labeled("Account") { accountField }

            TextField("Meeting title", text: $title)
                .textFieldStyle(.plain)
                .glassField()

            // Date, Time, Duration — equal-width glass fields filling the row.
            HStack(alignment: .bottom, spacing: 10) {
                labeled("Date") {
                    DatePicker("", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.field).labelsHidden()
                        .glassField()
                }
                labeled("Time") {
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.field).labelsHidden()
                        .glassField()
                }
                labeled("Duration") {
                    Menu {
                        ForEach(durations, id: \.self) { d in
                            Button("\(d) min") { durationMinutes = d }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("\(durationMinutes) min").foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .glassField()
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

            // Google lets you opt out of a Meet link; Zoom/Teams always include one.
            if account?.provider == .google {
                Toggle(isOn: $addMeet) {
                    Label("Add Google Meet link", systemImage: "video")
                }
            } else if let p = account?.provider {
                Label("A \(p.name) link will be added", systemImage: "video")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Spacer()
                Button("Cancel", role: .cancel) { onDone() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Button(action: submit) {
                    if submitting { ProgressView().controlSize(.small) }
                    else { Text(isEditing ? "Update" : "Schedule") }
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

    private var accountLabel: String {
        guard let a = account else { return "Select account" }
        return "\(a.provider.name) · \(a.email)"
    }

    @ViewBuilder
    private var accountField: some View {
        if isEditing {
            // Account is fixed when editing an existing event.
            HStack { Text(accountLabel).lineLimit(1); Spacer(minLength: 0) }
                .foregroundStyle(.secondary)
                .glassField()
        } else {
            Menu {
                ForEach(model.accounts) { a in
                    Button { account = a } label: { Text("\(a.provider.name) · \(a.email)") }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(accountLabel).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).buttonStyle(.plain)
            .glassField()
        }
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
            let ok: Bool
            if let editing {
                ok = await model.updateMeeting(editing, title: title, start: start,
                                               durationMinutes: durationMinutes,
                                               attendees: emails, addMeet: addMeet)
            } else if let account {
                ok = await model.scheduleMeeting(on: account, title: title, start: start,
                                                 durationMinutes: durationMinutes,
                                                 attendees: emails, addMeet: addMeet)
            } else {
                ok = false
            }
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
    /// A fixed-height field with a Liquid Glass background (material fallback),
    /// so every field in the form lines up to the same size.
    @ViewBuilder
    func glassField() -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        let boxed = self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 34)
        if #available(macOS 26.0, *) {
            boxed.glassEffect(.regular, in: shape)
        } else {
            boxed.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(.quaternary))
        }
    }

    /// Liquid Glass capsule for the email chips.
    @ViewBuilder
    func glassChip() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.quaternary))
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
                .glassChip()
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
