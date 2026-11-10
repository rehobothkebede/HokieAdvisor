import Foundation

// MARK: - Terms and registration (stage 1)
//
// Mirrors the `courses` edge function. Dates are calendar days ("yyyy-MM-dd")
// from official sources; see `CalendarDay` for display.

nonisolated struct CourseInstitution: Decodable, Equatable {
    let id: String
    let slug: String
    let name: String
}

nonisolated struct AcademicTerm: Decodable, Identifiable, Hashable {
    var id: String { termKey }
    let termKey: String
    let name: String
    let classesBegin: String
    let classesEnd: String
    let finalsEnd: String?
    let timezone: String
}

nonisolated struct TermDeadline: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let audience: String
    /// Verbatim from the official source.
    let label: String
    let startsOn: String
    let endsOn: String?
    let timeNote: String?
    let detail: String?
    let isTentative: Bool
    let sourceId: String
    /// past, open, today, or upcoming, computed in the term's time zone.
    let state: String

    var isPast: Bool { state == "past" }

    /// Plain-language audience, or nil when it applies to everyone.
    var audienceLabel: String? {
        switch audience {
        case "continuing": return "Continuing students"
        case "incoming": return "Incoming students"
        case "graduate": return "Graduate students"
        default: return nil
        }
    }

    var dateText: String {
        if let endsOn, endsOn != startsOn {
            return CalendarDay.rangeText(startsOn, endsOn)
        }
        return CalendarDay.text(startsOn, weekday: true)
    }
}

nonisolated struct CoursesOverview: Decodable {
    let supported: Bool
    let institution: CourseInstitution?
    let terms: [AcademicTerm]
    let currentTermKey: String?
    let registration: RegistrationHighlight?
}

nonisolated struct RegistrationHighlight: Decodable {
    let termKey: String
    let termName: String
    let deadline: TermDeadline
}

nonisolated struct OfficialSource: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let publisher: String
    let url: String
    let checkedOn: String

    var link: URL? { URL(string: url) }
}

nonisolated struct GuidePoint: Decodable, Equatable {
    let text: String
    let sourceId: String
}

nonisolated struct GuideComparisonRow: Decodable, Equatable {
    let aspect: String
    let drop: String
    let withdraw: String
    let sourceId: String
}

nonisolated struct GuideLink: Decodable, Equatable {
    let title: String
    let url: String
}

nonisolated struct GuideTopic: Decodable, Identifiable, Equatable {
    var id: String { topic }
    let topic: String
    let sortOrder: Int
    let title: String
    let points: [GuidePoint]
    let comparison: [GuideComparisonRow]?
    let links: [GuideLink]
}

nonisolated struct RegistrationGuide: Decodable {
    let institution: CourseInstitution
    let term: AcademicTerm
    let terms: [AcademicTerm]
    let deadlines: [TermDeadline]
    let topics: [GuideTopic]
    let sources: [OfficialSource]
    let canRegisterInApp: Bool

    func source(_ id: String) -> OfficialSource? { sources.first { $0.id == id } }
}

// MARK: - Calendar days

/// Formats "yyyy-MM-dd" calendar days without shifting them through a time zone.
nonisolated enum CalendarDay {
    private static let utc = TimeZone(identifier: "UTC")!

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = utc
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func date(_ day: String) -> Date? { parser.date(from: day) }

    /// The calendar day (yyyy-MM-dd) of `date` as the student sees it.
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func text(_ day: String, weekday: Bool = false, year: Bool = true) -> String {
        guard let date = date(day) else { return day }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, timeZone: utc)
            .month(.abbreviated)
            .day()
        if weekday { style = style.weekday(.abbreviated) }
        if year { style = style.year() }
        return date.formatted(style)
    }

    static func rangeText(_ start: String, _ end: String) -> String {
        let sameYear = start.prefix(4) == end.prefix(4)
        return "\(text(start, year: !sameYear)) – \(text(end))"
    }
}

// MARK: - Courses and syllabi (stage 2)

nonisolated enum SyllabusStatus: String, Decodable {
    case needed
    case processing
    case reviewNeeded = "review_needed"
    case ready
    case updateAvailable = "update_available"

    var label: String {
        switch self {
        case .needed: return "Syllabus needed"
        case .processing: return "Processing"
        case .reviewNeeded: return "Review needed"
        case .ready: return "Ready"
        case .updateAvailable: return "Updated version available"
        }
    }

    var symbol: String {
        switch self {
        case .needed: return "doc.badge.plus"
        case .processing: return "hourglass"
        case .reviewNeeded: return "checklist"
        case .ready: return "checkmark.circle"
        case .updateAvailable: return "arrow.triangle.2.circlepath"
        }
    }
}

nonisolated struct DocumentFinding: Decodable, Equatable, Identifiable {
    var id: String { "\(code)-\(page ?? 0)" }
    let code: String
    let message: String
    let page: Int?
}

nonisolated struct SyllabusDocumentSummary: Decodable, Identifiable, Equatable {
    let id: String
    let courseId: String
    let version: Int
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
    let pageCount: Int
    let textMethod: String
    /// processing, review_needed, reviewed, or failed.
    let processingState: String
    let errorCode: String?
    let findings: [DocumentFinding]
    let uploadedAt: String
    let extractedAt: String?
    let reviewedAt: String?

    var uploadedDate: Date? { ISO8601Timestamp.date(uploadedAt) }
}

nonisolated struct EnrolledCourse: Decodable, Identifiable, Equatable {
    let id: String
    let termKey: String
    let subject: String
    let number: String
    let title: String
    let sectionCode: String
    let instructorName: String
    let syllabusRemindOn: String?
    let status: SyllabusStatus
    let currentDocumentId: String?
    let pendingDocumentId: String?
    let lastUploadFailed: Bool
    let documents: [SyllabusDocumentSummary]

    var code: String { "\(subject) \(number)" }
}

nonisolated struct CourseListResponse: Decodable {
    let termKey: String
    let courses: [EnrolledCourse]
}

nonisolated struct AddCourseResponse: Decodable {
    let course: EnrolledCourse
}

nonisolated struct UploadSyllabusResponse: Decodable {
    let duplicate: Bool
    let document: SyllabusDocumentSummary
}

nonisolated struct DeleteResponse: Decodable {
    let deletedReminderIds: [String]?
}

nonisolated struct DocumentFileResponse: Decodable {
    let mimeType: String
    let fileName: String
    let dataBase64: String
}

/// Parses server timestamps with or without fractional seconds.
nonisolated enum ISO8601Timestamp {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain = ISO8601DateFormatter()

    static func date(_ value: String) -> Date? {
        // Postgres text timestamps use a space and short offsets; normalize them.
        var s = value.replacingOccurrences(of: " ", with: "T")
        if let range = s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) {
            s.replaceSubrange(range, with: s[range] + ":00")
        }
        return withFraction.date(from: s) ?? plain.date(from: s)
    }
}

// MARK: - Review and dashboard (stage 3)

/// A JSON scalar from the server (used for before/after values in changes).
nonisolated enum JSONScalar: Decodable, Equatable {
    case string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else { self = .null }
    }

    var text: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.formatted()
        case .bool(let b): return b ? "Yes" : "No"
        case .null: return nil
        }
    }
}

/// What a fact says. Only values stated in the syllabus (or, for
/// `effective`, the student's own correction) are present.
nonisolated struct FactValue: Decodable, Equatable {
    var summary: String?
    var dateText: String?
    var date: String?
    var dateBasis: String?
    var relativeTiming: String?
    var startTime: String?
    var endTime: String?
    var timeText: String?
    var timezoneText: String?
    var recurrenceText: String?
    var examFormat: String?
    var weightPercent: Double?
    var location: String?
    var appointment: String?
    var contact: String?
    var restrictions: [String]?

    var examFormatLabel: String? {
        switch examFormat {
        case "online": return "Online"
        case "in_person": return "In person"
        case "take_home": return "Take-home"
        case "proctored": return "Proctored"
        case "unspecified": return "Format not stated"
        default: return nil
        }
    }

    /// "Thu, Mar 4, 2027" for a confirmed calendar date.
    var dateLabel: String? { date.map { CalendarDay.text($0, weekday: true) } }

    /// Times exactly as the syllabus gives them, with a stated time zone.
    var timeLabel: String? {
        let base: String?
        if let startTime {
            base = [startTime, endTime].compactMap { $0.map(Self.clock) }.joined(separator: "–")
        } else {
            base = timeText
        }
        guard let base else { return nil }
        return timezoneText.map { "\(base) \($0)" } ?? base
    }

    static func clock(_ hhmm: String) -> String {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return hhmm }
        let hour = (parts[0] + 11) % 12 + 1
        return "\(hour):\(String(format: "%02d", parts[1])) \(parts[0] >= 12 ? "PM" : "AM")"
    }
}

nonisolated struct FactCorrection: Decodable, Equatable {
    let corrected: [String: JSONScalar]
    let note: String?
}

nonisolated struct SyllabusFact: Decodable, Identifiable, Equatable {
    let id: String
    let documentId: String
    let category: String
    let label: String
    let value: FactValue
    let excerpt: String
    let page: Int
    let qualifiers: [String]
    /// verified, other_page, approximate, or not_found.
    let evidence: String
    let issues: [String]
    let reviewState: String
    /// Dashboard only: value with the student's correction applied.
    let effective: FactValue?
    let correction: FactCorrection?

    var shown: FactValue { effective ?? value }
    var isDated: Bool { category == "exam" || category == "assignment_deadline" }
    var isBlocked: Bool { issues.contains("other_term") }
    var needsCorrectionToConfirm: Bool { evidence == "not_found" }
}

nonisolated struct CorrectionRecord: Decodable, Equatable {
    let factId: String
    let corrected: [String: JSONScalar]
    let note: String?
}

nonisolated struct FieldChange: Decodable, Equatable {
    let field: String
    let before: JSONScalar
    let after: JSONScalar
}

nonisolated struct FactChange: Decodable, Equatable, Identifiable {
    var id: String { factId ?? "\(category)-\(label)" }
    let factId: String?
    let category: String
    let label: String
    let fields: [FieldChange]?
    let affectedReminderIds: [String]?
}

nonisolated struct DocumentChanges: Decodable, Equatable {
    let comparedWithVersion: Int
    let changed: [FactChange]
    let added: [FactChange]
    let removed: [FactChange]
}

nonisolated struct DocumentDetail: Decodable {
    let document: SyllabusDocumentSummary
    let course: EnrolledCourse
    let facts: [SyllabusFact]
    let corrections: [CorrectionRecord]
    let changes: DocumentChanges?

    func correction(for fact: SyllabusFact) -> CorrectionRecord? { corrections.first { $0.factId == fact.id } }
}

nonisolated struct CourseReminder: Decodable, Identifiable, Equatable {
    let id: String
    let courseId: String
    let factId: String
    let lead: String
    let firesAt: String
    let title: String
    let body: String
    /// active or needs_reconfirm.
    let state: String

    var leadLabel: String {
        switch lead {
        case "week_before": return "A week before"
        case "day_before": return "The day before"
        default: return "The morning of"
        }
    }
}

nonisolated struct CourseDashboard: Decodable {
    let course: EnrolledCourse
    let termTimezone: String
    let currentDocument: SyllabusDocumentSummary?
    let pendingDocument: SyllabusDocumentSummary?
    let facts: [SyllabusFact]
    let next: SyllabusFact?
    let undated: [SyllabusFact]
    let reminders: [CourseReminder]

    func facts(_ categories: Set<String>) -> [SyllabusFact] { facts.filter { categories.contains($0.category) } }
}

nonisolated struct ReminderListResponse: Decodable {
    let reminders: [CourseReminder]
}

/// Plain-language explanations for review flags.
nonisolated enum FactIssue {
    static func text(_ issue: String, fact: SyllabusFact) -> String? {
        switch issue {
        case "excerpt_not_found": return "Agora couldn’t find this in the document. It may be a reading error."
        case "page_corrected": return "Found on page \(fact.page), not the page Agora first expected."
        case "approximate_match": return "Matched approximately: the file’s text order differs. Compare with the page."
        case "value_not_in_excerpt": return "This value isn’t in the quoted text. Check it against the page."
        case "year_from_term": return "The syllabus doesn’t give a year. Agora used the term’s year."
        case "invalid_date": return "This isn’t a real calendar date."
        case "date_outside_term": return "This date falls outside the term."
        case "weekday_mismatch": return "The weekday and the date don’t match."
        case "relative_date": return "No calendar date. The syllabus says “\(fact.value.relativeTiming ?? "")”."
        case "ambiguous_date": return "The date isn’t clear."
        case "other_term": return "From another term’s syllabus, so it can’t be used."
        case "timezone_unstated": return "No time zone given for an online or take-home exam."
        case "conflicting": return "The syllabus says different things about this."
        default: return nil
        }
    }
}

nonisolated enum FactCategory {
    static func title(_ category: String) -> String {
        switch category {
        case "exam": return "Exams"
        case "assignment_deadline": return "Deadlines"
        case "office_hours": return "Office hours"
        case "contact": return "Contact"
        case "attendance": return "Attendance"
        case "participation": return "Participation"
        case "grading_weight": return "Grading"
        case "late_work": return "Late work"
        case "makeup": return "Makeup work"
        case "materials": return "Required materials"
        case "requirement": return "Other requirements"
        case "restriction": return "Rules"
        default: return category.capitalized
        }
    }

    static let order = ["exam", "assignment_deadline", "grading_weight", "office_hours", "contact", "attendance",
                        "participation", "late_work", "makeup", "materials", "requirement", "restriction"]
}
