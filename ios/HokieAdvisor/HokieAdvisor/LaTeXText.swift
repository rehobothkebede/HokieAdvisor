import Foundation

/// Text-level LaTeX handling for advisor answers: finding math in Markdown,
/// splitting inline math out of a line, and normalizing what models write into
/// LaTeX that SwiftMath can typeset. Rendering lives in MathView.swift.
nonisolated enum LaTeXFormatter {
    enum Segment: Equatable {
        case text(String)
        case math(String, display: Bool)
    }

    // MARK: - Inline segmentation

    /// Splits one line of text into plain text and math spans.
    ///
    /// - `$...$` and `\(...\)` are inline math; `$$...$$` and `\[...\]` inside a
    ///   line are display-style math.
    /// - A `$` only opens math when followed by a non-space, and only closes it
    ///   when preceded by a non-space and not followed by a digit, so prices
    ///   like "$5 and $10" stay text.
    /// - `\$` is a literal dollar sign.
    static func segments(_ line: String) -> [Segment] {
        var result: [Segment] = []
        var text = ""
        let chars = Array(line)
        var i = 0

        func flushText() {
            if !text.isEmpty { result.append(.text(text)); text = "" }
        }
        func find(_ token: String, from start: Int) -> Int? {
            let needle = Array(token)
            guard start <= chars.count - needle.count else { return nil }
            for j in start...(chars.count - needle.count) where Array(chars[j..<(j + needle.count)]) == needle {
                return j
            }
            return nil
        }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            if c == "\\", next == "$" {
                text.append("$"); i += 2; continue
            }
            if c == "\\", next == "(" || next == "[", let close = find(next == "(" ? "\\)" : "\\]", from: i + 2) {
                let latex = String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces)
                if !latex.isEmpty {
                    flushText()
                    result.append(.math(latex, display: next == "["))
                    i = close + 2
                    continue
                }
            }
            if c == "$", next == "$", let close = find("$$", from: i + 2), close > i + 2 {
                flushText()
                result.append(.math(String(chars[(i + 2)..<close]).trimmingCharacters(in: .whitespaces), display: true))
                i = close + 2
                continue
            }
            if c == "$", let opener = next, !opener.isWhitespace, opener != "$", let close = closingDollar(chars, from: i + 1) {
                flushText()
                result.append(.math(String(chars[(i + 1)..<close]), display: false))
                i = close + 1
                continue
            }
            text.append(c)
            i += 1
        }
        flushText()
        return result
    }

    private static func closingDollar(_ chars: [Character], from start: Int) -> Int? {
        var j = start + 1
        while j < chars.count {
            if chars[j] == "$", chars[j - 1] != "\\" {
                let before = chars[j - 1]
                let after: Character? = j + 1 < chars.count ? chars[j + 1] : nil
                if !before.isWhitespace, !(after?.isNumber ?? false) { return j }
                return nil
            }
            j += 1
        }
        return nil
    }

    // MARK: - Normalization for SwiftMath

    /// Cleans model-written LaTeX for the typesetter: unescapes doubled
    /// backslashes, repairs malformed environments, strips display wrappers,
    /// and rewrites constructs SwiftMath does not support into ones it does.
    static func normalizeForRendering(_ latex: String) -> String {
        var value = repairMalformedMathSyntax(normalizeEscapes(latex))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("$", "$")] {
            if value.hasPrefix(open), value.hasSuffix(close), value.count > open.count + close.count {
                value = String(value.dropFirst(open.count).dropLast(close.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // "[ \begin{bmatrix} ... \end{bmatrix} ]" from models that lost the backslash.
        if value.hasPrefix("["), value.hasSuffix("]"), value.contains("\\begin{") {
            value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let rewrites: [(pattern: String, template: String)] = [
            (#"\\begin\{array\}(\{[^}]*\})?"#, "\\\\begin{matrix}"),
            (#"\\end\{array\}"#, "\\\\end{matrix}"),
            (#"\\begin\{(align|align\*|alignat|alignat\*|eqnarray\*?)\}(\{[^}]*\})?"#, "\\\\begin{aligned}"),
            (#"\\end\{(align|align\*|alignat|alignat\*|eqnarray\*?)\}"#, "\\\\end{aligned}"),
            (#"\\begin\{(gather\*)\}"#, "\\\\begin{gather}"),
            (#"\\end\{(gather\*)\}"#, "\\\\end{gather}"),
            (#"\\(begin|end)\{(equation\*?|displaymath)\}"#, ""),
            (#"\\(dfrac|tfrac)"#, "\\\\frac"),
            (#"\\operatorname\*?\{"#, "\\\\mathrm{"),
            (#"\\boxed\{"#, "{"),
            (#"\\tag\*?\{[^}]*\}"#, ""),
            (#"\\(nonumber|notag|displaystyle|textstyle)\b"#, ""),
            (#"\\(big|Big|bigg|Bigg)(l|r)?(?=[(\[|.)\]\\])"#, ""),
            (#"\\implies\b"#, #"\\Rightarrow"#),
            (#"\\impliedby\b"#, #"\\Leftarrow"#),
            (#"\\dots(c|b|m|o|i)?\b"#, #"\\ldots"#),
            (#"\\pmod\{([^}]*)\}"#, #"\\;(\\mathrm{mod}\\;$1)"#),
            (#"\\(bmod|mod)\b"#, #"\\;\\mathrm{mod}\\;"#),
            (#"\\[lr]vert\b"#, "|"),
            (#"\\[lr]Vert\b"#, #"\\|"#),
        ]
        for rewrite in rewrites {
            value = value.replacingOccurrences(of: rewrite.pattern, with: rewrite.template, options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Block detection (used by MarkdownBody)

    /// True when a line has a \begin{...} outside any inline $...$ span, i.e. the
    /// line itself is an environment rather than prose containing inline math.
    static func hasBareEnvironment(_ line: String) -> Bool {
        segments(line).contains { segment in
            if case .text(let value) = segment { return value.contains("\\begin") }
            return false
        }
    }

    static func looksLikeDisplayMath(_ latex: String) -> Bool {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        return normalized.contains("\\begin{") &&
            (normalized.contains("matrix}") || normalized.contains("array}") || normalized.contains("cases}"))
    }

    static func startedMathEnvironment(_ latex: String) -> String? {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        guard let range = normalized.range(
            of: #"\\begin\{(bmatrix|pmatrix|vmatrix|matrix|array|cases|case|aligned|align\*?|gather\*?)\}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let command = String(normalized[range])
        return command
            .replacingOccurrences(of: "\\begin{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    static func endsMathEnvironment(_ latex: String, environment: String) -> Bool {
        let normalized = repairMalformedMathSyntax(normalizeEscapes(latex))
        return normalized.contains("\\end{\(environment)}")
    }

    // MARK: - Repair

    private static func normalizeEscapes(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\\\\[", with: "\\[")
            .replacingOccurrences(of: "\\\\]", with: "\\]")
            .replacingOccurrences(of: "\\\\begin", with: "\\begin")
            .replacingOccurrences(of: "\\\\end", with: "\\end")
    }

    private static func repairMalformedMathSyntax(_ latex: String) -> String {
        var value = latex

        for environment in ["array", "bmatrix", "pmatrix", "vmatrix", "matrix", "cases", "case"] {
            value = value.replacingOccurrences(of: "\\end\(environment)", with: "\\end{\(environment)}")
        }

        let braceEnvironments = ["bmatrix", "pmatrix", "vmatrix", "matrix", "cases", "case"]
        for environment in braceEnvironments {
            let malformed = "\\begin\(environment)"
            while let range = value.range(of: malformed) {
                value.replaceSubrange(range, with: "\\begin{\(environment)}")
            }
        }

        while let range = value.range(of: "\\beginarray") {
            var cursor = range.upperBound
            var columnSpec = ""
            let allowedSpecCharacters = Set("clr|")

            while cursor < value.endIndex, allowedSpecCharacters.contains(value[cursor]) {
                columnSpec.append(value[cursor])
                cursor = value.index(after: cursor)
            }

            let replacement = columnSpec.isEmpty ? "\\begin{array}" : "\\begin{array}{\(columnSpec)}"
            value.replaceSubrange(range.lowerBound..<cursor, with: replacement)
        }

        // Models sometimes write \begin{case}; SwiftMath only knows cases.
        value = value
            .replacingOccurrences(of: "\\begin{case}", with: "\\begin{cases}")
            .replacingOccurrences(of: "\\end{case}", with: "\\end{cases}")

        return value
    }
}
