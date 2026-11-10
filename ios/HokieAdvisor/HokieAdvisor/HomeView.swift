import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: Int
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("graduationYear") private var graduationYear = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var showTranscriptImport = false

    private var compactTitleProgress: CGFloat {
        min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
                    homeHeader
                        .padding(.top, AgoraSpacing.sm)
                        .padding(.bottom, AgoraSpacing.xs)
                    nextStepCard
                    advisorCard
                    if let audit = appState.latestDegreeAudit, appState.hasTranscript {
                        degreeProgressCard(audit)
                    }
                    if appState.hasTranscript {
                        statsSection
                    }
                    if appState.needsTutoringSupport {
                        supportCard
                    }
                    if theme.slug == SchoolTheme.virginiaTech.slug {
                        tipsSection
                    }
                    Spacer(minLength: HokieChrome.contentBottomInset)
                }
                .padding(.horizontal, AgoraSpacing.xl - 4)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                guard abs(offset - scrollOffset) > 0.5 else { return }
                scrollOffset = offset
            }
            .hokieScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
            .overlay(alignment: .top) { compactTitleOverlay }
        }
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
        }
    }

    private var compactTitleOverlay: some View {
        HokieCompactTitleBar(title: "Home", progress: compactTitleProgress)
    }

    // MARK: - Header

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) {
                    AgoraWordmark(size: 24)
                    Spacer(minLength: 12)
                    schoolBadge
                }
                VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                    AgoraWordmark(size: 24)
                    schoolBadge
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.title.weight(.bold))
                    .tracking(-0.4)
                    .foregroundStyle(AgoraPalette.brandInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(programLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// School identity: a small, quiet badge. Only shown for a real school.
    @ViewBuilder
    private var schoolBadge: some View {
        if theme.isSchool {
            HStack(spacing: 6) {
                Circle().fill(theme.accent).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(theme.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AgoraPalette.brandInk)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(AgoraPalette.surface, in: Capsule())
            .overlay(Capsule().stroke(AgoraPalette.stroke.opacity(0.6), lineWidth: 0.75))
        }
    }

    private var firstName: String {
        studentName.components(separatedBy: " ").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation = hour < 12 ? "Good morning" : (hour < 17 ? "Good afternoon" : "Good evening")
        return firstName.isEmpty ? salutation : "\(salutation), \(firstName)"
    }

    /// Program from the latest audit when one exists, else the profile major.
    private var programLine: String {
        var parts: [String] = []
        if let audit = appState.latestDegreeAudit {
            parts.append("\(audit.major) \(audit.degree)")
        } else if !appState.major.isEmpty {
            parts.append(appState.major)
        }
        if !graduationYear.isEmpty {
            parts.append("Class of \(graduationYear)")
        }
        return parts.isEmpty ? AgoraBrand.supportingLine : parts.joined(separator: " · ")
    }

    // MARK: - Next Step

    private struct NextStep {
        let eyebrow: String
        let title: String
        let detail: String
        let action: String
        /// `nil` opens transcript import.
        let tab: Int?
    }

    private var nextStep: NextStep {
        guard appState.hasTranscript else {
            return NextStep(
                eyebrow: "Start here",
                title: "Import your transcript",
                detail: "Bring your credits, courses, and degree progress together in one place.",
                action: "Import transcript",
                tab: nil
            )
        }
        guard let audit = appState.latestDegreeAudit else {
            return NextStep(
                eyebrow: "Next step",
                title: "Check your degree progress",
                detail: "See which requirement groups your transcript covers and what's left.",
                action: "Open Degree Progress",
                tab: 1
            )
        }
        let attention = audit.buckets.filter { $0.status == "attention" }.count
        let remaining = max(audit.totalBucketCount - audit.completeBucketCount, 0)
        if attention > 0 {
            return NextStep(
                eyebrow: "Needs attention",
                title: "\(attention) requirement group\(attention == 1 ? "" : "s") need\(attention == 1 ? "s" : "") a look",
                detail: "Your transcript audit flagged \(attention == 1 ? "an item" : "items") to review.",
                action: "Review in Degree Progress",
                tab: 1
            )
        }
        if remaining > 0 {
            return NextStep(
                eyebrow: "Next step",
                title: "\(remaining) requirement group\(remaining == 1 ? "" : "s") remaining",
                detail: "See the courses still missing from each group.",
                action: "Review remaining requirements",
                tab: 1
            )
        }
        return NextStep(
            eyebrow: "Next step",
            title: "Every tracked group is marked complete",
            detail: "Confirm with your official audit and your academic advisor before you apply to graduate.",
            action: "Open Degree Progress",
            tab: 1
        )
    }

    private var nextStepCard: some View {
        let step = nextStep
        return VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
            VStack(alignment: .leading, spacing: 6) {
                Text(step.eyebrow)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text(step.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                if let tab = step.tab { switchToTab(tab) }
                else { showTranscriptImport = true }
            } label: {
                HStack(spacing: AgoraSpacing.sm) {
                    Text(step.action)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.right")
                        .accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.agoraNavy)
                .padding(.horizontal, AgoraSpacing.lg)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(AgoraSpacing.xl - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AgoraRadius.card, style: .continuous)
                .fill(Self.nextStepFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AgoraRadius.card, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
    }

    /// Agora navy, lifted slightly in dark mode so the card separates from the page.
    private static let nextStepFill = Color(light: 0x1B2A41, dark: 0x22314A)

    // MARK: - Degree Progress

    private func degreeProgressCard(_ audit: DegreeAuditResponse) -> some View {
        Button { switchToTab(1) } label: {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Degree progress")
                        .font(.headline)
                    Spacer()
                    Text("\(audit.percentComplete)%")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(AgoraPalette.brandInk)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                ProgressView(value: Double(audit.percentComplete), total: 100)
                    .tint(theme.accent)
                Text("\(Int(audit.completedCredits)) of \(Int(audit.totalRequiredCredits)) credits · \(audit.completeBucketCount) of \(audit.totalBucketCount) groups complete")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sourceNote)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
            .padding(AgoraSpacing.xl - 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Degree Progress")
    }

    private var sourceNote: String {
        if let preparedOn = appState.latestDarsAudit?.preparedOn, !preparedOn.isEmpty {
            return "Estimated from your transcript. Official DARS audit on file, prepared \(preparedOn)."
        }
        if appState.latestDarsAudit != nil {
            return "Estimated from your transcript. Official DARS audit on file."
        }
        return "Estimated from your transcript."
    }

    // MARK: - Stats

    private var statsSection: some View {
        let gpa = appState.calculatedGPA
        let stats: [(value: String, label: String)] = [
            ("\(Int(appState.totalCredits))", "Credits"),
            (gpa.map { String(format: "%.2f", $0) } ?? "N/A", "GPA"),
            ("\(appState.transcriptCourses.count)", "Courses"),
            (graduationYear.isEmpty ? "Not set" : graduationYear, "Grad year"),
        ]
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : Array(repeating: GridItem(.flexible(), spacing: AgoraSpacing.md, alignment: .leading), count: 2)
        return VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "From your transcript", icon: "doc.text")
            LazyVGrid(columns: columns, alignment: .leading, spacing: AgoraSpacing.lg) {
                ForEach(stats, id: \.label) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stat.value)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(AgoraPalette.brandInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(stat.label)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(AgoraSpacing.lg + 2)
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }

    // MARK: - Support and Advisor

    private var supportCard: some View {
        Button { switchToTab(1) } label: {
            HStack(alignment: .top, spacing: AgoraSpacing.md) {
                Image(systemName: "lifepreserver")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Academic support ready").font(.subheadline.weight(.semibold))
                    Text("Resources for \(appState.strugglingCourses.joined(separator: ", ")) are in Degree Progress.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(AgoraSpacing.lg)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
        .buttonStyle(.plain)
    }

    /// A quiet secondary entry; the next-step card stays the primary action.
    private var advisorCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            switchToTab(2)
        } label: {
            HStack(spacing: AgoraSpacing.md) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 36, height: 36)
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask your advisor")
                        .font(.subheadline.weight(.semibold))
                    Text("Courses, plans, or a tricky concept.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AgoraSpacing.lg)
            .padding(.vertical, AgoraSpacing.md)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
        .buttonStyle(.plain)
    }

    private func switchToTab(_ tab: Int) {
        setTabWithoutPageTraversal { selectedTab = tab }
    }

    // MARK: - School Tips

    /// Virginia Tech–specific guidance, shown only to Virginia Tech students.
    /// Compact expandable rows keep it secondary to the student's next action.
    private var tipsSection: some View {
        let tips: [(icon: String, title: String, detail: String)] = [
            ("calendar", "Plan ahead",
             "Register before advising deadlines — popular sections fill up fast."),
            ("person.2", "Go to office hours early",
             "Go early in the semester, not just before exams. Professors remember you."),
            ("checklist", "Keep Pathways in view",
             "Knock out Pathways requirements early — they're easy to defer and painful to cram in senior year."),
            ("building.columns", "Use campus resources",
             "The VT Writing Center, Math Emporium, and CS tutoring are free and underused."),
        ]
        return VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Tips for \(theme.name)", icon: "lightbulb")
            VStack(spacing: 0) {
                ForEach(Array(tips.enumerated()), id: \.offset) { index, tip in
                    if index > 0 {
                        Divider().padding(.leading, AgoraSpacing.lg + 24 + AgoraSpacing.md)
                    }
                    AgoraDisclosureRow(
                        title: tip.title,
                        detail: tip.detail,
                        icon: dynamicTypeSize.isAccessibilitySize ? nil : tip.icon
                    )
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(AppState())
}
