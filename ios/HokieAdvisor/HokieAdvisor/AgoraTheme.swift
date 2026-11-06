import SwiftUI
import UIKit

// MARK: - Agora Brand
//
// Platform identity. These values never change with the student's school.
// Color hexes are provisional until the final logo files supply exact values;
// see docs/AGORA_REBRAND_PLAN.md.

enum AgoraBrand {
    static let name = "Agora"
    static let tagline = "Your next chapter"
    static let supportingLine = "Understand your degree. Plan what's next."
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A color that resolves per appearance, so call sites stay scheme-agnostic.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static let agoraNavy      = Color(hex: 0x1B2A41)
    static let agoraNavyDeep  = Color(hex: 0x101A2B)
    static let agoraIvory     = Color(hex: 0xF7F2E8)
    static let agoraCopper    = Color(hex: 0xB06A3B)
    static let agoraCopperLit = Color(hex: 0xD08C5C)
}

// MARK: - Semantic Palette

enum AgoraPalette {
    static let background   = Color(light: 0xF7F2E8, dark: 0x0E1522)
    static let surface      = Color(light: 0xFFFDF8, dark: 0x172133)
    static let surfaceInset = Color(light: 0xEFE8DA, dark: 0x1E2A3F)
    static let stroke       = Color(light: 0xDDD3C2, dark: 0x2C3A52)
    /// Platform-identity ink: wordmark, header mark. Navy on ivory, ivory on navy.
    static let brandInk     = Color(light: 0x1B2A41, dark: 0xF7F2E8)
    static let copper       = Color(light: 0xB06A3B, dark: 0xD08C5C)
}

// MARK: - Metrics

enum AgoraSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AgoraRadius {
    static let control: CGFloat = 14
    static let inset: CGFloat = 16
    static let card: CGFloat = 22
    static let sheet: CGFloat = 28
}

// MARK: - Typography
//
// Serif is reserved for the wordmark and large brand headings. Everyday text,
// numbers, code, and math stay on the system font.

extension Font {
    static func agoraDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let agoraEyebrow = Font.system(size: 11, weight: .semibold)
}

/// TEMPORARY text wordmark. Replace with the supplied vector wordmark once it is
/// added to an asset catalog; this is not the final logo lettering.
struct AgoraWordmark: View {
    var size: CGFloat = 34

    var body: some View {
        Text(AgoraBrand.name)
            .font(.agoraDisplay(size, weight: .medium))
            .tracking(size * 0.04)
            .foregroundStyle(AgoraPalette.brandInk)
            .accessibilityLabel(AgoraBrand.name)
    }
}

// MARK: - School Theme
//
// School accents layered on the Agora base: selected tabs, primary buttons,
// progress indicators. The student's institution is not stored here:
// - Signed in: every account belongs to Virginia Tech today (migration 005
//   backfills existing profiles to VT and defaults new ones to it), so the
//   account resolves to its email's school, falling back to VT.
// - Signed out: the school picked on the welcome screen, held only in view
//   state until the student signs in.
// When `profiles.institution_id` ships, resolve signed-in accounts by its slug.

struct SchoolTheme: Equatable {
    /// Matches `institutions.slug` in migration 005. `nil` is the neutral Agora theme.
    let slug: String?
    let name: String
    let emailDomains: [String]
    let accent: Color
    let accentDeep: Color
    let onAccent: Color
    let secondaryAccent: Color
    /// `institutions.student_id_label` in migration 005, e.g. "PID".
    let studentIDLabel: String?
    /// `branding.community_name` in migration 005, e.g. "Hokie".
    let communityName: String?

    var isSchool: Bool { slug != nil }

    static let agora = SchoolTheme(
        slug: nil,
        name: AgoraBrand.name,
        emailDomains: [],
        accent: Color(light: 0x1B2A41, dark: 0xD08C5C),
        accentDeep: Color(light: 0x101A2B, dark: 0xB06A3B),
        onAccent: Color(light: 0xF7F2E8, dark: 0x101A2B),
        secondaryAccent: AgoraPalette.copper,
        studentIDLabel: nil,
        communityName: nil
    )

    // Values match the VT `branding` seed in migration 005; dark mode lifts the
    // maroon so selected states stay visible on navy.
    static let virginiaTech = SchoolTheme(
        slug: "vt",
        name: "Virginia Tech",
        emailDomains: ["vt.edu"],
        accent: Color(light: 0x861F41, dark: 0xA3325A),
        accentDeep: Color(light: 0x501027, dark: 0x861F41),
        onAccent: .white,
        secondaryAccent: Color(hex: 0xE5751F),
        studentIDLabel: "PID",
        communityName: "Hokie"
    )

    /// Schools Agora actually supports. Only add a school here once its
    /// catalog, audit, and advising support exist.
    static let supported: [SchoolTheme] = [.virginiaTech]

    /// The school for an existing account. See the note above for the VT fallback.
    static func forAccount(email: String) -> SchoolTheme {
        forEmailDomain(email) ?? .virginiaTech
    }

    static func forEmailDomain(_ email: String) -> SchoolTheme? {
        guard email.contains("@"), let domain = email.split(separator: "@").last?.lowercased() else {
            return nil
        }
        return supported.first { school in
            school.emailDomains.contains { domain == $0 || domain.hasSuffix(".\($0)") }
        }
    }
}

private struct SchoolThemeKey: EnvironmentKey {
    static let defaultValue = SchoolTheme.agora
}

extension EnvironmentValues {
    var schoolTheme: SchoolTheme {
        get { self[SchoolThemeKey.self] }
        set { self[SchoolThemeKey.self] = newValue }
    }
}

// MARK: - Buttons

struct AgoraPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AgoraPrimaryButtonBody(configuration: configuration)
    }
}

private struct AgoraPrimaryButtonBody: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? theme.onAccent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous)
                    .fill(isEnabled ? theme.accent : Color.primary.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.86 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct AgoraSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AgoraPalette.brandInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous)
                    .fill(AgoraPalette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous)
                    .stroke(AgoraPalette.stroke, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AgoraPrimaryButtonStyle {
    static var agoraPrimary: AgoraPrimaryButtonStyle { AgoraPrimaryButtonStyle() }
}

extension ButtonStyle where Self == AgoraSecondaryButtonStyle {
    static var agoraSecondary: AgoraSecondaryButtonStyle { AgoraSecondaryButtonStyle() }
}

// MARK: - Input Fields

extension View {
    func agoraField() -> some View {
        self
            .padding(.horizontal, AgoraSpacing.lg)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous)
                    .fill(AgoraPalette.surfaceInset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous)
                    .stroke(AgoraPalette.stroke, lineWidth: 1)
            )
    }
}
