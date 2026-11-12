import Foundation
import PDFKit

@main struct Smoke {
    @MainActor static func main() async throws {
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            print("\(condition ? "PASS" : "FAIL") \(name)")
            if !condition { failures += 1 }
        }

        // Uses the production Swift HTTP client and response models against
        // the real course handler with an isolated in-memory database.
        let overview = try await CourseCompanionAPI.overview()
        check(overview.supported && overview.terms.count == 2, "overview decodes published terms")
        let guide = try await CourseCompanionAPI.registrationGuide(termKey: "spring-2027")
        check(!guide.canRegisterInApp && !guide.sources.isEmpty, "registration includes official evidence")
        let course = try await CourseCompanionAPI.addCourse(.init(
            termKey: "spring-2027", subject: "CS", number: "2114", title: "QA sample",
            sectionCode: "99999", instructorName: "Dr. Test Instructor", origin: "manual"))
        check(course.status == .needed, "add course encodes section and term")
        try await CourseCompanionAPI.setSyllabusReminder(courseId: course.id, remindOn: "2027-01-20")
        var courses = try await CourseCompanionAPI.listCourses(termKey: "spring-2027")
        check(courses.courses.first?.syllabusRemindOn == "2027-01-20", "syllabus reminder persists")
        try await CourseCompanionAPI.setSyllabusReminder(courseId: course.id, remindOn: nil)
        courses = try await CourseCompanionAPI.listCourses(termKey: "spring-2027")
        check(courses.courses.first?.syllabusRemindOn == nil, "explicit null clears reminder")
        let fixture = "backend/supabase/tests/fixtures/qa_syllabus_v1.pdf"
        let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
        let pdf = PDFDocument(data: data)!
        let pages = (0..<pdf.pageCount).map { SyllabusTextExtractor.Page(page: $0 + 1, text: pdf.page(at: $0)!.string!) }
        let uploaded = try await CourseCompanionAPI.uploadSyllabus(forTest: course.id, data: data, pages: pages)
        check(uploaded.document.processingState == "review_needed", "multipart PDF upload reaches review")
        let original = try await CourseCompanionAPI.documentFile(documentId: uploaded.document.id)
        check(original == data, "original PDF round trips without corruption")
        let detail = try await CourseCompanionAPI.document(uploaded.document.id)
        check(!detail.facts.isEmpty, "syllabus facts and evidence decode")
        _ = try await CourseCompanionAPI.confirmUnflagged(documentId: uploaded.document.id)
        let pending = try await CourseCompanionAPI.document(uploaded.document.id)
        for fact in pending.facts where fact.reviewState == "pending" {
            try await CourseCompanionAPI.reviewFact(fact.id, decision: fact.evidence == "not_found" ? "reject" : "confirm")
        }
        _ = try await CourseCompanionAPI.completeReview(documentId: uploaded.document.id)
        let dashboard = try await CourseCompanionAPI.dashboard(courseId: course.id)
        check(dashboard.course.status == .ready, "review activates course dashboard")
        check(dashboard.next?.shown.date == "2027-03-04", "confirmed exam date reaches iOS")
        check(dashboard.undated.contains { $0.label == "Quiz 3" }, "relative dates stay undated")
        let reminder = try await CourseCompanionAPI.addReminder(factId: dashboard.next!.id, lead: "day_before")
        check(ISO8601Timestamp.date(reminder.firesAt) != nil, "reminder timestamp decodes")
        try await CourseCompanionAPI.deleteReminder(reminder.id)
        let remaining = try await CourseCompanionAPI.activeReminders()
        check(remaining.isEmpty, "deleted reminder disappears")
        _ = try await CourseCompanionAPI.deleteCourse(courseId: course.id)
        courses = try await CourseCompanionAPI.listCourses(termKey: "spring-2027")
        check(courses.courses.isEmpty, "course deletion refreshes list")

        // Actual production streaming transport and view model, synthetic SSE.
        for mode in ["normal", "length", "abrupt", "server-interrupted", "empty", "rate-limit"] {
            let vm = ChatViewModel()
            let history = ChatHistoryStore()
            vm.configure(store: history)
            let sent = await vm.sendMessage(textOverride: mode)
            switch mode {
            case "normal":
                check(sent && vm.messages.last?.content == "A partial answer", "normal stream completes")
                check(history.memoryContext == ["Prefers short examples."], "memory event reaches store")
            case "length": check(sent && vm.canContinueTruncatedAnswer, "token limit exposes Continue")
            case "abrupt": check(sent && vm.messages.last?.content.contains("(interrupted)") == true, "silent stream disconnect retains interrupted answer")
            case "server-interrupted": check(sent && vm.messages.last?.content.contains("(interrupted)") == true, "provider interruption retains partial answer")
            case "empty": check(!sent && vm.inputText == mode && vm.messages.isEmpty, "empty stream restores draft")
            default: check(!sent && vm.inputText == mode && vm.errorMessage == "Daily test limit reached.", "429 restores draft with friendly message")
            }
            check(vm.isReadyForMessage, "\(mode) releases composer")
        }

        let graph = SimpleGraph.parse("CS-2114 -> CS-3114 : 4\nCS-3114 -> Algorithms\nstep: CS-2114 | Start\nstep: CS-2114 -> CS-3114 | Next")
        check(graph?.nodes.contains("CS-2114") == true, "graph preserves hyphenated node names")
        check(graph?.edges.first?.directed == true && graph?.edges.first?.weight == "4", "graph retains direction and weight")
        check(graph?.steps.count == 2, "graph includes traversal steps")
        check(graph?.isTree == true, "tree uses layered layout")
        check(SimpleGraph.parse("Here is a paragraph explaining the answer.") == nil, "invalid graph falls back to raw text")
        let positions = graph!.positions(in: CGSize(width: 320, height: 260), inset: 35)
        check(positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.x <= 320 && $0.y >= 0 && $0.y <= 260 }, "graph coordinates fit card")
        check(LaTeXFormatter.segments("Let $x$ be positive.") == [.text("Let "), .math("x", display: false), .text(" be positive.")], "inline math preserves surrounding words and spaces")
        check(LaTeXFormatter.segments("$$x^2$$") == [.math("x^2", display: true)], "display math parses")
        check(LaTeXFormatter.segments("Costs $5 and $10") == [.text("Costs $5 and $10")], "prices are not treated as equations")
        print("RESULT: \(checks - failures)/\(checks) checks passed")
        if failures > 0 { exit(1) }
    }
}

extension CourseCompanionAPI {
    static func uploadSyllabus(forTest courseId: String, data: Data, pages: [SyllabusTextExtractor.Page]) async throws -> UploadSyllabusResponse {
        try await uploadSyllabus(courseId: courseId, file: data, mimeType: "application/pdf", fileName: "qa.pdf", extracted: .init(pages: pages, method: .pdfText))
    }
}
