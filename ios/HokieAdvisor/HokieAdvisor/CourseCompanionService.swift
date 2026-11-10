import Foundation

/// Calls the `courses` edge function. Every request carries the student's
/// session, and the server enforces access with row-level security.
nonisolated enum CourseCompanionAPI {
    private struct ActionBody<Payload: Encodable>: Encodable {
        let action: String
        let payload: Payload

        func encode(to encoder: Encoder) throws {
            try payload.encode(to: encoder)
            var container = encoder.container(keyedBy: AnyKey.self)
            try container.encode(action, forKey: AnyKey("action"))
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    struct Empty: Encodable {}

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: Endpoint

    static var endpoint: URL? {
        #if DEBUG
        if let override = debugOverride { return override.url }
        #endif
        return URL(string: "\(APIService.functionBaseURL)/courses")
    }

    static func headers() async -> [String: String] {
        #if DEBUG
        if let override = debugOverride { return ["Authorization": "Bearer \(override.token)"] }
        #endif
        return await APIService.supabaseFunctionHeaders(includeUserSession: true)
    }

    #if DEBUG
    /// `-AgoraCoursesEndpoint <url> -AgoraCoursesToken <token>` points the app at
    /// the local QA server (backend/supabase/tests/courses_dev_server.ts), which
    /// runs this function's handler against a local database. Debug builds only.
    static var debugOverride: (url: URL, token: String)? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-AgoraCoursesEndpoint"), args.indices.contains(i + 1),
              let url = URL(string: args[i + 1]),
              let j = args.firstIndex(of: "-AgoraCoursesToken"), args.indices.contains(j + 1) else { return nil }
        return (url, args[j + 1])
    }
    #endif

    // MARK: Requests

    static func call<Payload: Encodable, Response: Decodable>(
        _ action: String,
        _ payload: Payload,
        as: Response.Type = Response.self
    ) async throws -> Response {
        guard let url = endpoint else { throw APIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in await headers() { request.setValue(value, forHTTPHeaderField: key) }
        do {
            request.httpBody = try encoder.encode(ActionBody(action: action, payload: payload))
        } catch {
            throw APIError.decodingError(error)
        }
        return try await send(request)
    }

    static func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) } catch { throw APIError.networkError(error) }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIService.error(from: data, statusCode: http.statusCode)
        }
        do { return try decoder.decode(Response.self, from: data) } catch { throw APIError.decodingError(error) }
    }

    // MARK: Stage 1

    static func overview() async throws -> CoursesOverview {
        try await call("overview", Empty())
    }

    static func registrationGuide(termKey: String?) async throws -> RegistrationGuide {
        struct Payload: Encodable { let termKey: String? }
        return try await call("registration_guide", Payload(termKey: termKey))
    }
}
