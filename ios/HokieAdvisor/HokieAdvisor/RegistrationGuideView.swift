import SwiftUI

/// School-specific registration guidance from official sources. Agora only
/// explains and links; it never registers, drops, or withdraws a student.
struct RegistrationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.schoolTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var termKey: String?
    @State private var guide: RegistrationGuide?
    @State private var errorMessage: String?
    @State private var isLoading = false

    init(termKey: String?) {
        _termKey = State(initialValue: termKey)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    if let guide {
                        content(guide)
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else {
                        ProgressView("Loading official dates…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, AgoraSpacing.lg)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Registration",
                    subtitle: guide.map { "\($0.institution.name) · \($0.term.name)" } ?? "",
                    symbol: "calendar",
                    accent: theme.accent
                ) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .glassCircle(strokeOpacity: 0.08)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
        .task(id: termKey) { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await CourseCompanionAPI.registrationGuide(termKey: termKey)
            guide = result
            if termKey == nil { termKey = result.term.termKey }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Content

    @ViewBuilder
    private func content(_ guide: RegistrationGuide) -> some View {
        if guide.terms.count > 1 {
            HokieSegmentedControl(
                selection: Binding(get: { termKey ?? guide.term.termKey }, set: { termKey = $0 }),
                options: guide.terms.map { ($0.termKey, $0.name) }
            )
            .accessibilityLabel("Term")
        }

        notice

        if let comparison = guide.topics.first(where: { $0.topic == "drop_vs_withdraw" }) {
            comparisonCard(comparison, guide: guide)
        }

        keyDates(guide)

        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "How it works", icon: "list.bullet")
            VStack(spacing: 0) {
                let topics = guide.topics.filter { $0.topic != "drop_vs_withdraw" }
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                    GuideTopicRow(topic: topic, guide: guide)
                }
            }
            .glassSurface(cornerRadius: AgoraRadius.card)
        }

        Text("Official pages are the authority. If anything here differs from them, follow the official page.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var notice: some View {
        Label {
            Text("Agora can’t register, drop, or withdraw you. Make changes in HokieSPA or with the official forms linked below.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .padding(AgoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassInset(cornerRadius: AgoraRadius.inset)
    }

    private func comparisonCard(_ topic: GuideTopic, guide: RegistrationGuide) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: topic.title, icon: "arrow.left.arrow.right")
            VStack(spacing: 0) {
                comparisonRow(aspect: "", drop: "Drop", withdraw: "Withdraw (W)", header: true)
                ForEach(Array((topic.comparison ?? []).enumerated()), id: \.offset) { _, row in
                    Divider()
                    comparisonRow(aspect: row.aspect, drop: row.drop, withdraw: row.withdraw, header: false)
                }
            }
            .padding(.horizontal, AgoraSpacing.lg)
            .glassSurface(cornerRadius: AgoraRadius.card)
            if let id = topic.comparison?.first?.sourceId, let source = guide.source(id) {
                SourceFootnote(source: source)
            }
        }
    }

    @ViewBuilder
    private func comparisonRow(aspect: String, drop: String, withdraw: String, header: Bool) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    if !aspect.isEmpty {
                        Text(aspect).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(header ? drop : "Drop: \(drop)")
                    Text(header ? withdraw : "Withdraw: \(withdraw)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if !aspect.isEmpty {
                        Text(aspect).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: AgoraSpacing.md) {
                        Text(drop).frame(maxWidth: .infinity, alignment: .leading)
                        Text(withdraw).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(header ? .subheadline.weight(.semibold) : .subheadline)
        .foregroundStyle(header ? AgoraPalette.brandInk : .primary)
        .padding(.vertical, AgoraSpacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(header ? "Drop compared with withdraw" : "\(aspect). Drop: \(drop). Withdraw: \(withdraw).")
    }

    private func keyDates(_ guide: RegistrationGuide) -> some View {
        let groups = Dictionary(grouping: guide.deadlines, by: \.sourceId)
        let orderedSources = guide.sources.filter { groups[$0.id] != nil }
            .sorted { ($0.kind == "enrollment_dates" ? 0 : 1) < ($1.kind == "enrollment_dates" ? 0 : 1) }
        return VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "Official dates · \(guide.term.name)", icon: "calendar")
            ForEach(orderedSources) { source in
                VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                    VStack(spacing: 0) {
                        let rows = groups[source.id] ?? []
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, deadline in
                            if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                            DeadlineRow(deadline: deadline)
                        }
                    }
                    .glassSurface(cornerRadius: AgoraRadius.card)
                    SourceFootnote(source: source)
                }
            }
            if let calendar = guide.sources.first(where: { $0.kind == "academic_calendar" }), let url = calendar.link {
                Button {
                    openURL(url)
                } label: {
                    Text("Part-of-term, Winter, and Summer courses have different dates. Check the official calendar.")
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentText)
                .accessibilityHint("Opens the official academic calendar")
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: AgoraSpacing.md) {
            Text("Couldn’t load registration information")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .buttonStyle(.agoraSecondary)
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Rows

private struct DeadlineRow: View {
    let deadline: TermDeadline

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(deadline.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(deadline.isPast ? .secondary : AgoraPalette.brandInk)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AgoraSpacing.sm)
                if deadline.isPast {
                    Text("Passed").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Text(deadline.dateText)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(deadline.isPast ? .tertiary : .secondary)
            let tags = [deadline.audienceLabel, deadline.isTentative ? "Tentative" : nil].compactMap { $0 }
            if !tags.isEmpty {
                Text(tags.joined(separator: " · "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            if let detail = deadline.detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AgoraSpacing.lg)
        .padding(.vertical, AgoraSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct GuideTopicRow: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.openURL) private var openURL
    let topic: GuideTopic
    let guide: RegistrationGuide
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(topic.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AgoraPalette.brandInk)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: AgoraSpacing.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, AgoraSpacing.md)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                    ForEach(Array(topic.points.enumerated()), id: \.offset) { _, point in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(point.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            if let source = guide.source(point.sourceId) {
                                Text("Source: \(source.title)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                    ForEach(topic.links, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Button {
                                openURL(url)
                            } label: {
                                Label(link.title, systemImage: "arrow.up.right")
                                    .font(.subheadline.weight(.medium))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(theme.accentText)
                            .accessibilityHint("Opens the official page")
                        }
                    }
                }
                .padding(.bottom, AgoraSpacing.lg)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AgoraSpacing.lg)
    }
}

/// "Source: Title · checked Nov 9, 2026" with a link to the official page.
struct SourceFootnote: View {
    @Environment(\.schoolTheme) private var theme
    @Environment(\.openURL) private var openURL
    let source: OfficialSource

    var body: some View {
        Button {
            if let url = source.link { openURL(url) }
        } label: {
            (Text("Source: ") + Text(source.title).foregroundColor(theme.accentText)
                + Text(" · checked \(CalendarDay.text(source.checkedOn))"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.plain)
        .padding(.leading, 4)
        .accessibilityLabel("Source: \(source.title), checked \(CalendarDay.text(source.checkedOn))")
        .accessibilityHint("Opens the official page")
    }
}
