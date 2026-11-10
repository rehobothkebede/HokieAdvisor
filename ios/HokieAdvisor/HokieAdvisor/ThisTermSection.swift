import SwiftUI

/// Home's "This term" section: the student's chosen term, registration
/// guidance, and (from stage 2) their enrolled courses.
struct ThisTermSection: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.schoolTheme) private var theme
    @State private var showRegistration = false
    @State private var showAddCourse = false
    @State private var openCourseId: String?

    var body: some View {
        Group {
            if !store.isAvailable {
                EmptyView()
            } else {
                stateContent
            }
        }
        .task {
            await store.load()
            #if DEBUG
            // `-AgoraOpenRegistration` opens the guide for visual QA.
            if ProcessInfo.processInfo.arguments.contains("-AgoraOpenRegistration") { showRegistration = true }
            #endif
        }
        .task(id: store.selectedTerm?.termKey) {
            await store.loadCourses()
            #if DEBUG
            openQACourseIfRequested()
            #endif
        }
        .sheet(isPresented: $showAddCourse) {
            AddCourseView()
                .environmentObject(store)
                .environment(\.schoolTheme, theme)
        }
        .navigationDestination(item: $openCourseId) { id in
            CourseDashboardView(courseId: id)
                .environmentObject(store)
        }
        .sheet(isPresented: $showRegistration) {
            RegistrationGuideView(termKey: store.overview?.registration?.termKey ?? store.selectedTerm?.termKey)
                .environment(\.schoolTheme, theme)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        Group {
            switch store.state {
            case .idle, .loading where store.overview == nil:
                placeholder
            case .unsupported:
                EmptyView() // No dead ends for schools Agora doesn't cover yet.
            case .failed(let message) where store.overview == nil:
                failure(message)
            default:
                content
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            header
            registrationRow
            courseList
        }
    }

    // MARK: - Courses

    @ViewBuilder
    private var courseList: some View {
        let courses = store.coursesTermKey == store.selectedTerm?.termKey ? store.courses : []
        if !courses.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                    courseRow(course)
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
        } else if let error = store.coursesError {
            Text("Couldn’t load your courses. \(error)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !store.isLoadingCourses {
            Text("Add the courses you’re taking in \(store.selectedTerm?.name ?? "this term") to set up each syllabus.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        Button { showAddCourse = true } label: {
            Label("Add a course", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.accentText)
    }

    private func courseRow(_ course: EnrolledCourse) -> some View {
        Button { openCourseId = course.id } label: {
            HStack(spacing: AgoraSpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.code)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AgoraPalette.brandInk)
                    if !course.title.isEmpty {
                        Text(course.title)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statusLabel(course)
                }
                Spacer(minLength: AgoraSpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AgoraSpacing.lg)
            .padding(.vertical, AgoraSpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this course")
    }

    private func statusLabel(_ course: EnrolledCourse) -> some View {
        let uploading = store.uploading.contains(course.id)
        let status: SyllabusStatus = uploading ? .processing : course.status
        let needsAction = status == .needed || status == .reviewNeeded || status == .updateAvailable
        var text = status.label
        if status == .needed, let day = course.syllabusRemindOn {
            text = "Not available yet · reminder \(CalendarDay.text(day, year: false))"
        }
        return Label(text, systemImage: status.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(needsAction ? theme.accentText : .secondary)
            .labelStyle(.titleAndIcon)
    }

    #if DEBUG
    /// `-AgoraOpenCourse "CS 2114"` opens that course for visual QA.
    private func openQACourseIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AgoraOpenCourse"), args.indices.contains(i + 1) else {
            if args.contains("-AgoraOpenAddCourse") { showAddCourse = true }
            return
        }
        openCourseId = store.courses.first { $0.code == args[i + 1] }?.id
    }
    #endif

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(title: "This term", icon: "calendar")
            Spacer(minLength: AgoraSpacing.sm)
            if store.terms.count > 1 {
                Menu {
                    Picker("Term", selection: Binding(
                        get: { store.selectedTerm?.termKey ?? "" },
                        set: { store.selectedTermKey = $0 }
                    )) {
                        ForEach(store.terms) { term in
                            Text(term.name).tag(term.termKey)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.selectedTerm?.name ?? "Choose term")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Term: \(store.selectedTerm?.name ?? "not chosen")")
                .accessibilityHint("Changes the term shown in this section")
            } else if let term = store.selectedTerm {
                Text(term.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var registrationRow: some View {
        Button { showRegistration = true } label: {
            HStack(spacing: AgoraSpacing.md) {
                Image(systemName: "calendar.badge.clock")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(registrationTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(registrationDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AgoraSpacing.lg)
            .padding(.vertical, AgoraSpacing.md)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens registration dates and how add, drop, and withdrawal work")
    }

    private var registrationTitle: String {
        if let registration = store.overview?.registration {
            return "Registration · \(registration.termName)"
        }
        return "Registration guide"
    }

    private var registrationDetail: String {
        guard let deadline = store.overview?.registration?.deadline else {
            return "How Course Request, Add/Drop, and withdrawal work."
        }
        let verb = deadline.state == "open" ? "Open now" : deadline.dateText
        return "\(deadline.label) · \(verb)"
    }

    // MARK: - States

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "This term", icon: "calendar")
            RoundedRectangle(cornerRadius: AgoraRadius.inset + 2, style: .continuous)
                .fill(AgoraPalette.surface)
                .frame(height: 64)
                .overlay(ProgressView())
                .accessibilityLabel("Loading this term")
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "This term", icon: "calendar")
            HStack(spacing: AgoraSpacing.md) {
                Text("Couldn’t load this term. \(message)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Retry") { Task { await store.load(force: true) } }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, AgoraSpacing.lg)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
    }
}
