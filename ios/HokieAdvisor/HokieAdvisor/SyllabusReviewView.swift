import SwiftUI

/// Review extracted details against the syllabus before Agora uses them.
/// Nothing drives reminders or the dashboard until it's confirmed here.
struct SyllabusReviewView: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.schoolTheme) private var theme
    let documentId: String
    var onFinished: () -> Void = {}

    @State private var detail: DocumentDetail?
    @State private var errorMessage: String?
    @State private var busyFactId: String?
    @State private var isFinishing = false
    @State private var correcting: SyllabusFact?
    @State private var viewingPage: (page: Int, excerpt: String?)?

    private var facts: [SyllabusFact] { detail?.facts ?? [] }
    private var pendingCount: Int { facts.filter { $0.reviewState == "pending" }.count }
    private var bulkEligible: Int {
        facts.filter { $0.reviewState == "pending" && $0.issues.isEmpty && $0.evidence == "verified" && !$0.isDated && $0.value.date == nil }.count
    }
    private var blocked: Bool { detail?.document.findings.contains { $0.code == "term_mismatch" } ?? false }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    if let detail {
                        intro(detail)
                        findings(detail)
                        if let changes = detail.changes { changesSection(changes) }
                        ForEach(groupedFacts, id: \.category) { group in
                            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                                SectionLabel(title: FactCategory.title(group.category), icon: "list.bullet")
                                ForEach(group.facts) { fact in
                                    ReviewFactCard(
                                        fact: fact,
                                        correction: detail.correction(for: fact),
                                        isBusy: busyFactId == fact.id,
                                        onDecision: { decision in Task { await decide(fact, decision) } },
                                        onCorrect: { correcting = fact },
                                        onRemoveCorrection: { Task { await removeCorrection(fact) } },
                                        onViewPage: { viewingPage = (fact.page, fact.excerpt) }
                                    )
                                }
                            }
                        }
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary).padding(.top, 60)
                    } else {
                        ProgressView("Loading what Agora found…").frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, AgoraSpacing.lg)
                .padding(.bottom, 140)
            }
            .scrollIndicators(.hidden)
            .hokieScreenBackground()
            .safeAreaInset(edge: .bottom) { if detail != nil { footer } }
            .navigationTitle("Review syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .task { await load() }
        .sheet(item: $correcting) { fact in
            FactCorrectionSheet(fact: fact, existing: detail?.correction(for: fact)) { await load() }
                .environmentObject(store)
        }
        .sheet(isPresented: Binding(get: { viewingPage != nil }, set: { if !$0 { viewingPage = nil } })) {
            if let viewingPage, let detail {
                SyllabusPageView(documentId: detail.document.id, mimeType: detail.document.mimeType,
                                 page: viewingPage.page, excerpt: viewingPage.excerpt)
                    .environmentObject(store)
            }
        }
    }

    private var groupedFacts: [(category: String, facts: [SyllabusFact])] {
        FactCategory.order.compactMap { category in
            let items = facts.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    // MARK: - Sections

    private func intro(_ detail: DocumentDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(detail.course.code) · Version \(detail.document.version)")
                .font(.title2.weight(.bold))
                .foregroundStyle(AgoraPalette.brandInk)
            Text("Check each item against your syllabus. Agora only uses what you confirm. If something is wrong, correct it; your correction is kept separately from what the document says.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func findings(_ detail: DocumentDetail) -> some View {
        let items = detail.document.findings
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                ForEach(items) { finding in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(finding.message)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            if finding.code == "not_found", let missing = missingCategories(detail) {
                                Text(missing).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let page = finding.page {
                                Button("View page \(page)") { viewingPage = (page, nil) }
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(theme.accentText)
                            }
                        }
                    } icon: {
                        Image(systemName: finding.code == "term_mismatch" || finding.code == "ai_directed_text"
                              ? "exclamationmark.triangle" : "info.circle")
                            .foregroundStyle(finding.code == "term_mismatch" ? .orange : .secondary)
                    }
                    .padding(AgoraSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassInset(cornerRadius: AgoraRadius.inset)
                }
            }
        }
    }

    private func missingCategories(_ detail: DocumentDetail) -> String? {
        let present = Set(detail.facts.map(\.category))
        let missing = ["exam", "grading_weight", "office_hours", "attendance", "late_work"].filter { !present.contains($0) }
        return missing.isEmpty ? nil : missing.map(FactCategory.title).joined(separator: ", ")
    }

    private func changesSection(_ changes: DocumentChanges) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Changes from version \(changes.comparedWithVersion)", icon: "arrow.triangle.2.circlepath")
            if changes.changed.isEmpty && changes.added.isEmpty && changes.removed.isEmpty {
                Text("No differences from the version you reviewed.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                ForEach(changes.changed) { change in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.label).font(.subheadline.weight(.semibold))
                        ForEach(Array((change.fields ?? []).enumerated()), id: \.offset) { _, field in
                            Text("\(fieldName(field.field)): \(display(field.field, field.before)) → \(display(field.field, field.after))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if let ids = change.affectedReminderIds, !ids.isEmpty {
                            Text("Your reminder for this will need to be confirmed again.")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                ForEach(changes.added) { Text("New: \($0.label)").font(.footnote) }
                ForEach(changes.removed) { change in
                    Text("No longer in the syllabus: \(change.label)").font(.footnote)
                }
            }
            .padding(AgoraSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: AgoraRadius.card)
            Text("Until you finish this review, Agora keeps using the details you confirmed in version \(changes.comparedWithVersion).")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fieldName(_ field: String) -> String {
        ["date": "Date", "relative_timing": "Timing", "start_time": "Start", "end_time": "End", "exam_format": "Format",
         "weight_percent": "Weight", "location": "Location", "summary": "Details"][field] ?? field
    }

    private func display(_ field: String, _ value: JSONScalar) -> String {
        guard let text = value.text else { return "none" }
        switch field {
        case "date": return CalendarDay.text(text, weekday: true)
        case "start_time", "end_time": return FactValue.clock(text)
        case "weight_percent": return "\(text)%"
        default: return text
        }
    }

    private var footer: some View {
        VStack(spacing: AgoraSpacing.sm) {
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if blocked {
                Text("This syllabus is for a different term, so it can’t be used. Upload the current term’s syllabus for your section.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if bulkEligible > 0 {
                    Button("Confirm \(bulkEligible) policy item\(bulkEligible == 1 ? "" : "s") with no flags") {
                        Task { await confirmUnflagged() }
                    }
                    .buttonStyle(.agoraSecondary)
                }
                Button {
                    Task { await finish() }
                } label: {
                    if isFinishing { ProgressView() } else {
                        Text(pendingCount == 0 ? "Finish review" : "\(pendingCount) item\(pendingCount == 1 ? "" : "s") left to review")
                    }
                }
                .buttonStyle(.agoraPrimary)
                .disabled(pendingCount > 0 || isFinishing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, AgoraSpacing.md)
        .background(.bar)
    }

    // MARK: - Actions

    private func load() async {
        do {
            detail = try await CourseCompanionAPI.document(documentId)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func decide(_ fact: SyllabusFact, _ decision: String) async {
        busyFactId = fact.id
        defer { busyFactId = nil }
        do {
            try await CourseCompanionAPI.reviewFact(fact.id, decision: decision)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCorrection(_ fact: SyllabusFact) async {
        do {
            try await CourseCompanionAPI.removeCorrection(fact.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmUnflagged() async {
        do {
            _ = try await CourseCompanionAPI.confirmUnflagged(documentId: documentId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() async {
        isFinishing = true
        defer { isFinishing = false }
        do {
            _ = try await CourseCompanionAPI.completeReview(documentId: documentId)
            await store.reconcileReminders()
            await store.loadCourses(force: true)
            onFinished()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Fact card

private struct ReviewFactCard: View {
    @Environment(\.schoolTheme) private var theme
    let fact: SyllabusFact
    let correction: CorrectionRecord?
    let isBusy: Bool
    let onDecision: (String) -> Void
    let onCorrect: () -> Void
    let onRemoveCorrection: () -> Void
    let onViewPage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            FactSummary(fact: fact, value: fact.value)

            if let correction {
                CorrectionNote(corrected: correction.corrected, note: correction.note, onRemove: onRemoveCorrection)
            }

            let issues = fact.issues.compactMap { FactIssue.text($0, fact: fact) }
            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            ExcerptButton(excerpt: fact.excerpt, page: fact.page, evidence: fact.evidence, action: onViewPage)

            decisionRow
        }
        .padding(AgoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card)
        .opacity(isBusy ? 0.6 : 1)
    }

    @ViewBuilder
    private var decisionRow: some View {
        switch fact.reviewState {
        case "confirmed", "rejected":
            HStack {
                Label(fact.reviewState == "confirmed" ? (correction == nil ? "Confirmed" : "Confirmed with your correction") : "Marked not right",
                      systemImage: fact.reviewState == "confirmed" ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(fact.reviewState == "confirmed" ? .green : .secondary)
                Spacer()
                Button("Undo") { onDecision("undo") }
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
        default:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AgoraSpacing.sm) { buttons }
                VStack(spacing: AgoraSpacing.sm) { buttons }
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        if fact.isBlocked {
            Button("Not usable") { onDecision("reject") }.buttonStyle(.agoraSecondary)
        } else {
            Button("Confirm") { onDecision("confirm") }
                .buttonStyle(.agoraPrimary)
                .disabled(fact.needsCorrectionToConfirm && correction == nil)
            Button("Correct") { onCorrect() }.buttonStyle(.agoraSecondary)
            Button("Not right") { onDecision("reject") }.buttonStyle(.agoraSecondary)
        }
    }
}

/// The fact's content: label, date/time, format, rules, qualifiers.
struct FactSummary: View {
    let fact: SyllabusFact
    let value: FactValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fact.label)
                .font(.headline)
                .foregroundStyle(AgoraPalette.brandInk)
                .fixedSize(horizontal: false, vertical: true)
            let when = [value.dateLabel ?? value.relativeTiming ?? value.dateText ?? value.recurrenceText, value.timeLabel]
                .compactMap { $0 }.joined(separator: " · ")
            if !when.isEmpty {
                Text(when).font(.subheadline.weight(.medium)).monospacedDigit()
            }
            if let weight = value.weightPercent {
                Text("\(weight.formatted())% of the grade").font(.subheadline.weight(.medium))
            }
            let details = [fact.category == "exam" ? value.examFormatLabel : nil, value.location, value.contact,
                           value.appointment == "required" ? "Appointment required" : (value.appointment == "optional" ? "Appointment optional" : nil)]
                .compactMap { $0 }
            if !details.isEmpty {
                Text(details.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let summary = value.summary, fact.category != "grading_weight" {
                Text(summary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let restrictions = value.restrictions, !restrictions.isEmpty {
                Text("Rules: " + restrictions.joined(separator: "; "))
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !fact.qualifiers.isEmpty {
                Text("Syllabus says: " + fact.qualifiers.map { "“\($0)”" }.joined(separator: ", "))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Your correction" beside the document's value, never merged into it.
struct CorrectionNote: View {
    let corrected: [String: JSONScalar]
    let note: String?
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Your correction", systemImage: "pencil")
                .font(.footnote.weight(.semibold))
            ForEach(corrected.keys.sorted(), id: \.self) { key in
                if let text = corrected[key]?.text {
                    Text("\(Self.name(key)): \(Self.display(key, text))").font(.footnote)
                }
            }
            if let note, !note.isEmpty {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
            if let onRemove {
                Button("Remove correction", action: onRemove).font(.footnote.weight(.medium))
            }
        }
        .padding(AgoraSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassInset(cornerRadius: AgoraRadius.inset)
    }

    static func name(_ key: String) -> String {
        switch key {
        case "date": return "Date"
        case "startTime", "start_time": return "Start"
        case "endTime", "end_time": return "End"
        case "location": return "Location"
        case "weightPercent", "weight_percent": return "Weight"
        default: return "Details"
        }
    }

    static func display(_ key: String, _ text: String) -> String {
        switch key {
        case "date": return CalendarDay.text(text, weekday: true)
        case "startTime", "start_time", "endTime", "end_time": return FactValue.clock(text)
        case "weightPercent", "weight_percent": return "\(text)%"
        default: return text
        }
    }
}

/// The supporting excerpt with its page; opens the original page.
struct ExcerptButton: View {
    @Environment(\.schoolTheme) private var theme
    let excerpt: String
    let page: Int
    let evidence: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text("“\(excerpt)”")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Text(evidence == "not_found" ? "Not found in the document" : "Page \(page)")
                    if evidence != "not_found" {
                        Text("· View").foregroundStyle(theme.accentText)
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(evidence == "not_found" ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AgoraSpacing.md)
            .glassInset(cornerRadius: AgoraRadius.inset - 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(evidence == "not_found")
        .accessibilityLabel("Source: page \(page). \(excerpt)")
        .accessibilityHint(evidence == "not_found" ? "" : "Opens the page in your syllabus")
    }
}

// MARK: - Correction sheet

struct FactCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let fact: SyllabusFact
    let existing: CorrectionRecord?
    let onSaved: () async -> Void

    @State private var useDate = false
    @State private var date = Date()
    @State private var useTime = false
    @State private var start = Date()
    @State private var location = ""
    @State private var weight = ""
    @State private var text = ""
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FactSummary(fact: fact, value: fact.value)
                } header: {
                    Text("The syllabus says")
                } footer: {
                    Text("Your correction is saved privately alongside this, not in place of it.")
                }
                if fact.isDated {
                    Section("Date and time") {
                        Toggle("Set the date", isOn: $useDate)
                        if useDate { DatePicker("Date", selection: $date, displayedComponents: .date) }
                        Toggle("Set the start time", isOn: $useTime)
                        if useTime { DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute) }
                    }
                }
                if fact.category == "office_hours" || fact.category == "exam" {
                    Section("Location") { TextField("Location", text: $location) }
                }
                if fact.category == "grading_weight" {
                    Section("Weight") { TextField("Percent of grade", text: $weight).keyboardType(.decimalPad) }
                }
                if !fact.isDated && fact.category != "grading_weight" {
                    Section("Corrected details") { TextField("What it should say", text: $text, axis: .vertical) }
                }
                Section("Note (optional)") { TextField("Where this came from, e.g. a Canvas announcement", text: $note, axis: .vertical) }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Correct \(fact.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }.disabled(isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        if let d = fact.value.date.flatMap(CalendarDay.date) {
            date = Calendar.current.date(from: Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: d)) ?? date
        }
        location = fact.value.location ?? ""
        if let w = fact.value.weightPercent { weight = w.formatted() }
        note = existing?.note ?? ""
    }

    private func save() async {
        var correction = CourseCompanionAPI.Correction()
        if useDate { correction.date = CalendarDay.string(from: date) }
        if useTime {
            let c = Calendar.current.dateComponents([.hour, .minute], from: start)
            correction.startTime = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }
        let trimmedLocation = location.trimmingCharacters(in: .whitespaces)
        if !trimmedLocation.isEmpty, trimmedLocation != fact.value.location { correction.location = trimmedLocation }
        if let w = Double(weight), w != fact.value.weightPercent { correction.weightPercent = w }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty { correction.text = trimmedText }

        isSaving = true
        defer { isSaving = false }
        do {
            try await CourseCompanionAPI.correctFact(fact.id, correction: correction, note: note.isEmpty ? nil : note)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
