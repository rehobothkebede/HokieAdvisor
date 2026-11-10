import Foundation

/// Formats a student's program for display ("Computer Science · B.S."),
/// without changing the stored values. Records name programs inconsistently:
/// the degree field may be "B.S.", "BS", or "BS Computer Science", and the
/// major may carry the degree too. This shows each piece once and keeps text
/// that is genuinely different, such as a concentration.
nonisolated enum ProgramName {
    struct Parts: Equatable {
        var major: String
        /// Standard abbreviation, e.g. "B.S.", when the degree is recognized;
        /// otherwise the degree text as recorded.
        var degree: String?
        /// Extra program text that isn't the major, e.g. a concentration.
        var detail: String?
    }

    static func parts(major rawMajor: String, degree rawDegree: String) -> Parts {
        var major = clean(rawMajor)
        var degree: String?
        var leftovers: [String] = []

        let degreeText = clean(rawDegree)
        if let (abbreviation, rest) = splitDegree(degreeText) {
            degree = abbreviation
            if !rest.isEmpty { leftovers.append(rest) }
        } else if !degreeText.isEmpty {
            // Unrecognized degree wording: keep it, minus any repeated major.
            let rest = removingMajor(major, from: degreeText)
            if !rest.isEmpty { degree = rest }
        }

        // The major itself may include a degree ("BS Computer Science").
        if let (abbreviation, rest) = splitDegree(major) {
            degree = degree ?? abbreviation
            major = rest
        }

        var detail: [String] = []
        for leftover in leftovers {
            if major.isEmpty {
                major = leftover
                continue
            }
            let rest = removingMajor(major, from: leftover)
            if leftover.lowercased().hasPrefix(major.lowercased()),
               rest.lowercased().hasPrefix("and ") || rest.hasPrefix("& ") {
                major = leftover // a fuller program name, e.g. "… and Mathematics"
                continue
            }
            if !rest.isEmpty, !normalized(major).contains(normalized(rest)) { detail.append(rest) }
        }
        return Parts(major: major, degree: degree, detail: detail.isEmpty ? nil : detail.joined(separator: ", "))
    }

    /// "Computer Science · B.S. · Class of 2029", skipping missing pieces.
    /// Returns nil when there is nothing to show.
    static func line(major: String, degree: String, graduationYear: String? = nil) -> String? {
        let p = parts(major: major, degree: degree)
        var pieces = [p.major, p.degree ?? "", p.detail ?? ""]
        if let year = graduationYear.map(clean), !year.isEmpty { pieces.append("Class of \(year)") }
        let shown = pieces.filter { !$0.isEmpty }
        return shown.isEmpty ? nil : shown.joined(separator: " · ")
    }

    /// Major and degree only, e.g. a card title.
    static func title(major: String, degree: String) -> String {
        line(major: major, degree: degree) ?? ""
    }

    // MARK: - Degree recognition

    /// Patterns are matched as whole words at the start or end of the text,
    /// ignoring case, periods, and spacing ("BS", "B.S.", "b. s.").
    private static let degrees: [(pattern: String, abbreviation: String)] = [
        (#"bachelor\s+of\s+science\s+in\s+business\s+administration|b\.?\s?s\.?\s?b\.?\s?a\.?"#, "B.S.B.A."),
        (#"bachelor\s+of\s+fine\s+arts|b\.?\s?f\.?\s?a\.?"#, "B.F.A."),
        (#"bachelor\s+of\s+architecture|b\.?\s?arch\.?"#, "B.Arch."),
        (#"bachelor\s+of\s+music|b\.?\s?mus\.?"#, "B.M."),
        (#"bachelor\s+of\s+science|b\.?\s?sc?\.?"#, "B.S."),
        (#"bachelor\s+of\s+arts|b\.?\s?a\.?"#, "B.A."),
        (#"master\s+of\s+business\s+administration|m\.?\s?b\.?\s?a\.?"#, "M.B.A."),
        (#"master\s+of\s+engineering|m\.?\s?eng\.?"#, "M.Eng."),
        (#"master\s+of\s+fine\s+arts|m\.?\s?f\.?\s?a\.?"#, "M.F.A."),
        (#"master\s+of\s+science|m\.?\s?sc?\.?"#, "M.S."),
        (#"master\s+of\s+arts|m\.?\s?a\.?"#, "M.A."),
        (#"doctor\s+of\s+philosophy|ph\.?\s?d\.?"#, "Ph.D."),
        (#"associate\s+of\s+applied\s+science|a\.?\s?a\.?\s?s\.?"#, "A.A.S."),
        (#"associate\s+of\s+science|a\.?\s?s\.?"#, "A.S."),
        (#"associate\s+of\s+arts|a\.?\s?a\.?"#, "A.A."),
    ]

    private static let connector = #"[\s,:;–—\-/()]*(?:(?:in|of)\s+)?"#

    private static let matchers: [(start: NSRegularExpression, end: NSRegularExpression, abbreviation: String)] =
        degrees.compactMap { entry in
            // Short forms must stand alone, so "Mathematics" never reads as "MA".
            guard let start = try? NSRegularExpression(pattern: "^(?:\(entry.pattern))(?![A-Za-z])\(connector)", options: .caseInsensitive),
                  let end = try? NSRegularExpression(pattern: #"[\s,(–—\-]+(?:"# + entry.pattern + #")\)?$"#, options: .caseInsensitive)
            else { return nil }
            return (start, end, entry.abbreviation)
        }

    /// Finds a degree at the start or end of `text`; returns it and the rest.
    private static func splitDegree(_ text: String) -> (String, String)? {
        let range = NSRange(text.startIndex..., in: text)
        for m in matchers {
            for regex in [m.start, m.end] {
                guard let match = regex.firstMatch(in: text, range: range),
                      let r = Range(match.range, in: text) else { continue }
                var rest = text
                rest.removeSubrange(r)
                if regex === m.end, isShortForm(text[r]), rest.split(separator: " ").count > 3 {
                    continue // a trailing "AS" or "BA" in a long name is more likely a word
                }
                return (m.abbreviation, clean(rest))
            }
        }
        // The whole text may be just the degree, e.g. "BS".
        for m in matchers {
            if let match = m.start.firstMatch(in: text, range: range), match.range.length == range.length {
                return (m.abbreviation, "")
            }
        }
        return nil
    }

    private static func isShortForm(_ text: Substring) -> Bool {
        text.filter(\.isLetter).count <= 3
    }

    // MARK: - Text helpers

    private static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:·–—-/").union(.whitespaces))
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Removes a leading or trailing copy of the major from `text`.
    private static func removingMajor(_ major: String, from text: String) -> String {
        guard !major.isEmpty else { return text }
        if normalized(text) == normalized(major) { return "" }
        let lower = text.lowercased(), m = major.lowercased()
        if lower.hasPrefix(m) { return clean(String(text.dropFirst(major.count))) }
        if lower.hasSuffix(m) { return clean(String(text.dropLast(major.count))) }
        return text
    }
}
