import SwiftUI
import UniformTypeIdentifiers

/// One enrolled course: syllabus setup, then (after review) the dashboard.
/// Syllabus-based guidance waits for a reviewed syllabus; nothing else in
/// Agora does.
struct CourseDashboardView: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let courseId: String

    @State private var showImporter = false
    @State private var showNotAvailable = false
    @State private var errorMessage: String?
    @State private var confirmDeleteCourse = false
    @State private var documentToDelete: SyllabusDocumentSummary?
    @State private var notice: String?
    @State private var reviewDocumentId: ReviewTarget?
    @State private var pageRequest: PageRequest?

    private struct ReviewTarget: Identifiable { let id: String }
    private struct PageRequest: Identifiable {
        let id = UUID()
        let documentId: String
        let mimeType: String
        let page: Int
        let excerpt: String?
    }

    private var course: EnrolledCourse? { store.course(courseId) }
    private var isUploading: Bool { store.uploading.contains(courseId) }

    var body: some View {
        ScrollView {
            if let course {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    header(course)
                    if let notice { noticeBanner(notice) }
                    if let errorMessage { errorBanner(errorMessage) }
                    setupCard(course)
                    if course.status == .ready || course.status == .updateAvailable {
                        if let dashboard = store.dashboards[course.id] {
                            CourseDashboardSections(
                                dashboard: dashboard,
                                onViewPage: { pageRequest = PageRequest(documentId: $0, mimeType: $1, page: $2, excerpt: $3) },
                                onReviewUpdate: { reviewDocumentId = ReviewTarget(id: $0) }
                            )
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    if !course.documents.isEmpty { versions(course) }
                    removeCourseButton
                    Spacer(minLength: HokieChrome.contentBottomInset)
                }
                .padding(.horizontal, 20)
                .padding(.top, AgoraSpacing.sm)
            } else {
                Text("This course was removed.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 80)
            }
        }
        .scrollIndicators(.hidden)
        .hokieScreenBackground()
        .navigationTitle(course?.code ?? "Course")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .refreshable {
            await store.loadCourses(force: true)
            try? await store.loadDashboard(courseId: courseId)
        }
        .task(id: course?.status) {
            #if DEBUG
            openQAReviewIfRequested()
            #endif
            guard let course, course.status == .ready || course.status == .updateAvailable else { return }
            do { try await store.loadDashboard(courseId: course.id) } catch { errorMessage = error.localizedDescription }
        }
        .fullScreenCover(item: $reviewDocumentId) { target in
            SyllabusReviewView(documentId: target.id) {
                Task { try? await store.loadDashboard(courseId: courseId) }
            }
            .environmentObject(store)
            .environment(\.schoolTheme, theme)
        }
        .sheet(item: $pageRequest) { request in
            SyllabusPageView(documentId: request.documentId, mimeType: request.mimeType, page: request.page, excerpt: request.excerpt)
                .environmentObject(store)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .png, .jpeg]) { result in
            if case .success(let url) = result { Task { await upload(url: url) } }
        }
        .sheet(isPresented: $showNotAvailable) {
            if let course {
                SyllabusNotAvailableSheet(course: course) { allowed in
                    notice = allowed ? nil : "Reminder saved. Turn on notifications for Agora in Settings to get it."
                }
                .environmentObject(store)
                .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog("Remove \(course?.code ?? "course")?", isPresented: $confirmDeleteCourse, titleVisibility: .visible) {
            Button("Remove course and its syllabi", role: .destructive) { Task { await deleteCourse() } }
        } message: {
            Text("This deletes every uploaded version, the details read from them, and their reminders.")
        }
        .confirmationDialog("Delete this syllabus version?", isPresented: Binding(
            get: { documentToDelete != nil }, set: { if !$0 { documentToDelete = nil } }
        ), titleVisibility: .visible, presenting: documentToDelete) { document in
            Button("Delete version \(document.version)", role: .destructive) { Task { await deleteDocument(document) } }
        } message: { _ in
            Text("The file, the details read from it, and its reminders are removed from Agora.")
        }
        #if DEBUG
        .task { await runQAUploadIfRequested() }
        #endif
    }

    // MARK: - Header

    private func header(_ course: EnrolledCourse) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.code)
                .font(.largeTitle.weight(.bold))
                .tracking(-0.5)
                .foregroundStyle(AgoraPalette.brandInk)
                .accessibilityAddTraits(.isHeader)
            if !course.title.isEmpty {
                Text(course.title)
                    .font(.headline)
                    .foregroundStyle(AgoraPalette.brandInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("\(store.selectedTerm?.name ?? "") · \(sectionLabel) \(course.sectionCode) · \(course.instructorName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sectionLabel: String { theme.slug == SchoolTheme.virginiaTech.slug ? "CRN" : "Section" }

    // MARK: - Setup

    @ViewBuilder
    private func setupCard(_ course: EnrolledCourse) -> some View {
        if isUploading || course.status == .processing {
            card {
                HStack(spacing: AgoraSpacing.md) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reading your syllabus…").font(.headline)
                        Text("This can take up to a minute.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            switch course.status {
            case .needed:
                neededCard(course)
            case .reviewNeeded:
                reviewCard(course, title: "Review needed",
                           detail: "Check what Agora found against your syllabus. Syllabus-based guidance for this course turns on after you review it.")
            case .updateAvailable, .ready, .processing:
                EmptyView() // The dashboard shows a pending update itself.
            }
        }
    }

    private func neededCard(_ course: EnrolledCourse) -> some View {
        card {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                Label("Syllabus needed", systemImage: SyllabusStatus.needed.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Add your \(course.code) syllabus")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Agora uses it to find exam dates, office hours, grading, and course policies for this section. You can use the rest of Agora without it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if course.lastUploadFailed {
                    Text("The last upload couldn’t be processed. Try again, or upload a clearer copy.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { showImporter = true } label: {
                    Label("Upload syllabus", systemImage: "arrow.up.doc")
                }
                .buttonStyle(.agoraPrimary)
                Button { showNotAvailable = true } label: {
                    Text(course.syllabusRemindOn == nil ? "Syllabus not available yet" : "Change reminder")
                }
                .buttonStyle(.agoraSecondary)
                if let day = course.syllabusRemindOn {
                    Text("Agora will remind you on \(CalendarDay.text(day, weekday: true)).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("PDF, PNG, or JPEG. Your syllabus stays private to you. Agora reads its text on this device and sends that text to its AI provider to find dates and policies; you review everything before it’s used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reviewCard(_ course: EnrolledCourse, title: String, detail: String) -> some View {
        card {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                Label(title, systemImage: course.status.symbol)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let pending = course.pendingDocumentId {
                    Button("Review now") { reviewDocumentId = ReviewTarget(id: pending) }
                        .buttonStyle(.agoraPrimary)
                }
            }
        }
    }

    // MARK: - Versions

    private func versions(_ course: EnrolledCourse) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Syllabus versions", icon: "doc.on.doc")
            VStack(spacing: 0) {
                ForEach(Array(course.documents.enumerated()), id: \.element.id) { index, document in
                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                    HStack(alignment: .center, spacing: AgoraSpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version \(document.version)").font(.subheadline.weight(.semibold))
                            Text(versionDetail(document, course: course))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: AgoraSpacing.sm)
                        Button(role: .destructive) { documentToDelete = document } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Delete version \(document.version)")
                    }
                    .padding(.leading, AgoraSpacing.lg)
                    .padding(.trailing, AgoraSpacing.sm)
                    .padding(.vertical, AgoraSpacing.xs)
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
            if course.status == .ready || course.status == .updateAvailable {
                Button { showImporter = true } label: {
                    Label("Upload a new version", systemImage: "arrow.up.doc")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentText)
                .frame(minHeight: 44)
            }
        }
    }

    private func versionDetail(_ document: SyllabusDocumentSummary, course: EnrolledCourse) -> String {
        let state: String
        switch document.processingState {
        case "reviewed": state = document.id == course.currentDocumentId ? "In use" : "Reviewed"
        case "review_needed": state = "Waiting for review"
        case "processing": state = "Processing"
        default: state = "Couldn’t be processed"
        }
        let uploaded = document.uploadedDate.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        return [state, "\(document.pageCount) page\(document.pageCount == 1 ? "" : "s")", uploaded]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var removeCourseButton: some View {
        Button(role: .destructive) { confirmDeleteCourse = true } label: {
            Text("Remove course")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
    }

    // MARK: - Pieces

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(AgoraSpacing.xl - 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AgoraSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassInset(cornerRadius: AgoraRadius.inset)
    }

    private func noticeBanner(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(AgoraSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassInset(cornerRadius: AgoraRadius.inset)
    }

    // MARK: - Actions

    private func upload(url: URL) async {
        guard let course else { return }
        errorMessage = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let mimeType = SyllabusTextExtractor.mimeType(for: url) else {
            errorMessage = SyllabusTextExtractor.ExtractionError.unsupportedType.localizedDescription
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let response = try await store.uploadSyllabus(for: course, data: data, mimeType: mimeType, fileName: url.lastPathComponent)
            if response.duplicate {
                notice = "You’ve already uploaded this exact file (version \(response.document.version))."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCourse() async {
        guard let course else { return }
        do {
            try await store.deleteCourse(course)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDocument(_ document: SyllabusDocumentSummary) async {
        do {
            try await store.deleteDocument(document)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// `-AgoraOpenReview` opens the pending review for visual QA.
    private func openQAReviewIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-AgoraOpenReview"), let pending = course?.pendingDocumentId else { return }
        reviewDocumentId = ReviewTarget(id: pending)
    }

    /// `-AgoraQAUploadFile <path>` uploads a local QA file through the same
    /// path as the file picker, since the simulator tools here can't tap.
    private func runQAUploadIfRequested() async {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AgoraQAUploadFile"), args.indices.contains(i + 1),
              let course, course.status == .needed || course.status == .ready || course.status == .updateAvailable,
              !course.documents.contains(where: { $0.fileName == URL(fileURLWithPath: args[i + 1]).lastPathComponent })
        else { return }
        await upload(url: URL(fileURLWithPath: args[i + 1]))
    }
    #endif
}

/// "Syllabus not available yet": choose when to be reminded.
struct SyllabusNotAvailableSheet: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.dismiss) private var dismiss
    let course: EnrolledCourse
    let onSaved: (Bool) -> Void

    @State private var day = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var range: ClosedRange<Date> {
        let start = Calendar.current.startOfDay(for: Date())
        let end = store.selectedTerm.flatMap { CalendarDay.date($0.finalsEnd ?? $0.classesEnd) } ?? start
        return start...max(start, end)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
                Text("No problem. Many instructors post syllabi close to the first day. Agora will remind you to add it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DatePicker("Remind me on", selection: $day, in: range, displayedComponents: .date)
                    .font(.body.weight(.medium))
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    Task { await save(dayString: CalendarDay.string(from: day)) }
                } label: {
                    if isSaving { ProgressView() } else { Text("Save reminder") }
                }
                .buttonStyle(.agoraPrimary)
                .disabled(isSaving)
                if course.syllabusRemindOn != nil {
                    Button("Turn off reminder") { Task { await save(dayString: nil) } }
                        .buttonStyle(.agoraSecondary)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Syllabus not available yet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func save(dayString: String?) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let allowed = try await store.setSyllabusReminder(course, on: dayString)
            onSaved(dayString == nil || allowed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
