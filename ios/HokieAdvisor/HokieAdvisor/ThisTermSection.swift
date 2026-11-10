import SwiftUI

/// Home's "This term" section: the student's chosen term, registration
/// guidance, and (from stage 2) their enrolled courses.
struct ThisTermSection: View {
    @EnvironmentObject private var store: CourseCompanionStore
    @Environment(\.schoolTheme) private var theme
    @State private var showRegistration = false

    var body: some View {
        Group {
            if !store.isAvailable {
                EmptyView()
            } else {
                stateContent
            }
        }
        .task {
            await store.load()
            #if DEBUG
            // `-AgoraOpenRegistration` opens the guide for visual QA.
            if ProcessInfo.processInfo.arguments.contains("-AgoraOpenRegistration") { showRegistration = true }
            #endif
        }
        .sheet(isPresented: $showRegistration) {
            RegistrationGuideView(termKey: store.overview?.registration?.termKey ?? store.selectedTerm?.termKey)
                .environment(\.schoolTheme, theme)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        Group {
            switch store.state {
            case .idle, .loading where store.overview == nil:
                placeholder
            case .unsupported:
                EmptyView() // No dead ends for schools Agora doesn't cover yet.
            case .failed(let message) where store.overview == nil:
                failure(message)
            default:
                content
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            header
            registrationRow
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionLabel(title: "This term", icon: "calendar")
            Spacer(minLength: AgoraSpacing.sm)
            if store.terms.count > 1 {
                Menu {
                    Picker("Term", selection: Binding(
                        get: { store.selectedTerm?.termKey ?? "" },
                        set: { store.selectedTermKey = $0 }
                    )) {
                        ForEach(store.terms) { term in
                            Text(term.name).tag(term.termKey)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.selectedTerm?.name ?? "Choose term")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.accentText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Term: \(store.selectedTerm?.name ?? "not chosen")")
                .accessibilityHint("Changes the term shown in this section")
            } else if let term = store.selectedTerm {
                Text(term.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var registrationRow: some View {
        Button { showRegistration = true } label: {
            HStack(spacing: AgoraSpacing.md) {
                Image(systemName: "calendar.badge.clock")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(registrationTitle)
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(registrationDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AgoraSpacing.lg)
            .padding(.vertical, AgoraSpacing.md)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens registration dates and how add, drop, and withdrawal work")
    }

    private var registrationTitle: String {
        if let registration = store.overview?.registration {
            return "Registration · \(registration.termName)"
        }
        return "Registration guide"
    }

    private var registrationDetail: String {
        guard let deadline = store.overview?.registration?.deadline else {
            return "How Course Request, Add/Drop, and withdrawal work."
        }
        let verb = deadline.state == "open" ? "Open now" : deadline.dateText
        return "\(deadline.label) · \(verb)"
    }

    // MARK: - States

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "This term", icon: "calendar")
            RoundedRectangle(cornerRadius: AgoraRadius.inset + 2, style: .continuous)
                .fill(AgoraPalette.surface)
                .frame(height: 64)
                .overlay(ProgressView())
                .accessibilityLabel("Loading this term")
        }
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.md) {
            SectionLabel(title: "This term", icon: "calendar")
            HStack(spacing: AgoraSpacing.md) {
                Text("Couldn’t load this term. \(message)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button("Retry") { Task { await store.load(force: true) } }
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, AgoraSpacing.lg)
            .glassSurface(cornerRadius: AgoraRadius.inset + 2)
        }
    }
}
