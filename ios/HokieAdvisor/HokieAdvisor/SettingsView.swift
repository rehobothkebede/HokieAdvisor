import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("graduationYear") private var graduationYear = ""
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("vtEmail") private var vtEmail = ""
    @AppStorage("vtPID") private var vtPID = ""
    @AppStorage("onboardingComplete") private var onboardingComplete = true
    @AppStorage("authSessionActive") private var authSessionActive = false
    @AppStorage("pendingSignupEmail") private var pendingSignupEmail = ""

    @State private var showClearDataAlert = false
    @State private var showResetAlert = false
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var showTranscriptImport = false
    @State private var showMemoryEditor = false
    @State private var showHelp = false
    @State private var resetError = ""
    @State private var scrollOffset: CGFloat = 0
    @State private var profileSyncTask: Task<Void, Never>? = nil
    @State private var suppressProfileSync = false

    private var compactTitleProgress: CGFloat {
        min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                        .padding(.top, 12)
                    profileCard
                    settingsGroup(title: "School & Program") { academicSection }
                    settingsGroup(title: "Transcript") { transcriptSection }
                    settingsGroup(title: "Chat Memory") { chatMemorySection }
                    settingsGroup(title: "Appearance") { appearanceSection }
                    settingsGroup(title: "Help & About") { aboutSection }
                    settingsGroup(title: "Account") { dangerSection }

                    Text("\(AgoraBrand.name) · v1.0.0\n\(AgoraBrand.tagline)")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 4)

                    Spacer(minLength: HokieChrome.contentBottomInset)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                guard abs(offset - scrollOffset) > 0.5 else { return }
                scrollOffset = offset
            }
            .scrollDismissesKeyboard(.interactively)
            .hokieScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
            .overlay(alignment: .top) { compactTitleOverlay }
        }
        .swipeDownToDismissKeyboard()
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
        }
        .sheet(isPresented: $showMemoryEditor) {
            ChatMemoryEditorView()
                .environmentObject(chatHistory)
        }
        .sheet(isPresented: $showTerms) {
            LegalSheet(title: "Terms of Service", content: termsBody)
        }
        .sheet(isPresented: $showPrivacy) {
            LegalSheet(title: "Privacy Policy", content: privacyBody)
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .alert("Clear Local Data", isPresented: $showClearDataAlert) {
            Button("Clear Everything", role: .destructive) {
                clearLocalAccountData(deleteLocalChatCache: true)
                Task { await SupabaseAuthService.shared.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your transcript, academic data, saved chat history, and chat memories will be removed from this device. This cannot be undone.")
        }
        .alert("Reset Account", isPresented: $showResetAlert) {
            Button("Reset & Restart", role: .destructive) {
                resetAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will erase all your data and return you to the setup screen.")
        }
        .alert("Could Not Delete Remote Account", isPresented: Binding(
            get: { !resetError.isEmpty },
            set: { if !$0 { resetError = "" } }
        )) {
            Button("OK", role: .cancel) { resetError = "" }
        } message: {
            Text(resetError)
        }
        .onChange(of: studentName) { _, _ in scheduleProfileSync() }
        .onChange(of: graduationYear) { _, _ in scheduleProfileSync() }
        .onChange(of: appearanceMode) { _, _ in scheduleProfileSync() }
        .onChange(of: appState.major) { _, _ in scheduleProfileSync() }
        .onDisappear {
            flushProfileSync()
        }
        #if DEBUG
        .onAppear(perform: openVisualQASheetIfRequested)
        #endif
    }

    #if DEBUG
    /// `-HokieOpenProfileSheet help|memories|transcript|terms|privacy` opens that sheet.
    private func openVisualQASheetIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HokieOpenProfileSheet"),
              arguments.indices.contains(index + 1) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            switch arguments[index + 1] {
            case "help": showHelp = true
            case "memories": showMemoryEditor = true
            case "transcript": showTranscriptImport = true
            case "terms": showTerms = true
            case "privacy": showPrivacy = true
            default: break
            }
        }
    }
    #endif

    // MARK: - Profile Card

    private var compactTitleOverlay: some View {
        HokieCompactPill(
            title: "Profile",
            symbol: "person.crop.circle.fill",
            accent: theme.accent,
            progress: compactTitleProgress
        )
        .padding(.top, 8)
    }

    private var profileHeader: some View {
        HokiePageHeader(
            title: "Profile",
            eyebrow: theme.isSchool ? theme.name : AgoraBrand.name,
            subtitle: "Your school, records, and account.",
            symbol: "person.crop.circle.fill",
            accent: theme.accent,
            stat: profileHeaderStat
        )
    }

    private var profileHeaderStat: HokieHeaderStat {
        if !graduationYear.isEmpty {
            return HokieHeaderStat(value: "'\(String(graduationYear.suffix(2)))", label: "grad year", icon: "graduationcap.fill")
        }
        if !vtPID.isEmpty {
            return HokieHeaderStat(value: vtPID.uppercased(), label: theme.studentIDLabel ?? "ID", icon: "person.text.rectangle.fill")
        }
        return HokieHeaderStat(value: "New", label: "profile", icon: "person.fill")
    }

    private var profileCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent).frame(width: 76, height: 76)
                if initials.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.title2)
                        .foregroundStyle(theme.onAccent)
                } else {
                    Text(initials).font(.title2.weight(.semibold)).foregroundStyle(theme.onAccent)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                TextField("Your name", text: $studentName)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(AgoraPalette.brandInk)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Name")

                if !vtEmail.isEmpty {
                    Text(vtEmail)
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if let gpa = appState.calculatedGPA {
                    Text(String(format: "%.2f GPA", gpa))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(gpaColor(gpa))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AgoraSpacing.xl)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private func resetAccount() {
        Task {
            do {
                try await SupabaseAuthService.shared.deleteAccount()
                clearLocalAccountData(deleteLocalChatCache: true)
            } catch {
                resetError = error.localizedDescription
            }
        }
    }

    private func signOut() {
        profileSyncTask?.cancel()
        Task { await SupabaseAuthService.shared.signOut() }
        clearLocalAccountData(deleteLocalChatCache: false)
    }

    private func clearLocalAccountData(deleteLocalChatCache: Bool) {
        suppressProfileSync = true
        profileSyncTask?.cancel()
        appState.transcriptCourses = []
        appState.inProgressCourses = []
        appState.plannedCourses = []
        appState.transcriptNotes = []
        appState.inProgressGrades = [:]
        appState.hasTranscript = false
        appState.passingAllClasses = nil
        appState.strugglingCourses = []
        appState.major = ""
        appState.latestDegreeAudit = nil
        appState.latestDarsAudit = nil
        if deleteLocalChatCache {
            chatHistory.deleteAll()
        } else {
            chatHistory.clearLoadedUser()
        }
        vtEmail = ""
        vtPID = ""
        studentName = ""
        graduationYear = ""
        pendingSignupEmail = ""
        authSessionActive = false
        onboardingComplete = false
    }

    private func scheduleProfileSync() {
        guard !suppressProfileSync,
              authSessionActive,
              onboardingComplete else { return }

        let snapshot = currentProfileSnapshot
        profileSyncTask?.cancel()
        profileSyncTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await syncProfile(snapshot)
        }
    }

    private func flushProfileSync() {
        guard !suppressProfileSync,
              authSessionActive,
              onboardingComplete else { return }

        let snapshot = currentProfileSnapshot
        profileSyncTask?.cancel()
        profileSyncTask = nil
        Task { await syncProfile(snapshot) }
    }

    private var currentProfileSnapshot: SupabaseProfileSnapshot {
        SupabaseProfileSnapshot(
            fullName: studentName.trimmingCharacters(in: .whitespacesAndNewlines),
            vtPID: vtPID.trimmingCharacters(in: .whitespacesAndNewlines),
            vtEmail: vtEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            major: appState.major.trimmingCharacters(in: .whitespacesAndNewlines),
            graduationYear: graduationYear.trimmingCharacters(in: .whitespacesAndNewlines),
            appearanceMode: appearanceMode
        )
    }

    private func syncProfile(_ snapshot: SupabaseProfileSnapshot) async {
        guard let session = try? await SupabaseAuthService.shared.validatedCurrentSession(),
              let userID = session.user?.id else { return }

        try? await SupabaseUserDataService.shared.upsertProfile(
            snapshot,
            userID: userID,
            accessToken: session.accessToken
        )
    }

    private var initials: String {
        let parts = studentName.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        row(icon: "moon.stars.fill", iconColor: theme.accent, label: "Theme") {
            HokieSegmentedControl(
                selection: $appearanceMode,
                options: [
                    (value: "system", title: "System"),
                    (value: "light", title: "Light"),
                    (value: "dark", title: "Dark"),
                ]
            )
            .frame(width: 188)
        }
    }

    // MARK: - Academic

    private var academicSection: some View {
        VStack(spacing: 0) {
            row(icon: "building.columns.fill", iconColor: theme.accent, label: "School") {
                valueText(theme.isSchool ? theme.name : "Not set")
            }
            divider
            row(icon: "graduationcap.fill", iconColor: theme.accent, label: "Program") {
                valueText(appState.major.isEmpty ? "Not set" : appState.major)
            }
            if !vtPID.isEmpty {
                divider
                row(icon: "person.text.rectangle.fill", iconColor: theme.accent, label: theme.studentIDLabel ?? "Student ID") {
                    valueText(vtPID)
                }
            }
            divider
            row(icon: "calendar", iconColor: theme.accent, label: "Grad Year") {
                TextField("Not set", text: $graduationYear)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Graduation year")
            }
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline).foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        Button { showTranscriptImport = true } label: {
            if appState.hasTranscript {
                row(icon: "doc.text.fill", iconColor: theme.accent, label: "Transcript") {
                    HStack(spacing: 8) {
                        valueText("\(appState.transcriptCourses.count) courses · \(Int(appState.totalCredits)) cr")
                        chevron
                    }
                }
            } else {
                row(icon: "arrow.up.doc.fill", iconColor: theme.accent, label: "Import Transcript") {
                    chevron
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(appState.hasTranscript ? "Review courses or re-upload" : "")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
    }

    // MARK: - Chat Memory

    private var chatMemorySection: some View {
        VStack(spacing: 0) {
            row(icon: "bubble.left.and.bubble.right.fill", iconColor: theme.accent, label: "Saved Chats") {
                Text("\(chatHistory.sessions.count)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            divider
            Button { showMemoryEditor = true } label: {
                row(icon: "sparkles", iconColor: theme.accent, label: "Saved Memories") {
                    HStack(spacing: 8) {
                        Text("\(chatHistory.memories.count)")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.bold()).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if appState.hasTranscript {
                divider
                row(icon: "person.text.rectangle.fill", iconColor: theme.accent, label: "Transcript Context") {
                    Text("\(appState.transcriptCourses.count) courses")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if !chatHistory.recentMemoryHighlights.isEmpty {
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Text("Memory Preview")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(chatHistory.recentMemoryHighlights) { memory in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(theme.accent.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(memory.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 0) {
            Button { showHelp = true } label: {
                row(icon: "questionmark.circle.fill", iconColor: theme.accent, label: "Help & FAQ") {
                    chevron
                }
            }
            .buttonStyle(.plain)
            divider
            Button { showTerms = true } label: {
                row(icon: "doc.text", iconColor: .gray, label: "Terms of Service") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            divider
            Button { showPrivacy = true } label: {
                row(icon: "hand.raised.fill", iconColor: .gray, label: "Privacy Policy") {
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            divider
            row(icon: "info.circle.fill", iconColor: .gray, label: "Version") {
                Text("1.0.0 (1)").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Danger

    private var dangerSection: some View {
        VStack(spacing: 0) {
            Button { signOut() } label: {
                row(icon: "rectangle.portrait.and.arrow.right", iconColor: .gray, label: "Sign Out") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            divider
            Button { showClearDataAlert = true } label: {
                row(icon: "trash.fill", iconColor: .red, label: "Clear Local Data") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
            divider
            Button { showResetAlert = true } label: {
                row(icon: "arrow.counterclockwise", iconColor: .orange, label: "Reset Account & Restart") {
                    EmptyView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Divider().padding(.leading, 58)
    }

    private func settingsGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .accessibilityAddTraits(.isHeader)
                }
                .padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .glassSurface(cornerRadius: AgoraRadius.card)
        }
    }

    @ViewBuilder
    private func row<Trailing: View>(icon: String, iconColor: Color, label: String,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            HokieIconTile(symbol: icon, color: iconColor, size: 32)

            // Label and value stack at accessibility sizes so neither is squeezed.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Text(label).font(.body).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                trailing()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    // MARK: - Legal Content

    private var termsBody: String {
"""
**Terms of Service**

*Last updated: May 2026*

**Acceptance**
By using Agora, you agree to these terms. If you do not agree, please do not use the app.

**Purpose**
Agora is a student academic planning tool designed to assist Virginia Tech students with course planning and advising. It is not a replacement for official advising from your department or the university.

**AI Recommendations**
Course recommendations and advisor responses are AI-generated. Always verify recommendations against your official degree audit and consult your academic advisor before making enrollment decisions.

**Your Data**
Your transcript, audit uploads, chat messages, and academic context may be sent to Agora backend services, Supabase, and OpenAI-powered services to provide parsing, advising, and account features. Do not upload information you are not comfortable processing through those services.

**Disclaimer**
Agora is an independent student project and is not officially affiliated with or endorsed by Virginia Tech University.

**Changes**
We may update these terms at any time. Continued use of the app constitutes acceptance of any changes.
"""
    }

    private var privacyBody: String {
"""
**Privacy Policy**

*Last updated: May 2026*

**What We Collect**
- Transcript and audit files you choose to upload, plus parsed academic course data
- Chat messages, saved chat history, and saved chat memories
- Your name, major, graduation year, VT email, and account/profile details

**How We Use It**
Your data is used to parse academic records, generate personalized course plans, provide AI advisor responses, support account features, and improve your in-app academic workflow.

**Data Sharing**
We do not sell your personal data. Agora transmits relevant data to backend services, Supabase, and OpenAI-powered services when needed for authentication, storage, transcript parsing, audit extraction, chat, and advising features.

**Data Deletion**
You can delete local app data via Profile → Clear Local Data. If you created a Supabase-backed account, Profile → Reset Account & Restart also requests deletion of the remote account.

**Security**
Data stored on your device is protected by iOS app sandboxing and your device passcode/Face ID. Remote processing and storage depend on the configured backend, Supabase project, and OpenAI service settings.

**Contact**
Questions about this policy? Reach out through the Virginia Tech CS department.
"""
    }
}

// MARK: - Chat Memory Editor

struct ChatMemoryEditorView: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newMemory = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    addMemoryCard
                    savedMemorySection
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Chat Memory",
                    subtitle: "\(chatHistory.memories.count) saved note\(chatHistory.memories.count == 1 ? "" : "s")",
                    symbol: "brain.head.profile",
                    accent: theme.accent
                ) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, height: 44)
                            .glassCircle(strokeOpacity: 0.08)
                    }
                    .accessibilityLabel("Close")
                    .buttonStyle(.plain)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
        .swipeDownToDismissKeyboard()
    }

    private var addMemoryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HokieIconTile(symbol: "plus.message.fill", color: theme.accent, size: 38)

                TextField("Add something to remember...", text: $newMemory, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)

                Button {
                    addMemory()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(canAddMemory ? theme.onAccent : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(canAddMemory ? theme.accent : Color.primary.opacity(0.08), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canAddMemory)
                .accessibilityLabel("Add memory")
            }

            Text("Preferred name, tutoring style, weak topics, course goals, or scheduling preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private var savedMemorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .padding(.leading, 4)
                Spacer()
                if !chatHistory.memories.isEmpty {
                    Button("Delete all", role: .destructive) { confirmDeleteAll = true }
                        .font(.caption.weight(.bold))
                        .confirmationDialog(
                            "Delete all \(chatHistory.memories.count) memories?",
                            isPresented: $confirmDeleteAll,
                            titleVisibility: .visible
                        ) {
                            Button("Delete all memories", role: .destructive) { chatHistory.deleteAllMemories() }
                        } message: {
                            Text("The advisor will stop using them in future chats.")
                        }
                }
            }

            if chatHistory.memories.isEmpty {
                HStack(spacing: 12) {
                    HokieIconTile(symbol: "brain.head.profile", color: theme.accent, size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No saved memories yet")
                            .font(.subheadline.weight(.semibold))
                        Text("New notes you add here will shape future advisor responses.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .glassSurface(cornerRadius: 22)
            } else {
                VStack(spacing: 10) {
                    ForEach(chatHistory.memories) { memory in
                        EditableMemoryRow(memory: memory)
                            .environmentObject(chatHistory)
                    }
                }
            }
        }
    }

    private var canAddMemory: Bool {
        !newMemory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addMemory() {
        guard canAddMemory else { return }
        chatHistory.addMemory(newMemory)
        newMemory = ""
    }
}

struct EditableMemoryRow: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.schoolTheme) private var theme
    let memory: ChatMemory
    @State private var draft: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HokieIconTile(symbol: "sparkles", color: theme.accent, size: 34)

            TextField("Memory", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .font(.body)
                .textInputAutocapitalization(.sentences)
                .onAppear { draft = memory.content }
                .onSubmit {
                    chatHistory.updateMemory(memory, content: draft)
                }
                .onChange(of: draft) { _, value in
                    chatHistory.updateMemory(memory, content: value)
                }

            Button {
                chatHistory.deleteMemory(memory)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(width: 44, height: 44)
                    .glassCircle(strokeOpacity: 0.08)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete memory")
        }
        .padding(14)
        .glassSurface(cornerRadius: 20)
    }
}

// MARK: - Legal Sheet

struct LegalSheet: View {
    @Environment(\.schoolTheme) private var theme
    let title: String
    let content: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content.markdown)
                    .font(.body).lineSpacing(5)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: title,
                    subtitle: "\(AgoraBrand.name) policies",
                    symbol: "doc.text.fill",
                    accent: theme.accent
                ) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 44, height: 44)
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(ChatHistoryStore())
}
