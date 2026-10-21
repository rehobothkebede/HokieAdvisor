import SwiftMath
import SwiftUI
import UIKit

/// Typesets LaTeX with SwiftMath into images, cached per formula, size, and
/// color. Streaming re-renders a message on every token, so caching keeps
/// typesetting to once per distinct formula.
@MainActor
enum MathRenderer {
    struct Rendered {
        let image: UIImage
        let descent: CGFloat
    }

    private static var cache: [String: Rendered?] = [:]

    static func render(_ latex: String, fontSize: CGFloat, color: UIColor, display: Bool) -> Rendered? {
        let source = LaTeXFormatter.normalizeForRendering(latex)
        guard !source.isEmpty else { return nil }

        let key = "\(display ? "D" : "T")|\(fontSize)|\(color.cacheKey)|\(source)"
        if let cached = cache[key] { return cached }
        if cache.count > 400 { cache.removeAll() }

        var math = MathImage(
            latex: source,
            fontSize: fontSize,
            textColor: color,
            labelMode: display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, layout) = math.asImage()
        let rendered: Rendered? = if error == nil, let image, let layout {
            Rendered(image: image, descent: layout.descent)
        } else {
            nil
        }
        cache[key] = .some(rendered)
        return rendered
    }

    /// Point size for a SwiftUI text style at the current Dynamic Type setting.
    static func pointSize(for style: UIFont.TextStyle, scale: CGFloat = 1) -> CGFloat {
        (UIFont.preferredFont(forTextStyle: style).pointSize * scale).rounded()
    }
}

/// A display equation: typeset, horizontally scrollable when wide, on the same
/// glass inset the old renderer used. Falls back to the raw LaTeX when
/// SwiftMath cannot parse it, so a formula is never an empty box.
struct MathDisplayView: View {
    let latex: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Group {
                if let rendered = MathRenderer.render(
                    latex,
                    fontSize: MathRenderer.pointSize(for: .body, scale: 1.15),
                    color: UIColor.label.resolved(for: colorScheme),
                    display: true
                ) {
                    Image(uiImage: rendered.image)
                        .accessibilityLabel(Text(latex))
                } else {
                    Text(latex)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .glassInset(cornerRadius: 14)
    }
}

enum MathText {
    /// Builds one Text from a line that mixes Markdown and inline math, with
    /// each formula as a baseline-aligned image so it wraps with the words.
    @MainActor
    static func text(_ line: String, textStyle: UIFont.TextStyle, color: UIColor) -> Text {
        let segments = LaTeXFormatter.segments(line)
        guard segments.contains(where: { if case .math = $0 { true } else { false } }) else {
            return Text(line.markdown)
        }

        let fontSize = MathRenderer.pointSize(for: textStyle)
        var result = Text(verbatim: "")
        for segment in segments {
            switch segment {
            case .text(let value):
                // Markdown parsing trims edge whitespace; keep the spaces around formulas.
                let core = value.trimmingCharacters(in: .whitespaces)
                let leading = value.prefix { $0.isWhitespace }
                let trailing = core.isEmpty ? "" : String(value.reversed().prefix { $0.isWhitespace })
                result = Text("\(result)\(Text(verbatim: String(leading)))\(Text(core.markdown))\(Text(verbatim: trailing))")
            case .math(let latex, let display):
                if let rendered = MathRenderer.render(latex, fontSize: fontSize, color: color, display: display) {
                    let image = Text(Image(uiImage: rendered.image)).baselineOffset(-rendered.descent)
                    result = Text("\(result)\(image)")
                } else {
                    result = Text("\(result)\(Text(verbatim: "$\(latex)$").italic())")
                }
            }
        }
        return result
    }
}

extension UIFont.TextStyle {
    /// The UIKit text style matching the SwiftUI fonts MarkdownBody uses.
    init(_ font: Font) {
        switch font {
        case .largeTitle: self = .largeTitle
        case .title: self = .title1
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .body: self = .body
        case .callout: self = .callout
        case .footnote: self = .footnote
        case .caption: self = .caption1
        case .caption2: self = .caption2
        default: self = .subheadline
        }
    }
}

extension UIColor {
    func resolved(for colorScheme: ColorScheme) -> UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light))
    }

    fileprivate var cacheKey: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%.3f,%.3f,%.3f,%.3f", red, green, blue, alpha)
    }
}
