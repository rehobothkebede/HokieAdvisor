import SwiftUI

/// The current-course dashboard, built only from facts the student confirmed
/// in the reviewed syllabus version for this exact section and term.
struct CourseDashboardSections: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.schoolTheme) private var theme
    let dashboard: CourseDashboard
    let onViewPage: (_ documentId: String, _ mimeType: String, _ page: Int, _ excerpt: String?) -> Void
    let onReviewUpdate: (_ documentId: String) -> Void

    @State private var errorMessage: String?
    @State private var notice: String?

    private var document: SyllabusDocumentSummary? { dashboard.currentDocument }

    var body: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
            if let pending = dashboard.pendingDocument { updateBanner(pending) }
            reconfirmCards
            if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
            if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            nextCard
            datedSection
            if !dashboard.undated.isEmpty { undatedSection }
            gradingSection.id("grading")
            factSection("Office hours and contact", categories: ["office_hours", "contact"]).id("policies")
            factSection("Attendance and participation", categories: ["attendance", "participation"])
            factSection("Late work and makeups", categories: ["late_work", "makeup"])
            factSection("Materials and requirements", categories: ["materials", "requirement", "restriction"])
            sourceFooter
        }
    }

    // MARK: - Update and reminder changes

    private func updateBanner(_ pending: SyllabusDocumentSummary) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
            Label("Version \(pending.version) is waiting for review", systemImage: SyllabusStatus.updateAvailable.symbol)
                .font(.headline)
            Text("Agora keeps showing version \(document?.version ?? 1) until you review the changes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Review changes") { onReviewUpdate(pending.id) }
                .buttonStyle(.agoraPrimary)
        }
        .padding(AgoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    @ViewBuilder
    private var reconfirmCards: some View {
        let reminders = dashboard.reminders.filter { $0.state == "needs_reconfirm" }
        ForEach(reminders) { reminder in
            VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                Label("A date changed", systemImage: "bell.badge")
                    .font(.headline)
                Text("“\(reminder.title)” changed in the new syllabus version. This reminder is paused until you choose.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack { reconfirmButtons(reminder) }
                    VStack { reconfirmButtons(reminder) }
                }
            }
            .padding(AgoraSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }

    @ViewBuilder
    private func reconfirmButtons(_ reminder: CourseReminder) -> some View {
        Button("Use the new date") { Task { await resolve(reminder, move: true) } }
            .buttonStyle(.agoraPrimary)
        Button("Remove reminder") { Task { await resolve(reminder, move: false) } }
            .buttonStyle(.agoraSecondary)
    }

    // MARK: - Next and dated items

    @ViewBuilder
    private var nextCard: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Next confirmed date", icon: "calendar")
            if let next = dashboard.next {
                VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                    FactSummary(fact: next, value: next.shown)
                    if let days = daysUntil(next.shown.date) {
                        Text(days).font(.footnote.weight(.semibold)).foregroundStyle(theme.accentText)
                    }
                    if next.correction != nil {
                        Label("Includes your correction", systemImage: "pencil").font(.footnote).foregroundStyle(.secondary)
                    }
                    reminderControl(for: next)
                    sourceLink(next)
                }
                .padding(AgoraSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassSurface(cornerRadius: AgoraRadius.card)
            } else {
                Text("No confirmed upcoming exam or deadline.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var datedSection: some View {
        let dated = dashboard.facts(["exam", "assignment_deadline"]).filter { $0.shown.date != nil && $0.id != dashboard.next?.id }
        if !dated.isEmpty {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                SectionLabel(title: "Exams and deadlines", icon: "list.bullet")
                VStack(spacing: 0) {
                    ForEach(Array(dated.sorted { ($0.shown.date ?? "") < ($1.shown.date ?? "") }.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                            FactSummary(fact: fact, value: fact.shown)
                            reminderControl(for: fact)
                            sourceLink(fact)
                        }
                        .padding(AgoraSpacing.lg)
                    }
                }
                .glassSurface(cornerRadius: AgoraRadius.card)
            }
        }
    }

    private var undatedSection: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Not scheduled yet", icon: "questionmark.circle")
            Text("The syllabus doesn’t give calendar dates for these. Agora won’t guess; add one with a correction when your instructor announces it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(dashboard.undated.enumerated()), id: \.element.id) { index, fact in
                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                    VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                        FactSummary(fact: fact, value: fact.shown)
                        sourceLink(fact)
                    }
                    .padding(AgoraSpacing.lg)
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }

    // MARK: - Grading and policies

    @ViewBuilder
    private var gradingSection: some View {
        let weights = dashboard.facts(["grading_weight"])
        if !weights.isEmpty {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                SectionLabel(title: "Grading breakdown", icon: "chart.pie")
                VStack(spacing: 0) {
                    ForEach(Array(weights.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                        Button { open(fact) } label: {
                            HStack {
                                Text(fact.label).font(.subheadline)
                                if fact.correction != nil {
                                    Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
                                        .accessibilityLabel("Your correction")
                                }
                                Spacer()
                                Text(fact.shown.weightPercent.map { "\($0.formatted())%" } ?? "Not stated")
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, AgoraSpacing.lg)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows where this is in your syllabus")
                    }
                }
                .glassSurface(cornerRadius: AgoraRadius.card)
                let total = weights.compactMap(\.shown.weightPercent).reduce(0, +)
                Text(abs(total - 100) < 0.5 ? "Total 100%" : "These add up to \(total.formatted())%, not 100%. Check the syllabus.")
                    .font(.footnote)
                    .foregroundStyle(abs(total - 100) < 0.5 ? .secondary : Color.orange)
                    .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder
    private func factSection(_ title: String, categories: Set<String>) -> some View {
        let facts = dashboard.facts(categories)
        if !facts.isEmpty {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                SectionLabel(title: title, icon: "doc.text")
                VStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { index, fact in
                        if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                            FactSummary(fact: fact, value: fact.shown)
                            if let correction = fact.correction {
                                CorrectionNote(corrected: correction.corrected, note: correction.note)
                            }
                            sourceLink(fact)
                        }
                        .padding(AgoraSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .glassSurface(cornerRadius: AgoraRadius.card)
            }
        }
    }

    private var sourceFooter: some View {
        Text("From your reviewed syllabus\(document.map { ", version \($0.version)" } ?? ""). Instructors can change details during the term; follow their announcements.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func reminderControl(for fact: SyllabusFact) -> some View {
        let existing = dashboard.reminders.filter { $0.factId == fact.id && $0.state == "active" }
        if let reminder = existing.first {
            HStack {
                Label("Reminder: \(reminder.leadLabel.lowercased())", systemImage: "bell.fill")
                    .font(.footnote.weight(.medium))
                Spacer()
                Button("Remove") { Task { await removeReminder(reminder) } }
                    .font(.footnote)
                    .frame(minHeight: 44)
            }
        } else if fact.shown.date != nil {
            Menu {
                Button("A week before") { Task { await addReminder(fact, lead: "week_before") } }
                Button("The day before") { Task { await addReminder(fact, lead: "day_before") } }
                Button("The morning of") { Task { await addReminder(fact, lead: "morning_of") } }
            } label: {
                Label("Remind me", systemImage: "bell")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accentText)
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Optional. Adds a notification on this device.")
        }
    }

    private func sourceLink(_ fact: SyllabusFact) -> some View {
        Button { open(fact) } label: {
            Text("Page \(fact.page) of your syllabus · View")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the page this came from")
    }

    private func open(_ fact: SyllabusFact) {
        guard let document else { return }
        onViewPage(document.id, document.mimeType, fact.page, fact.excerpt)
    }

    private func daysUntil(_ day: String?) -> String? {
        guard let day, let date = CalendarDay.date(day) else { return nil }
        let today = CalendarDay.date(CalendarDay.string(from: Date())) ?? date
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: today, to: date).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        default: return days > 1 ? "In \(days) days" : nil
        }
    }

    private func addReminder(_ fact: SyllabusFact, lead: String) async {
        do {
            let allowed = try await store.addReminder(fact: fact, lead: lead)
            notice = allowed ? nil : "Reminder saved. Turn on notifications for Agora in Settings to receive it."
            try await store.loadDashboard(courseId: dashboard.course.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeReminder(_ reminder: CourseReminder) async {
        do {
            try await store.deleteReminder(reminder)
            try await store.loadDashboard(courseId: dashboard.course.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolve(_ reminder: CourseReminder, move: Bool) async {
        do {
            try await store.resolveReminder(reminder, moveToNewDate: move)
            try await store.loadDashboard(courseId: dashboard.course.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
