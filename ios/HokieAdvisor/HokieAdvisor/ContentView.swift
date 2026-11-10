import SwiftUI
import Combine
import UniformTypeIdentifiers
import UIKit

// MARK: - Markdown Helper

extension String {
    var markdown: AttributedString {
        (try? AttributedString(markdown: self)) ?? AttributedString(self)
    }
}

// MARK: - Design System

extension Color {
    static let vtBurgundy     = Color(red: 0.525, green: 0.122, blue: 0.255)
    static let vtBurgundyDark = Color(red: 0.315, green: 0.073, blue: 0.153)
    static let vtOrange       = Color(red: 0.898, green: 0.459, blue: 0.122)
    static let hokieStone     = Color(red: 0.459, green: 0.471, blue: 0.482)
}

enum HokieChrome {
    static let floatingTabBottomPadding: CGFloat = -16
    static let contentBottomInset: CGFloat = 150
    static let chatComposerRestingBottom: CGFloat = 71
    static let chatMessageRestingBottom: CGFloat = 249
}

// MARK: - Glass Surfaces
//
// Surfaces are flat, opaque cards on the neutral background, separated by a
// hairline stroke rather than a shadow. The `glass*` modifier names are kept
// so call sites stay unchanged.

private enum HokieGlassPalette {
    static func surfaceFill(for colorScheme: ColorScheme) -> Color {
        AgoraPalette.surface
    }

    static func insetFill(for colorScheme: ColorScheme) -> Color {
        AgoraPalette.surfaceInset.opacity(colorScheme == .dark ? 0.85 : 0.75)
    }

    /// Kept nearly invisible: surfaces read by fill contrast, not elevation.
    static func shadow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .clear : Color.black.opacity(0.018)
    }

    static func stroke(opacity: Double, for colorScheme: ColorScheme) -> Color {
        AgoraPalette.stroke.opacity(colorScheme == .dark ? 0.55 : 0.6)
    }
}

private struct HokieGlassRoundedBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let strokeOpacity: Double
    var inset = false
    var elevated = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        shape
            .fill(inset ? HokieGlassPalette.insetFill(for: colorScheme) : HokieGlassPalette.surfaceFill(for: colorScheme))
            .overlay {
                shape.stroke(HokieGlassPalette.stroke(opacity: strokeOpacity, for: colorScheme), lineWidth: 0.75)
            }
            .shadow(
                color: elevated ? HokieGlassPalette.shadow(for: colorScheme) : .clear,
                radius: elevated ? 6 : 0,
                x: 0,
                y: elevated ? 2 : 0
            )
    }
}

private struct HokieGlassCapsuleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let strokeOpacity: Double
    var elevated = true

    var body: some View {
        Capsule()
            .fill(HokieGlassPalette.surfaceFill(for: colorScheme))
            .overlay {
                Capsule().stroke(HokieGlassPalette.stroke(opacity: strokeOpacity, for: colorScheme), lineWidth: 0.75)
            }
            .shadow(
                color: elevated ? HokieGlassPalette.shadow(for: colorScheme) : .clear,
                radius: elevated ? 6 : 0,
                x: 0,
                y: elevated ? 2 : 0
            )
    }
}

private struct HokieGlassCircleBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    let strokeOpacity: Double
    var elevated = true

    var body: some View {
        Circle()
            .fill(HokieGlassPalette.surfaceFill(for: colorScheme))
            .overlay {
                Circle().stroke(HokieGlassPalette.stroke(opacity: strokeOpacity, for: colorScheme), lineWidth: 0.75)
            }
            .shadow(
                color: elevated ? HokieGlassPalette.shadow(for: colorScheme) : .clear,
                radius: elevated ? 6 : 0,
                x: 0,
                y: elevated ? 2 : 0
            )
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 24, strokeOpacity: Double = 0.09) -> some View {
        self
            .background {
                HokieGlassRoundedBackground(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity)
            }
    }

    func glassInset(cornerRadius: CGFloat = 16, strokeOpacity: Double = 0.06) -> some View {
        self
            .background {
                HokieGlassRoundedBackground(
                    cornerRadius: cornerRadius,
                    strokeOpacity: strokeOpacity,
                    inset: true,
                    elevated: false
                )
            }
    }

    func glassCapsule(strokeOpacity: Double = 0.10) -> some View {
        self
            .background {
                HokieGlassCapsuleBackground(strokeOpacity: strokeOpacity)
            }
    }

    func glassCircle(strokeOpacity: Double = 0.10) -> some View {
        self
            .background {
                HokieGlassCircleBackground(strokeOpacity: strokeOpacity)
            }
    }

    func transparentNavigationChrome() -> some View {
        self
            .toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarBackground(Color.clear, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .background(NavigationBarTransparencyView().allowsHitTesting(false))
    }

    func hokieScreenBackground() -> some View {
        self.background {
            HokieAppBackground()
                .ignoresSafeArea()
        }
    }
}

private struct NavigationBarTransparencyView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.clearNavigationChrome()
    }

    final class Controller: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            clearNavigationChrome()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            clearNavigationChrome()
        }

        func clearNavigationChrome() {
            guard let navigationBar = navigationController?.navigationBar else { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundColor = .clear
            appearance.backgroundEffect = nil
            appearance.shadowColor = .clear

            navigationBar.standardAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            if #available(iOS 15.0, *) {
                navigationBar.compactScrollEdgeAppearance = appearance
            }
            navigationBar.isTranslucent = true
            navigationBar.backgroundColor = .clear
            navigationBar.barTintColor = .clear
            navigationBar.setBackgroundImage(UIImage(), for: .default)
            navigationBar.shadowImage = UIImage()
        }
    }
}

// MARK: - Hokie Header System

struct HokieHeaderStat {
    let value: String
    let label: String
    let icon: String
}

struct HokiePageHeader<Trailing: View>: View {
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    let title: String
    let eyebrow: String
    let subtitle: String
    let symbol: String
    let accent: Color
    var stat: HokieHeaderStat?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    if !eyebrow.isEmpty {
                        Text(eyebrow)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(title)
                        .font(.system(size: min(titleSize, 48), weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(AgoraPalette.brandInk)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing()
            }
            if let stat {
                Label {
                    Text("\(stat.value) \(stat.label)")
                } icon: {
                    Image(systemName: stat.icon).foregroundStyle(accent)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 4)
    }
}

extension HokiePageHeader where Trailing == EmptyView {
    init(
        title: String,
        eyebrow: String,
        subtitle: String,
        symbol: String,
        accent: Color,
        stat: HokieHeaderStat? = nil
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
        self.stat = stat
        self.trailing = { EmptyView() }
    }
}

struct HokieSegmentedControl<Selection: Hashable>: View {
    @Environment(\.schoolTheme) private var theme

    @Binding var selection: Selection
    let options: [(value: Selection, title: String)]
    /// Overrides the school accent for the selected segment.
    var accent: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection == option.value

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .foregroundStyle(isSelected ? (accent ?? AgoraPalette.brandInk) : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .padding(.vertical, 2)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(AgoraPalette.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(AgoraPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct HokieIconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)

        ZStack {
            shape.fill(color.opacity(0.1))

            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Inline title that fades in once the large page header scrolls away, like a
/// standard navigation bar: full width, translucent, hairline bottom edge.
struct HokieCompactTitleBar: View {
    let title: String
    var progress: CGFloat

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AgoraPalette.brandInk)
            .lineLimit(1)
            // A bar title can't grow without covering content; VoiceOver and the
            // large header above it carry the full-size title.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                Rectangle()
                    .fill(AgoraPalette.background.opacity(0.96))
                    .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AgoraPalette.stroke.opacity(0.7))
                    .frame(height: 0.5)
            }
            .opacity(Double(progress))
            .allowsHitTesting(false)
            .accessibilityHidden(progress < 0.5)
    }
}

struct HokieAppBackground: View {
    var body: some View {
        AgoraPalette.background
    }
}

@MainActor
func setTabWithoutPageTraversal(_ update: () -> Void) {
    var transaction = Transaction(animation: nil)
    transaction.disablesAnimations = true
    UIView.performWithoutAnimation {
        withTransaction(transaction) {
            update()
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    @State private var isKeyboardVisible = false

    init() {
        _selectedTab = State(initialValue: Self.initialTabFromLaunchArguments())
    }

    private static func initialTabFromLaunchArguments() -> Int {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "-HokieInitialTab"),
              arguments.indices.contains(flagIndex + 1) else {
            return 0
        }

        switch arguments[flagIndex + 1].lowercased() {
        case "0", "home":
            return 0
        case "1", "audit":
            return 1
        case "2", "advisor", "chat":
            return 2
        case "3", "profile", "settings":
            return 3
        default:
            return 0
        }
        #else
        return 0
        #endif
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab)
                    .tag(0)

                DegreeAuditView()
                    .tag(1)

                ChatView()
                    .tag(2)

                SettingsView()
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isKeyboardVisible {
                FloatingTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, 24)
                    .padding(.bottom, HokieChrome.floatingTabBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .hokieScreenBackground()
        .animation(.spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08), value: isKeyboardVisible)
        .onKeyboardVisibilityChange { visible in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08)) {
                isKeyboardVisible = visible
            }
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("house",                          "Home"),
        ("checklist.checked",              "Progress"),
        ("bubble.left.and.bubble.right",   "Advisor"),
        ("person.crop.circle",             "Profile"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<items.count, id: \.self) { i in
                let isSelected = selectedTab == i
                Button {
                    setTabWithoutPageTraversal { selectedTab = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .symbolVariant(isSelected ? .fill : .none)
                            .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                            .frame(height: 22)
                        Text(items[i].label)
                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    // School maroon is too dark for text on the dark bar; the
                    // tinted pill carries the accent there instead.
                    .foregroundStyle(isSelected
                        ? (colorScheme == .dark ? AgoraPalette.brandInk : theme.accent)
                        : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(theme.accent.opacity(colorScheme == .dark ? 0.16 : 0.08))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(items[i].label)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                // Labels stay compact like a system tab bar; long-press shows
                // them enlarged at accessibility text sizes.
                .accessibilityShowsLargeContentViewer {
                    Image(systemName: items[i].icon)
                    Text(items[i].label)
                }
            }
        }
        .padding(5)
        .background(AgoraPalette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AgoraPalette.stroke.opacity(colorScheme == .dark ? 0.7 : 0.5), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 14, y: 4)
        .sensoryFeedback(.selection, trigger: selectedTab)
    }
}

// MARK: - Degree Audit View

struct DegreeAuditView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.schoolTheme) private var theme
    @StateObject private var vm = DegreeAuditViewModel()
    @StateObject private var darsVM = DarsAuditViewModel()
    @StateObject private var tutoringVM = TutoringViewModel()
    @State private var showTutoringSheet = false
    @State private var showDarsImporter = false
    @State private var showTranscriptImport = false
    @State private var showCompletedBuckets = false
    @State private var scrollOffset: CGFloat = 0

    private var compactTitleProgress: CGFloat {
        min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    auditHeader
                        .padding(.top, AgoraSpacing.md)

                    if !appState.hasTranscript && darsVM.audit == nil && !darsVM.isLoading {
                        auditEmptyState
                        if let error = darsVM.errorMessage {
                            DarsBackendStatusCard(message: error)
                        }
                    } else if darsVM.audit != nil {
                        // An official audit on file is the stronger source, so it leads.
                        officialAuditSection
                        transcriptAuditSection
                    } else {
                        transcriptAuditSection
                        officialAuditSection
                    }

                    if appState.needsTutoringSupport {
                        tutoringBanner
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
        .sheet(isPresented: $showTutoringSheet) { TutoringSheet(vm: tutoringVM) }
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
        }
        .fileImporter(
            isPresented: $showDarsImporter,
            allowedContentTypes: [.pdf, .png, .jpeg],
            allowsMultipleSelection: false,
            onCompletion: handlePickedDarsFile
        )
        .task(id: auditRefreshKey) {
            let shouldUseCachedAudit = vm.audit == nil && appState.latestDegreeAudit != nil
            loadCachedAuditsIfNeeded()
            guard appState.hasTranscript else { return }
            if shouldUseCachedAudit { return }
            await refreshAudit()
        }
    }

    // MARK: Header

    private var compactTitleOverlay: some View {
        HokieCompactTitleBar(title: "Degree Progress", progress: compactTitleProgress)
    }

    private var auditHeader: some View {
        HokiePageHeader(
            title: "Degree Progress",
            eyebrow: "",
            subtitle: programLine,
            symbol: "checklist.checked",
            accent: theme.accent,
            stat: auditHeaderStat
        )
    }

    /// The student's program as the records name it: official audit first,
    /// then the transcript audit, then the profile major.
    private var programLine: String {
        if let program = darsVM.audit?.program, !program.isEmpty {
            return program
        }
        if let audit = vm.audit {
            return "\(audit.major) \(audit.degree)"
        }
        return appState.major.isEmpty ? "Requirements, credits, and what's left." : appState.major
    }

    private var auditHeaderStat: HokieHeaderStat? {
        if darsVM.audit != nil {
            return HokieHeaderStat(value: "DARS", label: "on file", icon: "doc.text.fill")
        }
        if appState.hasTranscript {
            return HokieHeaderStat(value: "\(appState.transcriptCourses.count)", label: "courses", icon: "doc.text.fill")
        }
        return nil
    }

    // MARK: Empty State

    private var auditEmptyState: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            Text("Your degree progress will appear here")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Import your transcript and Agora estimates which requirement groups you've completed, including Pathways, electives, and retakes. Transcript estimates currently cover the Computer Science B.S.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("If you have your official DARS audit, import it too. It's the record your department uses.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Import transcript") { showTranscriptImport = true }
                .buttonStyle(.agoraPrimary)
                .padding(.top, AgoraSpacing.xs)
            Button("Import DARS audit") {
                darsVM.errorMessage = nil
                showDarsImporter = true
            }
            .buttonStyle(.agoraSecondary)
        }
        .padding(AgoraSpacing.xl - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    // MARK: Official Audit

    private var officialAuditSection: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Official audit (DARS)", icon: "building.columns.fill", color: theme.accent)

            DarsHeroCard(
                audit: darsVM.audit,
                fileName: darsVM.importedFileName,
                isLoading: darsVM.isLoading,
                onImport: {
                    darsVM.errorMessage = nil
                    showDarsImporter = true
                },
                onClear: {
                    darsVM.clear()
                    appState.latestDarsAudit = nil
                }
            )

            if darsVM.isLoading {
                statusCard(icon: "hourglass", iconColor: theme.accent,
                           title: "Reading audit",
                           subtitle: "Parsing the uploaded DARS/uAchieve file")
            }

            if let error = darsVM.errorMessage {
                DarsBackendStatusCard(message: error)
            }

            if let audit = darsVM.audit {
                DarsAuditSummaryCard(audit: audit)

                if !audit.warnings.isEmpty {
                    ForEach(audit.warnings, id: \.self) { WarningCard(text: $0) }
                }

                DarsCategoryList(categories: audit.categories)

                if !audit.sections.isEmpty {
                    DarsSectionList(sections: audit.sections)
                }
            }
        }
    }

    private var auditRefreshKey: String {
        let courses = appState.transcriptCourses
            .map { "\($0.code):\($0.grade ?? ""):\($0.credits ?? 0)" }
            .joined(separator: "|")
        return "\(appState.major)|\(courses)|\(appState.inProgressCourses.map(\.code).joined(separator: ","))"
    }

    // MARK: Transcript Audit

    private var transcriptAuditSection: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            HStack {
                SectionLabel(title: "Transcript estimate", icon: "doc.text.fill", color: theme.accent)
                Spacer()
                if appState.hasTranscript {
                    Button {
                        Task { await refreshAudit() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.bold())
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, height: 44)
                            .glassCircle(strokeOpacity: 0.08)
                    }
                    .disabled(vm.isAuditLoading)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Recalculate transcript estimate")
                }
            }

            if !appState.hasTranscript {
                VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                    Text("Import your transcript to compare it with the official audit and see an Agora estimate for each requirement group.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Import transcript") { showTranscriptImport = true }
                        .buttonStyle(.agoraSecondary)
                }
                .padding(AgoraSpacing.lg)
                .glassSurface(cornerRadius: AgoraRadius.card)
            } else if vm.isAuditLoading && vm.audit == nil {
                statusCard(icon: "hourglass", iconColor: theme.accent,
                           title: "Calculating", subtitle: "Checking your transcript against \(appState.major) requirements")
            } else if let error = vm.auditErrorMessage {
                statusCard(icon: "exclamationmark.triangle.fill", iconColor: .orange,
                           title: "Estimate unavailable", subtitle: error)
            } else if let audit = vm.audit {
                AuditSummaryCard(
                    audit: audit,
                    schoolName: theme.isSchool ? theme.name : nil,
                    source: transcriptSourceLine
                )

                if !audit.warnings.isEmpty {
                    ForEach(audit.warnings, id: \.self) { WarningCard(text: $0) }
                }

                auditBucketGroup(title: "Needs attention", buckets: audit.buckets.filter { $0.status == "attention" })
                auditBucketGroup(title: "Remaining", buckets: remainingBuckets(audit))
                completedBucketGroup(audit.buckets.filter { $0.status == "complete" })
            }
        }
    }

    private var transcriptSourceLine: String {
        var line = "Estimated by Agora from your imported transcript"
        if let calculatedAt = vm.calculatedAt {
            line += " · Updated \(calculatedAt.formatted(date: .abbreviated, time: .shortened))"
        }
        if darsVM.audit != nil {
            line += ". Where they differ, your official DARS audit takes priority."
        }
        return line
    }

    private var tutoringBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Academic support available").font(.subheadline.weight(.semibold))
                Text(appState.strugglingCourses.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("View") {
                Task {
                    await tutoringVM.load(strugglingCourses: appState.strugglingCourses,
                                          completedCourses: appState.completedCourseCodes,
                                          major: appState.major)
                    showTutoringSheet = true
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassCapsule(strokeOpacity: 0.08)
            .buttonStyle(.plain)
        }
        .padding(18)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private func auditBucketGroup(title: String, buckets: [AuditBucket]) -> some View {
        Group {
            if !buckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    bucketGroupTitle("\(title) (\(buckets.count))")
                    ForEach(buckets) { bucket in
                        AuditBucketCard(bucket: bucket)
                    }
                }
            }
        }
    }

    private func completedBucketGroup(_ buckets: [AuditBucket]) -> some View {
        Group {
            if !buckets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showCompletedBuckets.toggle() }
                    } label: {
                        HStack {
                            bucketGroupTitle("Completed (\(buckets.count))")
                            Spacer()
                            Text(showCompletedBuckets ? "Hide" : "Show")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showCompletedBuckets {
                        ForEach(buckets) { bucket in
                            AuditBucketCard(bucket: bucket)
                        }
                    }
                }
            }
        }
    }

    private func bucketGroupTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func remainingBuckets(_ audit: DegreeAuditResponse) -> [AuditBucket] {
        audit.buckets.filter { $0.status == "incomplete" } + audit.buckets.filter { $0.status == "in_progress" }
    }

    private func refreshAudit() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-HokieVisualQA") {
            vm.loadVisualQASampleAudit(major: appState.major)
            appState.latestDegreeAudit = vm.audit
            return
        }
        #endif

        await vm.runAudit(
            transcript: appState.transcriptCourses,
            major: appState.major,
            inProgressCourses: appState.inProgressCourses.map(\.code)
        )
        appState.latestDegreeAudit = vm.audit
    }

    private func loadCachedAuditsIfNeeded() {
        if vm.audit == nil {
            vm.loadCachedAudit(appState.latestDegreeAudit)
        }
        if darsVM.audit == nil {
            darsVM.loadCachedAudit(appState.latestDarsAudit)
        }
    }

    private func handlePickedDarsFile(_ pickerResult: Result<[URL], Error>) {
        switch pickerResult {
        case .failure(let error):
            darsVM.errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                darsVM.errorMessage = "Could not read the selected audit file."
                return
            }
            let mime: String
            switch url.pathExtension.lowercased() {
            case "pdf": mime = "application/pdf"
            case "png": mime = "image/png"
            default: mime = "image/jpeg"
            }
            Task {
                appState.latestDarsAudit = await darsVM.upload(fileData: data, mimeType: mime, fileName: url.lastPathComponent)
            }
        }
    }
}

// MARK: - Tutoring View Model

@MainActor
final class TutoringViewModel: ObservableObject {
    @Published var response: TutoringResponse? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func load(strugglingCourses: [String], completedCourses: [String], major: String) async {
        guard !strugglingCourses.isEmpty else { return }
        isLoading = true; errorMessage = nil
        do {
            response = try await APIService.fetchTutoring(
                request: TutoringRequest(struggling_courses: strugglingCourses,
                                        completed_courses: completedCourses, major: major))
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - Tutoring Sheet

struct TutoringSheet: View {
    @Environment(\.schoolTheme) private var theme
    @ObservedObject var vm: TutoringViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    centeredLoadingView(label: "Finding resources for you...")
                } else if let response = vm.response {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !response.encouragement.isEmpty {
                                Text(response.encouragement.markdown)
                                    .font(.subheadline).lineSpacing(4)
                                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .glassSurface(cornerRadius: 24)
                            }
                            if !response.resources.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(title: "Resources", icon: "building.columns.fill", color: theme.accent)
                                    ForEach(response.resources) { TutoringResourceCard(resource: $0) }
                                }
                            }
                            if !response.tips.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    SectionLabel(title: "Study Tips", icon: "lightbulb.fill", color: .orange)
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(response.tips, id: \.self) { tip in
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(theme.accent)
                                                    .font(.footnote).padding(.top, 2)
                                                Text(tip.markdown).font(.subheadline)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                    }
                                    .padding(18)
                                    .glassSurface(cornerRadius: 24)
                                }
                            }
                        }
                        .padding()
                    }
                } else if let error = vm.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle).foregroundStyle(.orange)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Academic Support",
                    subtitle: "Tutoring, resources, and next steps",
                    symbol: "lifepreserver.fill",
                    accent: theme.accent
                ) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 34, height: 34)
                            .glassCircle(strokeOpacity: 0.08)
                    }
                    .accessibilityLabel("Close")
                    .buttonStyle(.plain)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
    }
}

struct TutoringResourceCard: View {
    @Environment(\.schoolTheme) private var theme
    let resource: TutoringResource

    private var typeIcon: String {
        switch resource.type {
        case "tutoring": return "person.2.fill"
        case "study_group": return "person.3.fill"
        case "office_hours": return "clock.fill"
        case "online": return "globe"
        case "writing_center": return "pencil.and.scribble"
        case "ai_tutor": return "brain.head.profile"
        default: return "book.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            circleIcon(typeIcon, color: theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(resource.name).font(.subheadline.bold())
                Text(resource.description).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Shared UI Helpers

func circleIcon(_ icon: String, color: Color, size: CGFloat = 48) -> some View {
    HokieIconTile(symbol: icon, color: color, size: size)
}

func statusCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
    HStack(spacing: 14) {
        circleIcon(icon, color: iconColor)
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(18)
    .glassSurface(cornerRadius: 24)
}

func gpaColor(_ gpa: Double) -> Color {
    if gpa >= 3.7 { return .green }
    if gpa >= 3.0 { return .blue }
    if gpa >= 2.0 { return .orange }
    return .red
}

func centeredLoadingView(label: String) -> some View {
    VStack(spacing: 14) {
        ProgressView().scaleEffect(1.3)
        Text(label).font(.subheadline).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity).padding(.top, 48)
}

// MARK: - SectionLabel

/// A compact expandable row for guidance and FAQs: title plus a small chevron,
/// detail revealed in place. Place inside a grouped surface with dividers.
struct AgoraDisclosureRow: View {
    let title: String
    let detail: String
    var icon: String? = nil
    var titleFont: Font = .subheadline.weight(.medium)
    var detailFont: Font = .footnote
    @State private var isExpanded: Bool

    init(
        title: String,
        detail: String,
        icon: String? = nil,
        titleFont: Font = .subheadline.weight(.medium),
        detailFont: Font = .footnote,
        initiallyExpanded: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.titleFont = titleFont
        self.detailFont = detailFont
        _isExpanded = State(initialValue: initiallyExpanded)
    }

    /// Detail text lines up with the title, past the icon column when shown.
    private var detailLeading: CGFloat { icon == nil ? 0 : 24 + AgoraSpacing.md }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .center, spacing: AgoraSpacing.md) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(AgoraPalette.brandInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: AgoraSpacing.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, AgoraSpacing.sm)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides details" : "Shows details")

            if isExpanded {
                Text(detail)
                    .font(detailFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, detailLeading)
                    .padding(.bottom, AgoraSpacing.md)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, AgoraSpacing.lg)
    }
}

struct SectionLabel: View {
    let title: String
    let icon: String
    var color: Color = .primary

    /// `icon` and `color` are accepted for existing call sites; section titles
    /// stay text-only so headings don't compete with content.
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(AgoraPalette.brandInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct HokieSheetHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AgoraPalette.brandInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(AgoraPalette.background.opacity(0.96))
    }
}

extension HokieSheetHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, symbol: String, accent: Color) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.accent = accent
        self.trailing = { EmptyView() }
    }
}

// MARK: - Degree Audit Cards

struct AuditSummaryCard: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let audit: DegreeAuditResponse
    var schoolName: String? = nil
    var source: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(audit.major) \(audit.degree)")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([schoolName, "Catalog \(audit.catalogYear)"].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(audit.percentComplete)%")
                    .font(.title2.bold())
                    .foregroundStyle(theme.accent)
            }

            ProgressView(value: Double(audit.percentComplete), total: 100)
                .accessibilityLabel("Estimated progress")
                .accessibilityValue("\(audit.percentComplete) percent")

            let metrics = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            metrics {
                auditMetric(value: "\(Int(audit.completedCredits))/\(Int(audit.totalRequiredCredits))", label: "Credits")
                auditMetric(value: "\(audit.completeBucketCount)/\(audit.totalBucketCount)", label: "Requirement groups")
            }

            if let source {
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private func auditMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassInset(cornerRadius: AgoraRadius.inset)
    }
}

struct AuditBucketCard: View {
    let bucket: AuditBucket

    private var statusColor: Color {
        switch bucket.status {
        case "complete": return .green
        case "attention": return .orange
        case "in_progress": return .blue
        default: return .hokieStone
        }
    }

    private var statusIcon: String {
        switch bucket.status {
        case "complete": return "checkmark.circle.fill"
        case "attention": return "exclamationmark.triangle.fill"
        case "in_progress": return "clock.fill"
        default: return "circle"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)
                .font(.headline)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(bucket.title)
                        .font(.subheadline.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    if bucket.requiredCredits > 0 {
                        Text("\(Int(bucket.completedCredits))/\(Int(bucket.requiredCredits)) cr")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                if !bucket.matchedCourses.isEmpty {
                    Text(bucket.matchedCourses.prefix(4).joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !bucket.missingItems.isEmpty {
                    Text("Missing: \(bucket.missingItems.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = bucket.notes.first {
                    Text(note)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - DARS / uAchieve Cards

struct DarsHeroCard: View {
    @Environment(\.schoolTheme) private var theme

    let audit: DarsAuditResponse?
    let fileName: String?
    let isLoading: Bool
    let onImport: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
            VStack(alignment: .leading, spacing: 4) {
                Text(audit == nil ? "Import your official audit" : "Official audit on file")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(audit == nil
                     ? "Upload the PDF or a screenshot from DARS / uAchieve. When it's on file, it's the source of truth over the transcript estimate."
                     : loadedSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(action: onImport) {
                    Label(audit == nil ? "Import DARS audit" : "Replace audit", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(.agoraSecondary)
                .disabled(isLoading)

                if audit != nil {
                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 52, height: 52)
                            .glassCircle(strokeOpacity: 0.08)
                    }
                    .accessibilityLabel("Remove DARS audit")
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AgoraSpacing.xl - 4)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    /// Only facts the import provides: prepared date and file name.
    private var loadedSubtitle: String {
        var parts: [String] = []
        if let preparedOn = audit?.preparedOn, !preparedOn.isEmpty {
            parts.append("Prepared \(preparedOn)")
        }
        if let fileName, !fileName.isEmpty {
            parts.append(fileName)
        }
        return parts.isEmpty ? "Imported DARS audit" : parts.joined(separator: " · ")
    }
}

struct DarsBackendStatusCard: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "network.slash")
                .foregroundStyle(.orange)
                .font(.headline)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Could not analyze audit")
                    .font(.subheadline.bold())
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .glassSurface(cornerRadius: 20)
    }
}

struct DarsAuditSummaryCard: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let audit: DarsAuditResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(audit.program ?? "Degree audit")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if theme.isSchool {
                    Text(theme.name)
                        .font(.caption).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { pills }
                    VStack(alignment: .leading, spacing: 6) { pills }
                }
                if let graduationDate = audit.graduationDate, !graduationDate.isEmpty {
                    Text("Graduation term on audit: \(graduationDate)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            let metrics = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            metrics {
                darsMetric(value: audit.universityGPA.map { String(format: "%.3f", $0) } ?? "—", label: "University GPA")
                darsMetric(value: audit.inMajorGPA.map { String(format: "%.3f", $0) } ?? "—", label: "In-Major GPA")
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    @ViewBuilder
    private var pills: some View {
        if let programCode = audit.programCode, !programCode.isEmpty {
            DarsPill(text: programCode, color: theme.accent)
        }
        if let catalogYear = audit.catalogYear, !catalogYear.isEmpty {
            DarsPill(text: "Catalog \(catalogYear)", color: .secondary)
        }
        if let auditType = audit.auditType, !auditType.isEmpty {
            DarsPill(text: auditType, color: .secondary)
        }
    }

    private func darsMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassInset(cornerRadius: 16)
    }
}

struct DarsCategoryList: View {
    let categories: [DarsCategory]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Categories")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(categories) { category in
                DarsCategoryCard(category: category)
            }
        }
    }
}

struct DarsCategoryCard: View {
    let category: DarsCategory

    private var totalHours: Double {
        let visibleTotal = (category.completeHours ?? 0) +
            (category.inProgressHours ?? 0) +
            (category.unfulfilledHours ?? 0) +
            (category.plannedHours ?? 0)
        return max(category.requiredHours ?? visibleTotal, visibleTotal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(category.title)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if let required = category.requiredHours {
                    Text("\(formatHours(required)) hrs")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else if let gpa = category.gpa {
                    Text(String(format: "%.3f", gpa))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }

            DarsProgressBar(category: category, totalHours: totalHours)

            HStack(spacing: 10) {
                darsLegend("Complete", category.completeHours, .green)
                darsLegend("Progress", category.inProgressHours, .blue)
                darsLegend("Open", category.unfulfilledHours, .red)
                darsLegend("Planned", category.plannedHours, .purple)
            }

            if let note = category.notes.first {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 20)
    }

    private var statusColor: Color {
        switch category.status {
        case "complete": return .green
        case "in_progress": return .blue
        case "unfulfilled": return .red
        case "planned": return .purple
        default: return .hokieStone
        }
    }

    private var statusIcon: String {
        switch category.status {
        case "complete": return "checkmark.circle.fill"
        case "in_progress": return "clock.fill"
        case "unfulfilled": return "xmark.circle.fill"
        case "planned": return "calendar.badge.clock"
        default: return "questionmark.circle.fill"
        }
    }

    private func darsLegend(_ title: String, _ hours: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(title) \(formatHours(hours ?? 0))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DarsProgressBar: View {
    let category: DarsCategory
    let totalHours: Double

    private var segments: [(Double, Color)] {
        [
            (category.completeHours ?? 0, .green),
            (category.inProgressHours ?? 0, .blue),
            (category.unfulfilledHours ?? 0, .red),
            (category.plannedHours ?? 0, .purple),
        ].filter { $0.0 > 0 }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.08))
                } else {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(segment.1)
                            .frame(width: max(4, proxy.size.width * CGFloat(segment.0 / totalHours)))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 11)
        .glassInset(cornerRadius: 6)
    }
}

struct DarsSectionList: View {
    let sections: [DarsSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sections")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(sections) { section in
                DarsSectionCard(section: section)
            }
        }
    }
}

struct DarsSectionCard: View {
    let section: DarsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(section.title)
                    .font(.subheadline.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }

            if !section.matchedCourses.isEmpty {
                Text(section.matchedCourses.prefix(6).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !section.missingItems.isEmpty {
                Text("Missing: \(section.missingItems.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let note = section.notes.first {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 20)
    }

    private var statusColor: Color {
        switch section.status {
        case "complete": return .green
        case "in_progress": return .blue
        case "unfulfilled": return .red
        case "planned": return .purple
        default: return .hokieStone
        }
    }

    private var statusIcon: String {
        switch section.status {
        case "complete": return "checkmark.circle.fill"
        case "in_progress": return "clock.fill"
        case "unfulfilled": return "xmark.circle.fill"
        case "planned": return "calendar.badge.clock"
        default: return "questionmark.circle.fill"
        }
    }
}

struct DarsPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.16), lineWidth: 1))
    }
}

private func formatHours(_ value: Double) -> String {
    value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
}

// MARK: - MarkdownBody

struct MarkdownBody: View {
    let text: String
    var baseFont: Font = .subheadline
    var baseColor: Color = .primary

    @Environment(\.colorScheme) private var colorScheme

    private enum Block {
        case heading(Int, String)
        case bullet(String)
        case numbered(Int, String)
        case paragraph(String)
        case math(String)
        case code(language: String, content: String)
        case graph(String)
        case resource(title: String, url: URL)
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var pending = ""
        var inCode = false
        var inMath = false
        var mathEndEnvironment: String?
        var codeLang = ""
        var codeLines: [String] = []
        var mathLines: [String] = []

        for line in text.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)

            if inMath {
                if let environment = mathEndEnvironment {
                    mathLines.append(line)
                    if LaTeXFormatter.endsMathEnvironment(t, environment: environment) {
                        result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                        inMath = false; mathEndEnvironment = nil; mathLines = []
                    }
                } else if t == "$$" || t == "\\]" || t == "\\\\]" {
                    result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                    inMath = false; mathLines = []
                } else {
                    mathLines.append(line)
                }
                continue
            }

            if inCode {
                if t.hasPrefix("```") {
                    let content = codeLines.joined(separator: "\n")
                        .trimmingCharacters(in: .newlines)
                    if codeLang.lowercased() == "graph" {
                        result.append(.graph(content))
                    } else {
                        result.append(.code(language: codeLang, content: content))
                    }
                    inCode = false; codeLang = ""; codeLines = []
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if LaTeXFormatter.hasBareEnvironment(t), let environment = LaTeXFormatter.startedMathEnvironment(t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                inMath = true
                mathEndEnvironment = environment
                mathLines = [line]
                if LaTeXFormatter.endsMathEnvironment(t, environment: environment) {
                    result.append(.math(t))
                    inMath = false; mathEndEnvironment = nil; mathLines = []
                }
                continue
            }

            if t == "$$" || t == "\\[" || t == "\\\\[" {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                inMath = true; mathLines = []
                continue
            }

            if t.hasPrefix("$$"), t.hasSuffix("$$"), t.count > 4 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if t.hasPrefix("\\["), t.hasSuffix("\\]"), t.count > 4 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if t.hasPrefix("\\\\["), t.hasSuffix("\\\\]"), t.count > 6 {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(String(t.dropFirst(3).dropLast(3)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if LaTeXFormatter.hasBareEnvironment(t), LaTeXFormatter.looksLikeDisplayMath(t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.math(t))
                continue
            }

            if t.hasPrefix("```") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                codeLang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                inCode = true; codeLines = []
                continue
            }

            if t.isEmpty {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
            } else if let resource = MarkdownBody.youtubeResource(from: t) {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.resource(title: resource.title, url: resource.url))
            } else if t.hasPrefix("### ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(3, String(t.dropFirst(4))))
            } else if t.hasPrefix("## ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(2, String(t.dropFirst(3))))
            } else if t.hasPrefix("# ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.heading(1, String(t.dropFirst(2))))
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") {
                if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                result.append(.bullet(String(t.dropFirst(2))))
            } else {
                let parts = t.components(separatedBy: ". ")
                if parts.count >= 2, let num = Int(parts[0]), parts[0].count <= 3 {
                    if !pending.isEmpty { result.append(.paragraph(pending)); pending = "" }
                    result.append(.numbered(num, parts.dropFirst().joined(separator: ". ")))
                } else {
                    pending += pending.isEmpty ? t : " \(t)"
                }
            }
        }
        if inMath, !mathLines.isEmpty {
            result.append(.math(mathLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if !pending.isEmpty { result.append(.paragraph(pending)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    inline(content, font: level == 1 ? .headline : .subheadline)
                        .font(level == 1 ? .headline : .subheadline).fontWeight(.semibold)
                        .foregroundStyle(baseColor).padding(.top, level <= 2 ? 6 : 2)
                case .bullet(let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                        inline(content, font: baseFont).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .numbered(let number, let content):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(number).").font(baseFont).foregroundStyle(baseColor.opacity(0.6))
                            .frame(minWidth: 20, alignment: .trailing)
                        inline(content, font: baseFont).font(baseFont).foregroundStyle(baseColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let content):
                    inline(content, font: baseFont).font(baseFont).foregroundStyle(baseColor)
                        .fixedSize(horizontal: false, vertical: true)
                case .math(let content):
                    MathDisplayView(latex: content)
                        .padding(.vertical, 4)
                case .code(let lang, let content):
                    CodeBlockView(language: lang, code: content)
                        .padding(.vertical, 2)
                case .graph(let content):
                    GraphDiagramView(content: content)
                        .padding(.vertical, 4)
                case .resource(let title, let url):
                    ResourceLinkCard(title: title, url: url)
                        .padding(.vertical, 3)
                }
            }
        }
    }

    private func inline(_ content: String, font: Font) -> Text {
        MathText.text(
            content,
            textStyle: UIFont.TextStyle(font),
            color: UIColor(baseColor).resolved(for: colorScheme)
        )
    }

    private static func youtubeResource(from line: String) -> (title: String, url: URL)? {
        guard line.localizedCaseInsensitiveContains("youtube.com") ||
                line.localizedCaseInsensitiveContains("youtu.be") else {
            return nil
        }

        let markdownPattern = #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#
        if let range = line.range(of: markdownPattern, options: .regularExpression) {
            let match = String(line[range])
            let title = match.replacingOccurrences(of: #"^\[([^\]]+)\].*$"#, with: "$1", options: .regularExpression)
            let urlString = match.replacingOccurrences(of: #"^.*\]\((https?://[^)\s]+)\).*$"#, with: "$1", options: .regularExpression)
            if let url = URL(string: urlString) {
                return (title, url)
            }
        }

        let urlPattern = #"https?://[^\s)]+"#
        guard let range = line.range(of: urlPattern, options: .regularExpression),
              let url = URL(string: String(line[range])) else {
            return nil
        }
        return ("YouTube resource", url)
    }
}

// MARK: - LaTeX Rendering

struct ResourceLinkCard: View {
    @Environment(\.schoolTheme) private var theme

    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: "play.rectangle.fill")
                    .font(.headline)
                    .foregroundStyle(theme.accent)
                    .frame(width: 34, height: 34)
                    .glassCircle(strokeOpacity: 0.08)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.trimmingCharacters(in: CharacterSet(charactersIn: "-* ")))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(url.host() ?? "YouTube")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .glassInset(cornerRadius: 14)
        }
    }
}

struct GraphDiagramView: View {
    let content: String

    @Environment(\.schoolTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stepIndex = 0

    var body: some View {
        if let graph = GraphLayoutCache.graph(for: content) {
            diagram(graph)
        } else {
            // Unparseable or oversized block: show what the advisor wrote.
            CodeBlockView(language: "graph", code: content)
        }
    }

    private func diagram(_ graph: SimpleGraph) -> some View {
        let steps = graph.steps
        let current = steps.isEmpty ? nil : steps[min(stepIndex, steps.count - 1)]
        let highlight = current?.highlight ?? graph.highlight

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.caption.bold())
                    .foregroundStyle(theme.accent)
                Text("Visual model")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                canvas(graph, highlight: highlight, size: proxy.size)
            }
            .frame(height: canvasHeight(graph))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: stepIndex)

            if !steps.isEmpty {
                stepControls(count: steps.count, caption: current?.caption)
            }
        }
        .padding(14)
        .glassInset(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary(graph))
    }

    private func canvasHeight(_ graph: SimpleGraph) -> CGFloat {
        graph.isTree ? min(max(CGFloat(graph.layerCount) * 70, 160), 340) : 230
    }

    private func canvas(_ graph: SimpleGraph, highlight: SimpleGraph.Highlight, size: CGSize) -> some View {
        let widest = graph.nodes.map(nodeRadius).max() ?? 19
        let positions = graph.positions(in: size, inset: widest + 6)
        let currentNode = highlight.nodes.last
        return ZStack {
            ForEach(Array(graph.edges.enumerated()), id: \.offset) { _, edge in
                if let a = positions[edge.from], let b = positions[edge.to] {
                    let lit = graph.isHighlighted(edge, in: highlight)
                    let tint = lit ? theme.accent : Color.secondary.opacity(0.45)
                    let end = trimmed(from: a, to: b, by: boundaryDistance(edge.to, from: a, to: b))
                    let start = trimmed(from: b, to: a, by: boundaryDistance(edge.from, from: b, to: a))

                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: lit ? 3 : 1.5, lineCap: .round))

                    if edge.directed {
                        arrowhead(at: end, from: start)
                            .fill(tint)
                    }

                    if let weight = edge.weight {
                        Text(weight)
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(lit ? theme.accent : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.regularMaterial, in: Capsule())
                            .position(weightPosition(a, b))
                    }
                }
            }

            ForEach(graph.nodes, id: \.self) { node in
                if let point = positions[node] {
                    nodeView(node, highlighted: highlight.nodes.contains(node), isCurrent: node == currentNode && !graph.steps.isEmpty)
                        .position(point)
                }
            }
        }
    }

    private func stepControls(count: Int, caption: String?) -> some View {
        let index = min(stepIndex, count - 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                stepButton("chevron.left", label: "Previous step", enabled: index > 0) { stepIndex = index - 1 }
                Text("Step \(index + 1) of \(count)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                stepButton("chevron.right", label: "Next step", enabled: index < count - 1) { stepIndex = index + 1 }
            }
            if let caption {
                Text(caption)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func stepButton(_ icon: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(enabled ? theme.accent : Color.secondary.opacity(0.4))
                .frame(width: 36, height: 36)
                .glassCircle(strokeOpacity: 0.08)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func nodeView(_ label: String, highlighted: Bool, isCurrent: Bool) -> some View {
        Text(label)
            .font(.caption.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(highlighted ? theme.onAccent : .primary)
            .padding(.horizontal, label.count > 3 ? 8 : 0)
            .frame(maxWidth: 96)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: nodeRadius(label) * 2, height: 38)
            .background(highlighted ? theme.accent : Color.primary.opacity(0.08), in: Capsule())
            .overlay(
                Capsule().stroke(
                    isCurrent ? theme.secondaryAccent : (highlighted ? theme.accent : Color.secondary.opacity(0.35)),
                    lineWidth: isCurrent ? 2.5 : 1
                )
            )
            .shadow(color: highlighted ? theme.accent.opacity(0.22) : .clear, radius: 8, y: 4)
    }

    /// Approximate half-width of a node capsule, so edges stop at its edge.
    private func nodeRadius(_ label: String) -> CGFloat {
        label.count > 3 ? min(CGFloat(label.count) * 3.6 + 8, 48) : 19
    }

    /// Distance from a node's center to its capsule edge along the a→b direction,
    /// so edges meet wide labels at the side and the top/bottom alike.
    private func boundaryDistance(_ label: String, from a: CGPoint, to b: CGPoint) -> CGFloat {
        let halfWidth = nodeRadius(label), halfHeight: CGFloat = 19
        let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
        let length = max(hypot(dx, dy), 0.001)
        let cosine = dx / length, sine = dy / length
        return min(cosine > 0.001 ? halfWidth / cosine : .infinity, sine > 0.001 ? halfHeight / sine : .infinity)
    }

    private func trimmed(from a: CGPoint, to b: CGPoint, by distance: CGFloat) -> CGPoint {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let t = max(length - distance - 2, 0) / length
        return CGPoint(x: a.x + dx * t, y: a.y + dy * t)
    }

    private func arrowhead(at tip: CGPoint, from tail: CGPoint) -> Path {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let length: CGFloat = 10
        let spread: CGFloat = .pi / 7
        return Path { path in
            path.move(to: tip)
            path.addLine(to: CGPoint(x: tip.x - length * cos(angle - spread), y: tip.y - length * sin(angle - spread)))
            path.addLine(to: CGPoint(x: tip.x - length * cos(angle + spread), y: tip.y - length * sin(angle + spread)))
            path.closeSubpath()
        }
    }

    /// Midpoint nudged off the line so the label does not sit on the stroke.
    private func weightPosition(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        return CGPoint(x: mid.x - dy / length * 10, y: mid.y + dx / length * 10)
    }

    private func accessibilitySummary(_ graph: SimpleGraph) -> String {
        let kind = graph.isDirected ? "Directed graph" : "Graph"
        return "\(kind) with \(graph.nodes.count) nodes and \(graph.edges.count) edges"
    }
}

/// Parsed graphs keyed by block text. Streaming re-renders a message on every
/// token, so parse and layout once per distinct block.
@MainActor
enum GraphLayoutCache {
    private static var graphs: [String: SimpleGraph?] = [:]

    static func graph(for content: String) -> SimpleGraph? {
        if let cached = graphs[content] { return cached }
        if graphs.count > 64 { graphs.removeAll() }
        let parsed = SimpleGraph.parse(content)
        graphs[content] = .some(parsed)
        return parsed
    }
}

struct ReasoningCard: View {
    let text: String
    var body: some View {
        MarkdownBody(text: text)
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: 24)
    }
}

struct WarningCard: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.footnote).padding(.top, 2)
            Text(text.markdown).font(.subheadline).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 24)
    }
}

// MARK: - Previews

#Preview("Tabs") { ContentView().environmentObject(AppState()) }
#Preview("Audit — Empty") { DegreeAuditView().environmentObject(AppState()) }
