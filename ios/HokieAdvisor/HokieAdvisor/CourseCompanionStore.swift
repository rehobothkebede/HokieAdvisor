import Combine
import Foundation

/// State for the Home "This term" section and the screens it opens.
@MainActor
final class CourseCompanionStore: ObservableObject {
    enum LoadState: Equatable {
        case idle, loading, loaded, unsupported
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var overview: CoursesOverview?
    /// The student's chosen term; falls back to the term in session.
    @Published var selectedTermKey: String? {
        didSet { UserDefaults.standard.set(selectedTermKey, forKey: Self.termKeyDefaultsKey) }
    }

    private static let termKeyDefaultsKey = "courseCompanionSelectedTermKey"

    init() {
        selectedTermKey = UserDefaults.standard.string(forKey: Self.termKeyDefaultsKey)
    }

    var terms: [AcademicTerm] { overview?.terms ?? [] }

    var selectedTerm: AcademicTerm? {
        terms.first { $0.termKey == selectedTermKey } ?? terms.first { $0.termKey == overview?.currentTermKey }
    }

    var isAvailable: Bool {
        #if DEBUG
        // Visual QA runs without a backend unless pointed at the local QA server.
        if ProcessInfo.processInfo.arguments.contains("-HokieVisualQA"),
           CourseCompanionAPI.debugOverride == nil {
            return false
        }
        #endif
        return true
    }

    // MARK: - Courses (stage 2)

    @Published private(set) var courses: [EnrolledCourse] = []
    @Published private(set) var coursesTermKey: String?
    @Published private(set) var coursesError: String?
    @Published private(set) var isLoadingCourses = false
    /// Courses whose syllabus is being read or uploaded from this device.
    @Published private(set) var uploading: Set<String> = []

    func course(_ id: String) -> EnrolledCourse? { courses.first { $0.id == id } }

    func loadCourses(force: Bool = false) async {
        guard let termKey = selectedTerm?.termKey else { return }
        if !force, coursesTermKey == termKey, coursesError == nil { return }
        isLoadingCourses = true
        defer { isLoadingCourses = false }
        do {
            let result = try await CourseCompanionAPI.listCourses(termKey: termKey)
            guard result.termKey == selectedTerm?.termKey else { return } // term changed meanwhile
            courses = result.courses
            coursesTermKey = result.termKey
            coursesError = nil
            await CourseReminderScheduler.reconcileSyllabusReminders(termKey: termKey, courses: result.courses)
            await reconcileReminders()
        } catch {
            coursesError = error.localizedDescription
        }
    }

    func addCourse(_ course: CourseCompanionAPI.NewCourse) async throws {
        _ = try await CourseCompanionAPI.addCourse(course)
        await loadCourses(force: true)
    }

    func deleteCourse(_ course: EnrolledCourse) async throws {
        let result = try await CourseCompanionAPI.deleteCourse(courseId: course.id)
        CourseReminderScheduler.remove(identifiers:
            [CourseReminderScheduler.syllabusIdentifier(termKey: course.termKey, courseId: course.id)]
            + (result.deletedReminderIds ?? []).map(CourseReminderScheduler.factIdentifier))
        await loadCourses(force: true)
    }

    func deleteDocument(_ document: SyllabusDocumentSummary) async throws {
        let result = try await CourseCompanionAPI.deleteDocument(documentId: document.id)
        fileCache[document.id] = nil
        dashboards[document.courseId] = nil
        CourseReminderScheduler.remove(identifiers: (result.deletedReminderIds ?? []).map(CourseReminderScheduler.factIdentifier))
        await loadCourses(force: true)
    }

    /// "Syllabus not available yet": saves the reminder date and schedules a
    /// local notification if the student allows notifications.
    @discardableResult
    func setSyllabusReminder(_ course: EnrolledCourse, on day: String?) async throws -> Bool {
        try await CourseCompanionAPI.setSyllabusReminder(courseId: course.id, remindOn: day)
        let identifier = CourseReminderScheduler.syllabusIdentifier(termKey: course.termKey, courseId: course.id)
        CourseReminderScheduler.remove(identifiers: [identifier])
        var notificationsAllowed = true
        if let day {
            notificationsAllowed = await CourseReminderScheduler.requestPermission()
            if notificationsAllowed { await CourseReminderScheduler.scheduleSyllabusReminder(course: course, on: day) }
        }
        await loadCourses(force: true)
        return notificationsAllowed
    }

    /// Reads the file's text on this device, then uploads both.
    func uploadSyllabus(for course: EnrolledCourse, data: Data, mimeType: String, fileName: String) async throws -> UploadSyllabusResponse {
        uploading.insert(course.id)
        defer { uploading.remove(course.id) }
        let extracted = try await SyllabusTextExtractor.extract(data: data, mimeType: mimeType)
        let response = try await CourseCompanionAPI.uploadSyllabus(
            courseId: course.id, file: data, mimeType: mimeType, fileName: fileName, extracted: extracted
        )
        if course.syllabusRemindOn != nil {
            // The syllabus arrived; the "not available yet" reminder is no longer needed.
            try? await CourseCompanionAPI.setSyllabusReminder(courseId: course.id, remindOn: nil)
            CourseReminderScheduler.remove(identifiers:
                [CourseReminderScheduler.syllabusIdentifier(termKey: course.termKey, courseId: course.id)])
        }
        await loadCourses(force: true)
        return response
    }

    // MARK: - Review and dashboard (stage 3)

    @Published private(set) var dashboards: [String: CourseDashboard] = [:]
    private var fileCache: [String: Data] = [:]

    func loadDashboard(courseId: String) async throws {
        dashboards[courseId] = try await CourseCompanionAPI.dashboard(courseId: courseId)
    }

    /// The original upload, kept in memory for this session only.
    func documentFile(_ documentId: String) async throws -> Data {
        if let cached = fileCache[documentId] { return cached }
        let data = try await CourseCompanionAPI.documentFile(documentId: documentId)
        fileCache[documentId] = data
        return data
    }

    func addReminder(fact: SyllabusFact, lead: String) async throws -> Bool {
        let allowed = await CourseReminderScheduler.requestPermission()
        let reminder = try await CourseCompanionAPI.addReminder(factId: fact.id, lead: lead)
        if allowed { await CourseReminderScheduler.scheduleFactReminder(reminder) }
        return allowed
    }

    func deleteReminder(_ reminder: CourseReminder) async throws {
        try await CourseCompanionAPI.deleteReminder(reminder.id)
        CourseReminderScheduler.remove(identifiers: [CourseReminderScheduler.factIdentifier(reminder.id)])
    }

    func resolveReminder(_ reminder: CourseReminder, moveToNewDate: Bool) async throws {
        try await CourseCompanionAPI.resolveReminder(reminder.id, resolution: moveToNewDate ? "update" : "remove")
        await reconcileReminders()
    }

    func reconcileReminders() async {
        guard let active = try? await CourseCompanionAPI.activeReminders() else { return }
        await CourseReminderScheduler.reconcileFactReminders(active)
    }

    func deleteDocumentCache(_ documentId: String) { fileCache[documentId] = nil }

    func load(force: Bool = false) async {
        guard isAvailable else { return }
        if state == .loading { return }
        if !force, state == .loaded { return }
        state = .loading
        do {
            let result = try await CourseCompanionAPI.overview()
            overview = result
            if !result.supported {
                state = .unsupported
                return
            }
            if selectedTermKey == nil || !result.terms.contains(where: { $0.termKey == selectedTermKey }) {
                selectedTermKey = result.currentTermKey
            }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
