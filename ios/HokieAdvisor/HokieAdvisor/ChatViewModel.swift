import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    /// Mirrors the chat Edge Function's input caps.
    static let maxMessageCharacters = 8_000
    static let maxHistoryMessages = 40

    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var major: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    /// True when the latest answer stopped at the token limit; ChatView offers a Continue chip.
    @Published private(set) var canContinueTruncatedAnswer = false

    static let truncationNote = "\n\n*(Answer was cut off; ask me to continue.)*"
    static let interruptionNote = "\n\n*(interrupted)*"
    static let continuePrompt = "Please continue exactly where you left off."

    // Synced from AppState by ChatView on appear / onChange
    var transcriptCourses: [TranscriptCourse] = []
    var inProgressSummary: [String] = []
    var transcriptNotes: [String] = []

    private(set) var currentSessionID: UUID = UUID()
    private weak var historyStore: ChatHistoryStore?
    private var activeRequestID: UUID?

    var isReadyForMessage: Bool {
        !isLoading
            && !messages.contains(where: { $0.isStreaming })
    }

    var canSend: Bool {
        canSend(text: inputText)
    }

    func canSend(text: String, attachment: ChatAttachmentPayload? = nil) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (!trimmed.isEmpty || attachment != nil)
            && trimmed.count <= Self.maxMessageCharacters
            && isReadyForMessage
    }

    func configure(store: ChatHistoryStore) {
        historyStore = store
    }

    /// Returns false only when the message could not be sent and nothing was
    /// answered, so the caller can restore the draft. A request superseded by
    /// switching or clearing chats counts as sent; its partial answer was saved.
    @discardableResult
    func sendMessage(textOverride: String? = nil, attachment: ChatAttachmentPayload? = nil) async -> Bool {
        let sourceText = textOverride ?? inputText
        let typed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend(text: typed, attachment: attachment) else { return false }

        // The saved message names the attachment; its bytes are sent only with
        // this request and never stored in chat history.
        var text = typed
        if let attachment {
            if text.isEmpty {
                text = attachment.type == .image
                    ? "Can you help me with this photo?"
                    : "Can you help me with this document?"
            }
            text += "\n\n📎 \(attachment.name)"
        }

        inputText = ""
        errorMessage = nil
        canContinueTruncatedAnswer = false
        messages.append(ChatMessage(role: "user", content: text))
        historyStore?.captureRecurringTopic(from: typed)
        isLoading = true

        let payload = messages
            .suffix(Self.maxHistoryMessages)
            .map { ChatPayload(role: $0.role, content: $0.content) }
        let transcriptEntries = transcriptCourses.map {
            TranscriptEntry(code: $0.code, name: $0.name, grade: $0.grade,
                            semester: $0.semester, credits: $0.credits)
        }
        let chatRequest = ChatRequest(
            messages: payload,
            major: major,
            transcript: transcriptEntries,
            inProgressCourses: inProgressSummary,
            transcriptNotes: transcriptNotes,
            chatMemories: historyStore?.memoryContext ?? [],
            attachments: attachment.map { [$0] } ?? []
        )

        let streamID = UUID()
        activeRequestID = streamID
        var streamStarted = false
        var finishReason: String?

        do {
            for try await event in APIService.streamChat(request: chatRequest) {
                guard activeRequestID == streamID else { return true }
                switch event {
                case .token(let token):
                    if !streamStarted {
                        streamStarted = true
                        isLoading = false
                        messages.append(ChatMessage(id: streamID, role: "assistant", content: "", isStreaming: true))
                    }
                    if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                        messages[idx].content += token
                    }
                case .finish(let reason):
                    finishReason = reason
                case .memories(let facts):
                    historyStore?.addExtractedMemories(facts)
                }
            }
            guard activeRequestID == streamID else { return true }
            if let idx = messages.firstIndex(where: { $0.id == streamID }) {
                messages[idx].isStreaming = false
                if finishReason == "length" {
                    messages[idx].content += Self.truncationNote
                    canContinueTruncatedAnswer = true
                }
            }
            activeRequestID = nil
            autoSave()
            isLoading = false
            return true
        } catch {
            guard activeRequestID == streamID else { return true }
            activeRequestID = nil
            isLoading = false
            // Part of the answer already arrived: keep it, marked, rather than
            // throwing it away with the question.
            if let idx = messages.firstIndex(where: { $0.id == streamID }),
               !messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages[idx].content += Self.interruptionNote
                messages[idx].isStreaming = false
                autoSave()
                return true
            }
            messages.removeAll { $0.id == streamID }
            if messages.last?.role == "user" { messages.removeLast() }
            errorMessage = error.localizedDescription
            inputText = typed
            return false
        }
    }

    func loadSession(_ session: ChatSession) {
        finalizeInterruptedStream()
        autoSave()
        activeRequestID = nil
        isLoading = false
        currentSessionID = session.id
        canContinueTruncatedAnswer = false
        messages = session.messages.map {
            ChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false)
        }
        errorMessage = nil
    }

    func autoSave() {
        guard !messages.isEmpty, let store = historyStore else { return }
        let title = messages.first(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(60)
            .description ?? "Chat"
        // A still-streaming answer is saved as interrupted; if the stream
        // finishes, the next save replaces it with the full answer.
        let saved = messages.map {
            let partial = $0.isStreaming && !$0.content.isEmpty
            return ChatMessage(
                id: $0.id,
                role: $0.role,
                content: partial ? $0.content + Self.interruptionNote : $0.content,
                isStreaming: false
            )
        }
        store.upsert(ChatSession(id: currentSessionID, title: title, date: Date(), messages: saved))
    }

    func clearConversation() {
        finalizeInterruptedStream()
        autoSave()
        resetConversation()
    }

    func discardCurrentConversation() {
        resetConversation()
    }

    /// Called when the student switches away from an answer that is still
    /// streaming: the partial text is saved with an "(interrupted)" mark.
    private func finalizeInterruptedStream() {
        guard let idx = messages.firstIndex(where: \.isStreaming) else { return }
        if messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.remove(at: idx)
        } else {
            messages[idx].content += Self.interruptionNote
            messages[idx].isStreaming = false
        }
    }

    private func resetConversation() {
        activeRequestID = nil
        isLoading = false
        canContinueTruncatedAnswer = false
        messages = []
        inputText = ""
        errorMessage = nil
        currentSessionID = UUID()
    }
}
