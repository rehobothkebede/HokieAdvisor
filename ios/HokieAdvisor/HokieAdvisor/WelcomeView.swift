import SwiftUI

// MARK: - Signed-Out Flow

/// Welcome → school → sign in. The chosen school only themes the sign-in
/// screen; once signed in, the account determines the school.
struct SignedOutFlow: View {
    @Binding var isAuthenticated: Bool
    @AppStorage("vtEmail") private var vtEmail = ""

    @State private var selectedSchool: SchoolTheme?

    init(isAuthenticated: Binding<Bool>) {
        _isAuthenticated = isAuthenticated
        // A student waiting on email confirmation goes straight back to sign-in.
        let pendingEmail = UserDefaults.standard.string(forKey: "pendingSignupEmail") ?? ""
        _selectedSchool = State(initialValue: pendingEmail.isEmpty ? nil : SchoolTheme.forAccount(email: pendingEmail))
    }

    var body: some View {
        ZStack {
            if let school = selectedSchool {
                LoginView(isAuthenticated: $isAuthenticated) {
                    withAnimation(.easeInOut(duration: 0.3)) { selectedSchool = nil }
                }
                .environment(\.schoolTheme, school)
                .tint(school.accent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                WelcomeView(returningSchool: vtEmail.isEmpty ? nil : SchoolTheme.forAccount(email: vtEmail)) { school in
                    withAnimation(.easeInOut(duration: 0.3)) { selectedSchool = school }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
    }
}

// MARK: - Welcome

struct WelcomeView: View {
    /// The school of the account last used on this device, if any.
    let returningSchool: SchoolTheme?
    let onSelectSchool: (SchoolTheme) -> Void

    @State private var showSchoolPicker = false
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 56
    @ScaledMetric(relativeTo: .title) private var taglineSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: AgoraSpacing.xxl)

            VStack(spacing: AgoraSpacing.lg) {
                AgoraWordmark(size: min(wordmarkSize, 84))

                Capsule()
                    .fill(AgoraPalette.copper)
                    .frame(width: 36, height: 2)
                    .accessibilityHidden(true)

                Text(AgoraBrand.tagline)
                    .font(.agoraDisplay(min(taglineSize, 44), weight: .regular))
                    .foregroundStyle(AgoraPalette.brandInk)
                    .multilineTextAlignment(.center)

                Text(AgoraBrand.supportingLine)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AgoraSpacing.xl)

            Spacer(minLength: AgoraSpacing.xxl)

            VStack(spacing: AgoraSpacing.md) {
                if let returningSchool {
                    Button("Continue with \(returningSchool.name)") {
                        onSelectSchool(returningSchool)
                    }
                    .buttonStyle(.agoraPrimary)

                    Button("Choose a different school") {
                        showSchoolPicker = true
                    }
                    .buttonStyle(.agoraSecondary)
                } else {
                    Button {
                        showSchoolPicker = true
                    } label: {
                        Label("Find your school", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.agoraPrimary)
                }
            }
            .padding(.horizontal, AgoraSpacing.xl)
            .padding(.bottom, AgoraSpacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HokieAppBackground().ignoresSafeArea())
        .sheet(isPresented: $showSchoolPicker) {
            SchoolPickerSheet { school in
                showSchoolPicker = false
                onSelectSchool(school)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - School Picker

/// Lists only schools in `SchoolTheme.supported`; nothing here is a placeholder.
struct SchoolPickerSheet: View {
    let onSelect: (SchoolTheme) -> Void

    @State private var query = ""

    private var matches: [SchoolTheme] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return SchoolTheme.supported }
        return SchoolTheme.supported.filter { school in
            school.name.localizedCaseInsensitiveContains(trimmed) ||
                school.emailDomains.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.lg) {
            Text("Find your school")
                .font(.agoraDisplay(26))
                .foregroundStyle(AgoraPalette.brandInk)

            HStack(spacing: AgoraSpacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("School name or email domain", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .agoraField()

            VStack(spacing: AgoraSpacing.sm) {
                ForEach(matches, id: \.name) { school in
                    Button { onSelect(school) } label: {
                        HStack(spacing: AgoraSpacing.md) {
                            Image(systemName: "building.columns.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AgoraPalette.brandInk)
                                .frame(width: 40, height: 40)
                                .background(AgoraPalette.surfaceInset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(school.name).font(.body.weight(.semibold))
                                Text(school.emailDomains.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.primary)
                        .padding(AgoraSpacing.md)
                        .glassSurface(cornerRadius: AgoraRadius.inset)
                    }
                    .buttonStyle(.plain)
                }

                if matches.isEmpty {
                    Text("No supported school matches \u{201C}\(query)\u{201D}.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AgoraSpacing.sm)
                }
            }

            Text("Agora is available to \(ListFormatter.localizedString(byJoining: SchoolTheme.supported.map(\.name))) students today.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(AgoraSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AgoraPalette.background.ignoresSafeArea())
    }
}

#Preview {
    SignedOutFlow(isAuthenticated: .constant(false))
        .environmentObject(AppState())
}
