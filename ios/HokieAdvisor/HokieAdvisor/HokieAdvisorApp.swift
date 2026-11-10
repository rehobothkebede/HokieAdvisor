import SwiftUI
import UIKit

// UIViewRepresentable that sets overrideUserInterfaceStyle on its window.
// updateUIView is called after the view is attached to a window, so we
// defer one run-loop tick with async to guarantee window != nil.
struct WindowAppearanceSetter: UIViewRepresentable {
    let mode: String

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isHidden = true
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let style: UIUserInterfaceStyle = switch mode {
            case "dark":  .dark
            case "light": .light
            default:      .unspecified
        }
        DispatchQueue.main.async {
            uiView.window?.overrideUserInterfaceStyle = style
        }
    }
}

@main
struct HokieAdvisorApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var chatHistory = ChatHistoryStore()
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("authSessionActive") private var authSessionActive = false
    @AppStorage("studentName") private var studentName = ""
    @AppStorage("vtEmail") private var vtEmail = ""
    @AppStorage("vtPID") private var vtPID = ""
    @AppStorage("graduationYear") private var graduationYear = ""
    @State private var isAuthenticated = false
    @State private var didCheckSession = false
    @State private var configuredUserID: UUID?
    @State private var restoredSnapshotUserID: UUID?
    /// Set only by an explicit sign-in; never persisted, so relaunching,
    /// restoring a session, refreshing a token, or foregrounding can't show it.
    @State private var signInWelcome: SchoolWelcome?

    init() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundColor = .clear
        navigationAppearance.backgroundEffect = nil
        navigationAppearance.shadowColor = .clear

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = navigationAppearance
        }
        UINavigationBar.appearance().isTranslucent = true
        UINavigationBar.appearance().backgroundColor = .clear
        UINavigationBar.appearance().barTintColor = .clear
        UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
        UINavigationBar.appearance().shadowImage = UIImage()

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundColor = .clear
        tabAppearance.backgroundEffect = nil
        tabAppearance.shadowColor = .clear

        UITabBar.appearance().standardAppearance = tabAppearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        }
        UITabBar.appearance().isTranslucent = true
        UITabBar.appearance().backgroundColor = .clear
        UITabBar.appearance().barTintColor = .clear
        UITabBar.appearance().shadowImage = UIImage()
        UITabBar.appearance().backgroundImage = UIImage()
    }

    /// Signed in: the account's school. Signed out: neutral Agora; the welcome
    /// flow applies the chosen school to sign-in itself.
    private var schoolTheme: SchoolTheme {
        isAuthenticated && authSessionActive ? SchoolTheme.forAccount(email: vtEmail) : .agora
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !didCheckSession {
                    LaunchLoadingView()
                } else if !isAuthenticated || !authSessionActive {
                    SignedOutFlow(isAuthenticated: $isAuthenticated, onSignedIn: presentSignInWelcome)
                        .environmentObject(appState)
                        .environmentObject(chatHistory)
                } else if let welcome = signInWelcome {
                    // Continue only clears the welcome; the checks below still
                    // decide between onboarding and Home.
                    SchoolWelcomeView(welcome: welcome) { signInWelcome = nil }
                } else if !onboardingComplete {
                    OnboardingView()
                        .environmentObject(appState)
                        .environmentObject(chatHistory)
                } else {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(chatHistory)
                }
            }
            .environment(\.schoolTheme, schoolTheme)
            .tint(schoolTheme.accent)
            .background(WindowAppearanceSetter(mode: signInWelcome == nil ? appearanceMode : "dark"))
            .preferredColorScheme(appPreferredColorScheme)
            .animation(.easeInOut(duration: 0.35), value: onboardingComplete)
            .animation(.easeInOut(duration: 0.35), value: isAuthenticated)
            .animation(.easeInOut(duration: 0.35), value: authSessionActive)
            .animation(.easeInOut(duration: 0.35), value: signInWelcome)
            .task { await restoreSession() }
            .onChange(of: authSessionActive) { _, active in
                Task { await handleAuthSessionChange(active) }
            }
            .onOpenURL { url in
                Task {
                    if (try? await SupabaseAuthService.shared.handleAuthRedirect(url)) == true {
                        // Opening the email confirmation link is an explicit sign-in.
                        if let email = (try? await SupabaseAuthService.shared.currentSession())?.user?.email {
                            presentSignInWelcome(accountEmail: email)
                        }
                        await configureAuthenticatedUserData()
                        isAuthenticated = true
                        authSessionActive = true
                    }
                }
            }
        }
    }

    /// Greets the school of the account that just signed in, resolved from the
    /// session's email, never from the school picked while signed out.
    @MainActor
    private func presentSignInWelcome(accountEmail: String) {
        signInWelcome = SchoolTheme.forAccount(email: accountEmail).welcome
    }

    private var appPreferredColorScheme: ColorScheme? {
        // The welcome is designed light-on-dark; this also keeps the status bar legible.
        if signInWelcome != nil { return .dark }
        switch appearanceMode {
        case "dark":
            return .dark
        case "light":
            return .light
        default:
            return nil
        }
    }

    @MainActor
    private func restoreSession() async {
        guard !didCheckSession else { return }
        #if DEBUG
        if isVisualQAMode {
            seedVisualQAData()
            isAuthenticated = true
            authSessionActive = true
            // `-HokieVisualQAOnboarding` shows onboarding for the sample student.
            onboardingComplete = !ProcessInfo.processInfo.arguments.contains("-HokieVisualQAOnboarding")
            // `-HokieVisualQASignIn` stands in for LoginView's success callback,
            // since visual QA must not sign in to a real account.
            if ProcessInfo.processInfo.arguments.contains("-HokieVisualQASignIn") {
                presentSignInWelcome(accountEmail: vtEmail)
                // `-HokieVisualQAContinue` then performs Continue's action after
                // a pause, since the simulator tools here can't tap.
                if ProcessInfo.processInfo.arguments.contains("-HokieVisualQAContinue") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { signInWelcome = nil }
                }
            }
            didCheckSession = true
            return
        }
        #endif

        if SupabaseConfig.isConfigured,
           let session = try? await SupabaseAuthService.shared.validatedCurrentSession() {
            await configureAuthenticatedUserData(session: session)
            isAuthenticated = true
            authSessionActive = true
        } else {
            authSessionActive = false
            chatHistory.clearLoadedUser()
            configuredUserID = nil
            restoredSnapshotUserID = nil
        }
        didCheckSession = true
    }

    @MainActor
    private func handleAuthSessionChange(_ active: Bool) async {
        if active {
            await configureAuthenticatedUserData()
        } else {
            signInWelcome = nil
            chatHistory.clearLoadedUser()
            configuredUserID = nil
            restoredSnapshotUserID = nil
        }
    }

    @MainActor
    private func configureAuthenticatedUserData() async {
        guard let session = try? await SupabaseAuthService.shared.validatedCurrentSession() else {
            chatHistory.clearLoadedUser()
            configuredUserID = nil
            restoredSnapshotUserID = nil
            return
        }
        await configureAuthenticatedUserData(session: session)
    }

    @MainActor
    private func configureAuthenticatedUserData(session: SupabaseSession) async {
        guard let userID = session.user?.id else { return }

        if configuredUserID != userID {
            await chatHistory.configure(userID: userID, accessToken: session.accessToken)
            configuredUserID = userID
        }

        guard restoredSnapshotUserID != userID else { return }
        if let snapshot = try? await SupabaseUserDataService.shared.fetchStudentSnapshot(
            userID: userID,
            accessToken: session.accessToken
        ) {
            apply(snapshot)
            if snapshot.didFetchAllStudentData {
                restoredSnapshotUserID = userID
            }
        }
    }

    @MainActor
    private func apply(_ snapshot: SupabaseStudentSnapshot) {
        if let profile = snapshot.profile {
            studentName = profile.fullName ?? ""
            vtEmail = profile.vtEmail ?? ""
            vtPID = profile.vtPID ?? ""
            graduationYear = profile.graduationYear ?? ""
            if let major = profile.major, !major.isEmpty {
                appState.major = major
            } else {
                appState.major = "Computer Science"
            }
            if let mode = profile.appearanceMode,
               ["system", "light", "dark"].contains(mode) {
                appearanceMode = mode
            }
        }

        if snapshot.didFetchTranscript {
            if let transcript = snapshot.transcript {
                appState.transcriptCourses = transcript.courses
                appState.inProgressCourses = transcript.inProgressCourses
                appState.plannedCourses = transcript.plannedCourses
                appState.transcriptNotes = transcript.notes
                appState.inProgressGrades = [:]
                appState.hasTranscript = !transcript.courses.isEmpty ||
                    !transcript.inProgressCourses.isEmpty ||
                    !transcript.plannedCourses.isEmpty
            } else {
                appState.transcriptCourses = []
                appState.inProgressCourses = []
                appState.plannedCourses = []
                appState.transcriptNotes = []
                appState.inProgressGrades = [:]
                appState.hasTranscript = false
            }
        }

        if snapshot.didFetchDegreeAudit {
            appState.latestDegreeAudit = snapshot.degreeAudit
        }
        if snapshot.didFetchDarsAudit {
            appState.latestDarsAudit = snapshot.darsAudit
        }
    }

    #if DEBUG
    private var isVisualQAMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-HokieVisualQA")
    }

    @MainActor
    private func seedVisualQAData() {
        let defaults = UserDefaults.standard
        defaults.set("Rehoboth Kebede", forKey: "studentName")
        defaults.set("rehobothk@vt.edu", forKey: "vtEmail")
        defaults.set("rehobothk", forKey: "vtPID")
        defaults.set("2029", forKey: "graduationYear")

        appState.major = "Computer Science"

        // `-HokieVisualQAEmpty` keeps the signed-in student but skips academic data,
        // for checking empty states.
        if ProcessInfo.processInfo.arguments.contains("-HokieVisualQAEmpty") {
            appState.hasTranscript = false
            return
        }

        appState.hasTranscript = true
        appState.transcriptCourses = [
            TranscriptCourse(code: "CS 1114", name: "Introduction to Software Design", credits: 3, grade: "A", semester: "Fall 2025"),
            TranscriptCourse(code: "MATH 1225", name: "Calculus of a Single Variable", credits: 4, grade: "A-", semester: "Fall 2025"),
            TranscriptCourse(code: "ENGL 1105", name: "First-Year Writing", credits: 3, grade: "B+", semester: "Fall 2025"),
            TranscriptCourse(code: "CS 2114", name: "Software Design and Data Structures", credits: 3, grade: "A", semester: "Spring 2026"),
            TranscriptCourse(code: "MATH 1226", name: "Calculus of a Single Variable", credits: 4, grade: "B+", semester: "Spring 2026"),
            TranscriptCourse(code: "COMM 1016", name: "Communication Skills", credits: 3, grade: "A-", semester: "Spring 2026"),
        ]
        appState.inProgressCourses = [
            InProgressCourse(code: "CS 2505", name: "Introduction to Computer Organization", credits: 3, semester: "Summer 2026"),
            InProgressCourse(code: "MATH 2114", name: "Introduction to Linear Algebra", credits: 3, semester: "Summer 2026"),
        ]
        appState.plannedCourses = [
            InProgressCourse(code: "CS 3114", name: "Data Structures and Algorithms", credits: 3, semester: "Fall 2026"),
            InProgressCourse(code: "STAT 4705", name: "Probability and Statistics", credits: 3, semester: "Fall 2026"),
        ]
        appState.inProgressGrades = [
            "CS 2505": "A-",
            "MATH 2114": "B+",
        ]
        appState.transcriptNotes = [
            "Visual QA sample data. Not a real transcript.",
            "DARS import has not been attached in this simulator profile.",
        ]
        appState.passingAllClasses = true
        appState.strugglingCourses = []

        let sessionID = UUID(uuidString: "4F92F806-74C8-4F0D-A19A-629E2D6B39A6") ?? UUID()
        chatHistory.upsert(
            ChatSession(
                id: sessionID,
                title: "BFS on a graph",
                date: Date(),
                messages: [
                    ChatMessage(role: "user", content: "Show me BFS on a graph with a visual"),
                    ChatMessage(role: "assistant", content: "Start at the source, visit each neighbor, then move outward one layer at a time. Think of it as exploring campus from your dorm by walking every closest path before taking longer ones.")
                ]
            )
        )
        chatHistory.addMemory("Prefers visual explanations for graph theory and algorithms.")
        chatHistory.addMemory("Planning toward the VT Computer Science degree.")
    }
    #endif
}

private struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            HokieAppBackground()
                .ignoresSafeArea()
            ProgressView()
        }
    }
}
