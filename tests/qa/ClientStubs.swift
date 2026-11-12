import Foundation

// Local-only collaborators: no production credentials or account access.
nonisolated enum SupabaseConfig {
    static let url = "http://127.0.0.1:8792"
    static let anonKey = "qa-anon"
}
actor SupabaseAuthService {
    static let shared = SupabaseAuthService()
    struct Session { let accessToken = "qa-token-student" }
    func validatedCurrentSession() async throws -> Session? { Session() }
}
nonisolated enum SyllabusTextExtractor {
    enum Method: String { case pdfText = "pdf_text" }
    struct Page: Encodable { let page: Int; let text: String }
    struct Result { let pages: [Page]; let method: Method }
}
@MainActor final class ChatHistoryStore {
    var memoryContext: [String] = []
    var saved: [ChatSession] = []
    func captureRecurringTopic(from: String) {}
    func addExtractedMemories(_ facts: [String]) { memoryContext += facts }
    func upsert(_ session: ChatSession) { saved.append(session) }
}
