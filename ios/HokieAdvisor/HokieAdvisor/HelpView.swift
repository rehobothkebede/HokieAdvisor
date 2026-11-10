import SwiftUI

/// Answers describe the app as implemented; update them when behavior changes.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.schoolTheme) private var theme

    private struct Entry: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let entries: [Entry]
    }

    private var supportedSchools: String {
        ListFormatter.localizedString(byJoining: SchoolTheme.supported.map(\.name))
    }

    private var topics: [Topic] {
        [
            Topic(title: "Schools and programs", entries: [
                Entry(
                    question: "Which schools and programs are supported?",
                    answer: """
                    Agora currently supports \(supportedSchools) students.

                    The transcript-based degree progress estimate covers the Computer Science B.S. only. Students in other programs can still import an official DARS audit and use the advisor, but Agora won't calculate a transcript estimate for their program.
                    """
                ),
            ]),
            Topic(title: "Importing records", entries: [
                Entry(
                    question: "How do I import my transcript?",
                    answer: """
                    Go to Profile → Transcript, or tap Import transcript on Home or Degree Progress. Choose a PDF, PNG, or JPEG of your transcript.

                    The file is sent to Agora's server, where an AI model reads your courses, grades, credits, and semesters. Check the results afterward, since automated reading can make mistakes.
                    """
                ),
                Entry(
                    question: "How do I import my degree audit?",
                    answer: """
                    Open Degree Progress and tap Import DARS audit. Choose the PDF or a screenshot (PNG or JPEG) of your audit from DARS / uAchieve.

                    When an official audit is on file, it appears first and takes priority over Agora's transcript estimate. You can replace or remove it from the same card.
                    """
                ),
                Entry(
                    question: "Can I review or correct imported information?",
                    answer: """
                    Open Profile → Transcript to review the courses Agora read. Individual courses can't be edited. If something is wrong, re-upload a clearer file; a new upload replaces the previous one.

                    On the same screen you can mark how your current classes are going. In Profile you can change your name and graduation year. Your program can't be changed in the app.

                    For your official audit, use Replace audit or remove it in Degree Progress.
                    """
                ),
            ]),
            Topic(title: "Advisor", entries: [
                Entry(
                    question: "What can the advisor do?",
                    answer: """
                    It answers questions about requirements, courses, and planning, and helps you study CS and math topics with formatted math, code, and step-through graph diagrams.

                    Each question includes your imported transcript courses, in-progress courses, program, and saved memories.

                    You can attach a photo, a PDF with selectable text (up to 30 pages), or a text file. Photos are compressed before sending.
                    """
                ),
                Entry(
                    question: "What can't the advisor do?",
                    answer: """
                    It can't access your school's systems: it doesn't log in to DARS, register you for classes, or contact your advisor.

                    Answers are AI-generated and can be wrong. Check them against your official audit and your academic advisor before making enrollment decisions.

                    Scanned PDFs without selectable text can't be read; attach a photo of the page instead. Voice input isn't available.
                    """
                ),
                Entry(
                    question: "How do saved chats work?",
                    answer: """
                    Chats are saved automatically. Tap the history button on the Advisor screen to reopen or delete one.

                    Attached files are sent with that one question and aren't saved in chat history; the chat keeps only the file name.
                    """
                ),
                Entry(
                    question: "How do chat memories work?",
                    answer: """
                    Memories are short notes included with every question, such as your study preferences or course goals. Add your own in Profile → Saved memories.

                    Agora can also add memories on its own: topics you keep returning to, and short facts the advisor picks up from your messages.

                    In Saved memories you can edit or delete any memory, or use Delete all. When you're signed in, memories are saved to your account, and deleting one also removes it from your account.
                    """
                ),
            ]),
            Topic(title: "Courses and syllabi", entries: [
                Entry(
                    question: "Where do registration dates come from?",
                    answer: """
                    From your school's official pages. Each date shows its source and when Agora last checked it. If an official page differs from what Agora shows, follow the official page.

                    Agora can't register, drop, or withdraw you. Use your school's registration system and official forms.
                    """
                ),
                Entry(
                    question: "Who can see my syllabi?",
                    answer: """
                    Only you. Uploaded syllabi and the details read from them are private to your account and aren't shared with other students.

                    Agora reads the syllabus text on your device and sends that text to its AI provider to find dates and policies. You review everything before Agora uses it, and your corrections are kept separate from what the document says.
                    """
                ),
                Entry(
                    question: "Why does Agora need a reviewed syllabus?",
                    answer: """
                    Exam dates, office hours, and policies can differ by section and term. Agora uses only details you've checked against your own section's syllabus, and it never turns phrases like "Week 6" into a date for you. Without a reviewed syllabus, the rest of Agora still works.
                    """
                ),
                Entry(
                    question: "What happens when I delete a syllabus?",
                    answer: """
                    Deleting a syllabus version removes the file, the details read from it, your corrections, and its reminders from Agora's active systems right away, and cancels its notifications on this device. Removing a course or deleting your account does the same for every version.

                    Copies can remain in the database provider's backups until those backups expire on their own schedule. Agora can't remove individual items from backups.
                    """
                ),
            ]),
            Topic(title: "Account and data", entries: [
                Entry(
                    question: "What do Sign Out, Clear Local Data, and Reset Account do?",
                    answer: """
                    Sign Out signs you out on this device. Your account and the data saved to it stay as they are.

                    Clear Local Data removes your transcript, academic data, saved chats, and memories from this device, then signs you out. Data saved to your account is not deleted.

                    Reset Account & Restart asks Agora's server to delete your account. Your profile, imported transcript and audit results, saved chats, memories, and uploaded syllabi are stored with that account and are removed with it. The app then returns to the start.
                    """
                ),
            ]),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
                    ForEach(topics) { topic in
                        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
                            Text(topic.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                                .accessibilityAddTraits(.isHeader)
                            VStack(spacing: 0) {
                                ForEach(Array(topic.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { Divider().padding(.leading, AgoraSpacing.lg) }
                                    FAQRow(question: entry.question, answer: entry.answer)
                                }
                            }
                            .glassSurface(cornerRadius: AgoraRadius.card)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, AgoraSpacing.lg)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Help & FAQ",
                    subtitle: "How \(AgoraBrand.name) works",
                    symbol: "questionmark.circle.fill",
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

private struct FAQRow: View {
    let question: String
    let answer: String

    #if DEBUG
    /// `-HokieExpandFAQ` opens every answer for visual QA.
    private let initiallyExpanded = ProcessInfo.processInfo.arguments.contains("-HokieExpandFAQ")
    #else
    private let initiallyExpanded = false
    #endif

    var body: some View {
        AgoraDisclosureRow(
            title: question,
            detail: answer,
            titleFont: .body.weight(.semibold),
            detailFont: .subheadline,
            initiallyExpanded: initiallyExpanded
        )
    }
}

#Preview {
    HelpView()
}
