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
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    homeHeader
                        .padding(.top, AgoraSpacing.md)
                    nextStepCard
                    if let audit = appState.latestDegreeAudit, appState.hasTranscript {
                        degreeProgressCard(audit)
                    }
                    if appState.hasTranscript {
                        statsSection
                    }
                    if appState.needsTutoringSupport {
                        supportCard
                    }
                    advisorCard
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
        HokieCompactPill(
            title: "Home",
            symbol: "house.fill",
            accent: theme.accent,
            progress: compactTitleProgress
        )
        .padding(.top, 8)
    }

    // MARK: - Header

    private var homeHeader: some View {
        HokiePageHeader(
            title: greeting,
            eyebrow: theme.isSchool ? theme.name : AgoraBrand.name,
            subtitle: programLine,
            symbol: "house.fill",
            accent: theme.accent
        )
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
        let icon: String
        /// `nil` opens transcript import.
        let tab: Int?
    }

    private var nextStep: NextStep {
        guard appState.hasTranscript else {
            return NextStep(
                eyebrow: "Start here",
                title: "Import your transcript",
                detail: "Your credits, GPA, courses, and degree progress are calculated from it. Nothing is shown until it's imported.",
                action: "Import transcript",
                icon: "arrow.up.doc.fill",
                tab: nil
            )
        }
        guard let audit = appState.latestDegreeAudit else {
            return NextStep(
                eyebrow: "Next step",
                title: "Check your degree progress",
                detail: "See which requirement groups your transcript covers and what's left.",
                action: "Open Degree Progress",
                icon: "checklist.checked",
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
                icon: "exclamationmark.triangle.fill",
                tab: 1
            )
        }
        if remaining > 0 {
            return NextStep(
                eyebrow: "Next step",
                title: "\(remaining) requirement group\(remaining == 1 ? "" : "s") remaining",
                detail: "See the courses still missing from each group.",
                action: "Review remaining requirements",
                icon: "checklist.checked",
                tab: 1
            )
        }
        return NextStep(
            eyebrow: "Next step",
            title: "Every tracked group is marked complete",
            detail: "Confirm with your official audit and your academic advisor before you apply to graduate.",
            action: "Open Degree Progress",
            icon: "checkmark.circle.fill",
            tab: 1
        )
    }

    private var nextStepCard: some View {
        let step = nextStep
        return VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            Label(step.eyebrow.uppercased(), systemImage: step.icon)
                .font(.agoraEyebrow)
                .tracking(1.2)
                .foregroundStyle(theme.accent)
            Text(step.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(step.action) {
                if let tab = step.tab {
                    switchToTab(tab)
                } else {
                    showTranscriptImport = true
                }
            }
                .buttonStyle(.agoraPrimary)
                .padding(.top, AgoraSpacing.xs)
        }
        .padding(AgoraSpacing.xl - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    // MARK: - Degree Progress

    private func degreeProgressCard(_ audit: DegreeAuditResponse) -> some View {
        Button { switchToTab(1) } label: {
            VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Degree progress")
                        .font(.headline)
                    Spacer()
                    Text("\(audit.percentComplete)%")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(theme.accent)
                }
                ProgressView(value: Double(audit.percentComplete), total: 100)
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
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "From your transcript", icon: "doc.text.fill", color: theme.accent)
            LazyVGrid(columns: columns, spacing: AgoraSpacing.md) {
                statTile(value: "\(Int(appState.totalCredits))", label: "Credits", icon: "books.vertical.fill")
                statTile(
                    value: gpa.map { String(format: "%.2f", $0) } ?? "N/A",
                    label: "GPA",
                    icon: "chart.bar.fill",
                    iconColor: gpa.map { gpaColor($0) }
                )
                statTile(value: "\(appState.transcriptCourses.count)", label: "Courses", icon: "checkmark.circle.fill")
                statTile(
                    value: graduationYear.isEmpty ? "Not set" : graduationYear,
                    label: "Grad year",
                    icon: "graduationcap.fill"
                )
            }
        }
    }

    private func statTile(value: String, label: String, icon: String, iconColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.xs) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor ?? theme.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AgoraSpacing.lg)
        .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Support and Advisor

    private var supportCard: some View {
        HStack(alignment: .top, spacing: AgoraSpacing.md) {
            Image(systemName: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Academic support ready").font(.subheadline.weight(.semibold))
                Text("Resources for \(appState.strugglingCourses.joined(separator: ", ")) are in Degree Progress.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(AgoraSpacing.lg)
        .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        .onTapGesture { switchToTab(1) }
        .accessibilityAddTraits(.isButton)
    }

    private var advisorCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            switchToTab(2)
        } label: {
            HStack(spacing: AgoraSpacing.md) {
                HokieIconTile(symbol: "bubble.left.and.bubble.right.fill", color: theme.accent, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask your advisor")
                        .font(.subheadline.weight(.semibold))
                    Text("Plan courses or work through a concept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(AgoraSpacing.lg)
            .glassSurface(cornerRadius: AgoraRadius.card)
        }
        .buttonStyle(.plain)
    }

    private func switchToTab(_ tab: Int) {
        setTabWithoutPageTraversal { selectedTab = tab }
    }

    // MARK: - School Tips

    /// Virginia Tech–specific advice, shown only to Virginia Tech students.
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Tips for \(theme.name)", icon: "lightbulb.fill", color: theme.accent)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: AgoraSpacing.md) {
                    tipCard(icon: "calendar.badge.clock",
                            title: "Plan Ahead",
                            body: "Register before advising deadlines — popular sections fill up fast.")
                    tipCard(icon: "person.2.fill",
                            title: "Office Hours",
                            body: "Go early in the semester, not just before exams. Professors remember you.")
                    tipCard(icon: "checkmark.seal.fill",
                            title: "Pathways",
                            body: "Knock out Pathways requirements early — they're easy to defer and painful to cram in senior year.")
                    tipCard(icon: "brain.head.profile",
                            title: "Ask Anything",
                            body: "Your AI advisor knows the VT CS curriculum. No question is too small.")
                    tipCard(icon: "building.columns.fill",
                            title: "Use Resources",
                            body: "The VT Writing Center, Math Emporium, and CS tutoring are free and underused.")
                }
                .padding(.vertical, 4)
            }
            .scrollClipDisabled()
        }
    }

    private func tipCard(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: dynamicTypeSize.isAccessibilitySize ? 280 : 200, alignment: .leading)
        .padding(AgoraSpacing.lg)
        .glassSurface(cornerRadius: AgoraRadius.inset + 2)
    }
}

#Preview {
    HomeView(selectedTab: .constant(0))
        .environmentObject(AppState())
}
