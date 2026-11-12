import SwiftUI
import UIKit
import Combine
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.schoolTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var vm = ChatViewModel()
    private let topID = "chatTop"
    private let bottomID = "chatBottom"
    private let emptyStateBottomID = "chatEmptyStateBottom"
    private let keyboardComposerGap: CGFloat = 24
    private let keyboardMessageBottomPadding: CGFloat = 152
    @State private var showHistory = false
    @State private var showTranscriptImport = false
    @State private var isKeyboardVisible = false
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    private var hasDraft: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSendableDraft: Bool {
        hasDraft
    }

    private var draftMessageText: String {
        vm.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmitDraft: Bool {
        vm.canSend(text: draftMessageText)
    }

    private var draftOverflow: Int {
        draftMessageText.count - ChatViewModel.maxMessageCharacters
    }

    private var keyboardAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(response: 0.38, dampingFraction: 0.90, blendDuration: 0.08)
    }

    private var controlAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.04)
    }

    private var composerBottomPadding: CGFloat {
        isKeyboardVisible ? keyboardComposerGap : HokieChrome.chatComposerRestingBottom
    }

    private var messageBottomPadding: CGFloat {
        isKeyboardVisible ? keyboardMessageBottomPadding : HokieChrome.chatMessageRestingBottom
    }

    private var shouldKeepInputVisible: Bool {
        isKeyboardVisible && isInputFocused
    }

    private var compactTitleProgress: CGFloat {
        guard !vm.messages.isEmpty else { return 0 }
        return min(max((scrollOffset - 82) / 34, 0), 1)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                messageList
                inputBar
            }
            .hokieScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
            .overlay(alignment: .top) { compactTitleOverlay }
        }
        .swipeDownToDismissKeyboard()
        .onKeyboardVisibilityChange { visible in
            withAnimation(keyboardAnimation) {
                isKeyboardVisible = visible
            }
        }
        .animation(keyboardAnimation, value: isKeyboardVisible)
        .onAppear {
            vm.configure(store: chatHistory)
            if vm.major.isEmpty && !appState.major.isEmpty { vm.major = appState.major }
            vm.transcriptCourses = appState.transcriptCourses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
            #if DEBUG
            loadVisualQAChatIfRequested()
            #endif
        }
        .onDisappear { vm.autoSave() }
        .onChange(of: appState.major) { _, major in
            if !major.isEmpty { vm.major = major }
        }
        .onChange(of: appState.transcriptCourses) { _, courses in
            vm.transcriptCourses = courses
            vm.inProgressSummary = appState.inProgressSummary
            vm.transcriptNotes = appState.transcriptNotes
        }
        .onChange(of: appState.transcriptNotes) { _, notes in
            vm.transcriptNotes = notes
        }
        .sheet(isPresented: $showHistory) {
            ChatHistorySheet(vm: vm)
                .environmentObject(chatHistory)
        }
        .sheet(isPresented: $showTranscriptImport) {
            TranscriptView().environmentObject(appState)
        }
    }

    // MARK: - Header

    private var header: some View {
        HokiePageHeader(
            title: "MyAdvisor",
            eyebrow: "",
            subtitle: dynamicTypeSize.isAccessibilitySize
                ? "Your degree. Your next steps."
                : "Plan your degree, understand requirements, and find the right support.",
            symbol: "bubble.left.and.bubble.right.fill",
            accent: theme.accent,
        ) {
            HStack(spacing: 8) {
                headerButton("clock.arrow.circlepath", label: "Chat history") { showHistory = true }
                if !vm.messages.isEmpty {
                    headerButton("square.and.pencil", label: "New chat") { vm.clearConversation() }
                }
            }
        }
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 44, height: 44)
                .glassCircle(strokeOpacity: 0.08)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var compactTitleOverlay: some View {
        HokieCompactTitleBar(title: "MyAdvisor", progress: compactTitleProgress)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 10) {
                        Color.clear
                            .frame(height: 1)
                            .id(topID)
                        header
                        if vm.messages.isEmpty {
                            emptyState
                            Color.clear
                                .frame(height: messageBottomPadding)
                                .id(emptyStateBottomID)
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(vm.messages) { MessageBubble(message: $0) }
                                if vm.canContinueTruncatedAnswer && vm.isReadyForMessage {
                                    ContinueAnswerChip { Task { await vm.sendMessage(textOverride: ChatViewModel.continuePrompt) } }
                                }
                                if vm.isLoading { TypingIndicator() }
                                if let error = vm.errorMessage { ErrorBanner(message: error) }
                                Color.clear
                                    .frame(height: messageBottomPadding)
                                    .id(bottomID)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    guard abs(offset - scrollOffset) > 0.5 else { return }
                    scrollOffset = offset
                }

                if !vm.messages.isEmpty {
                    Button {
                        withAnimation(keyboardAnimation) {
                            proxy.scrollTo(bottomID, anchor: .bottom)
                        }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 46, height: 46)
                            .glassCapsule(strokeOpacity: 0.10)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, composerBottomPadding + 62)
                    .accessibilityLabel("Jump to latest message")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard vm.messages.isEmpty else { return }
                if shouldKeepInputVisible {
                    scrollKeyboardTargetIntoView(proxy)
                } else {
                    resetEmptyChatToTop(proxy)
                }
            }
            .onChange(of: isKeyboardVisible) { _, visible in
                guard visible, isInputFocused else { return }
                scrollKeyboardTargetIntoView(proxy)
            }
            .onChange(of: isInputFocused) { _, focused in
                guard focused, isKeyboardVisible else { return }
                scrollKeyboardTargetIntoView(proxy)
            }
            .onChange(of: vm.messages.count) { _, count in
                if count == 0 {
                    if shouldKeepInputVisible {
                        scrollKeyboardTargetIntoView(proxy)
                    } else {
                        withAnimation(keyboardAnimation) {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    }
                } else {
                    withAnimation(keyboardAnimation) {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    }
                }
            }
            .onChange(of: vm.isLoading) { _, _ in
                guard !vm.messages.isEmpty else { return }
                withAnimation(keyboardAnimation) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: vm.messages.last?.content) { _, _ in
                guard !vm.messages.isEmpty else { return }
                proxy.scrollTo(bottomID, anchor: .bottom)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.xl) {
            if let error = vm.errorMessage { ErrorBanner(message: error) }
            contextCard

            if appState.needsTutoringSupport {
                SuggestionChip(
                    title: "I'm struggling with \(appState.strugglingCourses.first ?? "my classes"). What should I do?",
                    icon: "lifepreserver"
                ) { sendSuggestion("I'm struggling with \(appState.strugglingCourses.first ?? "my classes"). What should I do?") }
            }

            suggestionGroup("Plan your degree", icon: "checklist.checked", suggestions: planningSuggestions)
            suggestionGroup("Manage your semester", icon: "calendar", suggestions: semesterSuggestions)
        }
        .padding(.top, AgoraSpacing.sm)
    }

    /// States only what the app actually sends with each question.
    private var contextCard: some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
            Text("Pilot · up to 10 AI replies a day")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accentText)
            Text("MyAdvisor helps with academic planning and finding support. Assignment solutions and general tutoring aren’t included in this pilot.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if appState.hasTranscript {
                Label {
                    Text(contextLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "doc.text.fill").foregroundStyle(theme.accent)
                }
            } else {
                Text("Import your transcript so answers about requirements and courses can reflect your record.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Import transcript") { showTranscriptImport = true }
                    .buttonStyle(.agoraSecondary)
            }
        }
        .padding(AgoraSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card)
    }

    private var contextLine: String {
        let courses = appState.transcriptCourses.count
        var line = "Questions include your transcript (\(courses) course\(courses == 1 ? "" : "s"))"
        let memories = chatHistory.memories.count
        if memories > 0 {
            line += " and \(memories) saved memor\(memories == 1 ? "y" : "ies")"
        }
        return line + "."
    }

    private struct Suggestion: Hashable {
        let title: String
        let icon: String
        /// Sent as-is when set; otherwise `title` is placed in the composer to finish.
        let prompt: String?
    }

    private var planningSuggestions: [Suggestion] {
        [
            Suggestion(title: "What requirements do I have left?", icon: "list.bullet.clipboard", prompt: "What requirements do I have left?"),
            Suggestion(title: "Explain my latest degree audit.", icon: "doc.text.magnifyingglass", prompt: "Explain my latest degree audit."),
            Suggestion(title: "What prerequisites am I missing?", icon: "arrow.triangle.branch", prompt: "What prerequisites am I missing for the courses I want to take next?"),
            Suggestion(title: "Help me prepare for my advising appointment.", icon: "calendar.badge.clock", prompt: "Help me prepare for my advising appointment."),
        ]
    }

    private var semesterSuggestions: [Suggestion] {
        [
            Suggestion(title: "Help me plan my study week.", icon: "calendar", prompt: "Help me plan my study week around my current courses."),
            Suggestion(title: "Where can I get help with a difficult class?", icon: "lifepreserver", prompt: "Where can I find tutoring or office hours for a difficult class?"),
        ]
    }

    private func suggestionGroup(_ title: String, icon: String, suggestions: [Suggestion]) -> some View {
        VStack(alignment: .leading, spacing: AgoraSpacing.sm) {
            SectionLabel(title: title, icon: icon, color: theme.accent)
            ForEach(suggestions, id: \.self) { suggestion in
                SuggestionChip(title: suggestion.title, icon: suggestion.icon) {
                    if let prompt = suggestion.prompt {
                        sendSuggestion(prompt)
                    } else {
                        vm.inputText = "Help me understand "
                        isInputFocused = true
                    }
                }
            }
        }
    }

    private func sendSuggestion(_ text: String) {
        vm.inputText = text
        Task { await vm.sendMessage() }
    }

    private func resetEmptyChatToTop(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            proxy.scrollTo(topID, anchor: .top)
        }
    }

    private func scrollKeyboardTargetIntoView(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(keyboardAnimation) {
                if vm.messages.isEmpty {
                    proxy.scrollTo(emptyStateBottomID, anchor: .bottom)
                } else {
                    proxy.scrollTo(bottomID, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draftOverflow > 0 {
                Text("Message is \(draftOverflow.formatted()) characters over the \(ChatViewModel.maxMessageCharacters.formatted())-character limit.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.leading, 20)
                    .transition(.opacity)
            }

            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("Ask about your degree or a course", text: $vm.inputText, axis: .vertical)
                            .focused($isInputFocused)
                            .lineLimit(1...5)
                            .submitLabel(.return)
                            .textInputAutocapitalization(.sentences)
                            .autocorrectionDisabled(false)
                            .tint(theme.accent)
                            .font(.body)
                            .padding(.leading, 18)
                            .padding(.vertical, 13)

                        Group {
                            if hasSendableDraft {
                                Button {
                                    sendDraft()
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundStyle(canSubmitDraft ? theme.onAccent : Color.secondary)
                                        .frame(width: 38, height: 38)
                                        .background(canSubmitDraft ? theme.accent : Color.primary.opacity(0.08), in: Circle())
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .disabled(!canSubmitDraft)
                                .id("send")
                                .transition(.scale(scale: 0.82).combined(with: .opacity))
                                .accessibilityLabel("Send message")
                            }
                        }
                        .padding(.trailing, 5)
                        .padding(.bottom, 2)
                    }
                    .glassSurface(cornerRadius: 24, strokeOpacity: 0.08)
                    .animation(controlAnimation, value: hasSendableDraft)
                }


            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, composerBottomPadding)
        .offset(y: isKeyboardVisible ? -3 : 0)
        .shadow(color: Color.black.opacity(isKeyboardVisible ? 0.08 : 0.04), radius: isKeyboardVisible ? 18 : 10, x: 0, y: 8)
        .background(.clear)
        .animation(keyboardAnimation, value: isKeyboardVisible)
    }

    private func sendDraft() {
        guard canSubmitDraft else { return }
        let text = draftMessageText
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.dismissKeyboard()
        Task { @MainActor in
            await vm.sendMessage(textOverride: text)
        }
    }

}

#if DEBUG
extension ChatView {
    /// `-HokieVisualQAChat` opens a long sample conversation covering markdown,
    /// long math, a stepped graph, an attachment, and cut-off/interrupted answers.
    /// `-HokieVisualQAKeyboard` also focuses the composer.
    fileprivate func loadVisualQAChatIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-HokieVisualQAChat"), vm.messages.isEmpty else { return }
        let longMath = #"$$\sum_{k=1}^{n} k^2 = \frac{n(n+1)(2n+1)}{6} \quad\text{and}\quad \int_0^1 x^2\,dx + \int_1^2 (3x^2 - 2x + 1)\,dx + \int_2^3 e^{x}\sin(x)\,dx$$"#
        let graph = """
        ```graph
        A - B
        A - C
        B - D
        C - D
        D - E
        step: A | Start at A
        step: A, B, C | Visit A's neighbors
        step: A -> B -> D | Reach D through B
        step: A -> B -> D -> E | E is two layers past B
        ```
        """
        let messages: [ChatMessage] = [
            ChatMessage(role: "user", content: "What requirements do I have left?"),
            ChatMessage(role: "assistant", content: """
            ## Remaining requirements
            Based on your transcript, these groups are still open:

            - **Systems**: CS 2506 (after CS 2505)
            - **Upper-division CS**: 21 credits
            - **Pathways 2 and 3**: one course each

            1. Register for CS 2506 next term.
            2. Pick one Pathways 2 course that fits your schedule.

            Confirm the list with your official DARS audit before registering.
            """),
            ChatMessage(role: "user", content: "Can you check this sum and integral?\n\n📎 Homework 4.pdf"),
            ChatMessage(role: "assistant", content: "The closed form is right. Here is the whole expression on one line:\n\n\(longMath)\n\nInline, that first sum is $\\frac{n(n+1)(2n+1)}{6}$."),
            ChatMessage(role: "user", content: "Show me BFS on a graph with a visual"),
            ChatMessage(role: "assistant", content: "BFS explores one layer at a time. Step through it:\n\n\(graph)\n\n```swift\nvar queue = [start]\nwhile !queue.isEmpty { let node = queue.removeFirst() }\n```" + ChatViewModel.truncationNote),
            ChatMessage(role: "user", content: "And DFS?"),
            ChatMessage(role: "assistant", content: "DFS goes deep before wide. Start at A, then follow one branch" + ChatViewModel.interruptionNote),
        ]
        // Loaded after the scroll reader is in place, the way a history pick arrives.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            vm.loadSession(ChatSession(id: UUID(), title: "Visual QA", date: Date(), messages: messages))
            if arguments.contains("-HokieVisualQAChatError") {
                vm.errorMessage = "The advisor is unavailable right now. Try again in a moment."
            }
        }
        if arguments.contains("-HokieVisualQAKeyboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { isInputFocused = true }
        }
    }
}
#endif

struct ChatComposerCircleButton: View {
    let systemName: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassCircle(strokeOpacity: 0.08)
                .rotationEffect(.degrees(isActive ? 45 : 0))
                .animation(.spring(response: 0.30, dampingFraction: 0.86, blendDuration: 0.04), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isActive ? "Close attachment menu" : "Add attachment")
    }
}

struct ChatAttachment: Identifiable {
    enum Kind {
        case camera, photo, file

        var label: String {
            switch self {
            case .camera: return "Camera"
            case .photo:  return "Photo"
            case .file:   return "File"
            }
        }

        var icon: String {
            switch self {
            case .camera: return "camera.fill"
            case .photo:  return "photo"
            case .file:   return "doc.fill"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let name: String
    let image: UIImage?
    let summary: String
    let payload: ChatAttachmentPayload

    init(kind: Kind, prepared: ChatAttachmentProcessor.Prepared) {
        self.kind = kind
        self.name = prepared.payload.name
        self.image = prepared.thumbnail
        self.summary = prepared.summary
        self.payload = prepared.payload
    }
}

struct ChatAttachmentChip: View {
    @Environment(\.schoolTheme) private var theme

    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let image = attachment.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: attachment.kind.icon)
                    .font(.caption.bold())
                    .foregroundStyle(theme.accent)
                    .frame(width: 34, height: 34)
                    .glassCircle(strokeOpacity: 0.08)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.kind.label)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                Text("\(attachment.name) · \(attachment.summary)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove attachment")
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .glassCapsule(strokeOpacity: 0.08)
    }
}

struct ChatAttachmentMenu: View {
    let cameraAvailable: Bool
    let onCamera: () -> Void
    let onFiles: () -> Void
    @Binding var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onCamera) {
                AttachmentMenuRow(icon: "camera", title: "Camera")
            }
            .buttonStyle(.plain)
            .disabled(!cameraAvailable)
            .opacity(cameraAvailable ? 1 : 0.45)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                AttachmentMenuRow(icon: "photo", title: "Photos")
            }
            .buttonStyle(.plain)

            Button(action: onFiles) {
                AttachmentMenuRow(icon: "paperclip", title: "Files")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: 240, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.card, strokeOpacity: 0.08)
    }
}

struct AttachmentMenuRow: View {
    @Environment(\.schoolTheme) private var theme

    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 14) {
            HokieIconTile(symbol: icon, color: theme.accent, size: 40)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @Environment(\.schoolTheme) private var theme

    let message: ChatMessage
    private var isUser: Bool { message.role == "user" }

    private enum AnswerStatus {
        case truncated, interrupted
    }

    /// Splits the status notes `ChatViewModel` appends to stored text so they can
    /// be shown as labels. The stored message itself is unchanged.
    private var parsed: (text: String, status: AnswerStatus?) {
        let content = message.content
        if content.hasSuffix(ChatViewModel.truncationNote) {
            return (String(content.dropLast(ChatViewModel.truncationNote.count)), .truncated)
        }
        if content.hasSuffix(ChatViewModel.interruptionNote) {
            return (String(content.dropLast(ChatViewModel.interruptionNote.count)), .interrupted)
        }
        return (content, nil)
    }

    /// Splits off the "📎 name" line `ChatViewModel` adds for an attachment.
    private var userParts: (text: String, attachment: String?) {
        let marker = "\n\n📎 "
        guard let range = message.content.range(of: marker, options: .backwards) else {
            return (message.content, nil)
        }
        return (String(message.content[..<range.lowerBound]), String(message.content[range.upperBound...]))
    }

    @ViewBuilder
    private var bubbleContent: some View {
        if isUser {
            let parts = userParts
            VStack(alignment: .trailing, spacing: 8) {
                if !parts.text.isEmpty {
                    Text(parts.text)
                        .font(.body)
                        .foregroundStyle(theme.onAccent)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let attachment = parts.attachment {
                    Label(attachment, systemImage: "paperclip")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(theme.onAccent.opacity(0.16), in: Capsule())
                        .accessibilityLabel("Attachment: \(attachment)")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            let parts = parsed
            VStack(alignment: .leading, spacing: 8) {
                Text("Advisor")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                MarkdownBody(text: parts.text.isEmpty ? " " : parts.text, baseFont: .body, baseColor: .primary)
                if message.isStreaming {
                    StreamingCursor()
                }
                if let status = parts.status {
                    statusLabel(status)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func statusLabel(_ status: AnswerStatus) -> some View {
        Label(
            status == .truncated ? "Answer was cut off. Ask to continue." : "Answer interrupted before it finished.",
            systemImage: status == .truncated ? "scissors" : "pause.circle"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassInset(cornerRadius: 10)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 48) }
            bubbleContent
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isUser ? "You" : "Advisor")
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @Environment(\.schoolTheme) private var theme
    @State private var visible = true
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .frame(width: 2, height: 16)
            .foregroundStyle(theme.accent)
            .opacity(visible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: visible)
            .onReceive(timer) { _ in visible.toggle() }
            .accessibilityHidden(true)
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @Environment(\.schoolTheme) private var theme
    @State private var phase = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle().frame(width: 7, height: 7)
                        .foregroundStyle(theme.accent.opacity(phase == i ? 1 : 0.3))
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            Text("Thinking")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .glassCapsule(strokeOpacity: 0.08)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Advisor is responding")
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: AgoraRadius.inset)
    }
}

// MARK: - Continue Chip

struct ContinueAnswerChip: View {
    @Environment(\.schoolTheme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Continue answer", systemImage: "arrow.down.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint("Asks the advisor to finish the answer that was cut off")
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    @Environment(\.schoolTheme) private var theme

    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .glassSurface(cornerRadius: AgoraRadius.inset, strokeOpacity: 0.07)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chat History Sheet

struct ChatHistorySheet: View {
    @EnvironmentObject var chatHistory: ChatHistoryStore
    @Environment(\.schoolTheme) private var theme
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if chatHistory.sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundStyle(theme.accent.opacity(0.5))
                        Text("No saved chats yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(AgoraPalette.brandInk)
                        Text("Your conversations are automatically saved as you chat.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(chatHistory.sessions) { session in
                                ChatHistoryRow(
                                    session: session,
                                    isCurrent: session.id == vm.currentSessionID,
                                    dateText: Self.dateFormatter.string(from: session.date),
                                    onOpen: {
                                        vm.loadSession(session)
                                        dismiss()
                                    },
                                    onDelete: {
                                        if session.id == vm.currentSessionID {
                                            vm.discardCurrentConversation()
                                        }
                                        chatHistory.delete(sessionID: session.id)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .hokieScreenBackground()
            .safeAreaInset(edge: .top) {
                HokieSheetHeader(
                    title: "Chat History",
                    subtitle: "\(chatHistory.sessions.count) saved conversation\(chatHistory.sessions.count == 1 ? "" : "s")",
                    symbol: "clock.arrow.circlepath",
                    accent: theme.accent
                ) {
                    HStack(spacing: 8) {
                        Button {
                            vm.clearConversation()
                            dismiss()
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .glassCircle(strokeOpacity: 0.08)
                        }
                        .accessibilityLabel("New chat")
                        .buttonStyle(.plain)

                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 44, height: 44)
                                .glassCircle(strokeOpacity: 0.08)
                        }
                        .accessibilityLabel("Close")
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(theme.accent)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .transparentNavigationChrome()
        }
    }
}

private struct ChatHistoryRow: View {
    @Environment(\.schoolTheme) private var theme

    let session: ChatSession
    let isCurrent: Bool
    let dateText: String
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var userMessageCount: Int {
        session.messages.filter { $0.role == "user" }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    HokieIconTile(
                        symbol: isCurrent ? "checkmark.bubble.fill" : "text.bubble.fill",
                        color: isCurrent ? theme.accent : AgoraPalette.brandInk.opacity(0.75),
                        size: 40
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)

                        Text("\(dateText) · \(userMessageCount) \(userMessageCount == 1 ? "message" : "messages")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.82))
                    .frame(width: 44, height: 44)
                    .glassCircle(strokeOpacity: 0.08)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete chat")
        }
        .padding(14)
        .glassSurface(cornerRadius: 22)
    }
}

#Preview { ChatView().environmentObject(AppState()).environmentObject(ChatHistoryStore()) }
