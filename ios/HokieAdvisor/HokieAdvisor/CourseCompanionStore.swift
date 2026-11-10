import Combine
import Foundation

/// State for the Home "This term" section and the screens it opens.
@MainActor
final class CourseCompanionStore: ObservableObject {
    enum LoadState: Equatable {
        case idle, loading, loaded, unsupported
        case failed(String)
    }

    @Published private(set) var state: LoadState = .idle
    @Published private(set) var overview: CoursesOverview?
    /// The student's chosen term; falls back to the term in session.
    @Published var selectedTermKey: String? {
        didSet { UserDefaults.standard.set(selectedTermKey, forKey: Self.termKeyDefaultsKey) }
    }

    private static let termKeyDefaultsKey = "courseCompanionSelectedTermKey"

    init() {
        selectedTermKey = UserDefaults.standard.string(forKey: Self.termKeyDefaultsKey)
    }

    var terms: [AcademicTerm] { overview?.terms ?? [] }

    var selectedTerm: AcademicTerm? {
        terms.first { $0.termKey == selectedTermKey } ?? terms.first { $0.termKey == overview?.currentTermKey }
    }

    var isAvailable: Bool {
        #if DEBUG
        // Visual QA runs without a backend unless pointed at the local QA server.
        if ProcessInfo.processInfo.arguments.contains("-HokieVisualQA"),
           CourseCompanionAPI.debugOverride == nil {
            return false
        }
        #endif
        return true
    }

    func load(force: Bool = false) async {
        guard isAvailable else { return }
        if state == .loading { return }
        if !force, state == .loaded { return }
        state = .loading
        do {
            let result = try await CourseCompanionAPI.overview()
            overview = result
            if !result.supported {
                state = .unsupported
                return
            }
            if selectedTermKey == nil || !result.terms.contains(where: { $0.termKey == selectedTermKey }) {
                selectedTermKey = result.currentTermKey
            }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
