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
