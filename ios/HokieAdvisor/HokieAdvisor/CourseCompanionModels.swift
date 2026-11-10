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
