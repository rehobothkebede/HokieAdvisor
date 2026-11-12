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
            // A missing deployment is a service problem, not the student's
            // connection. Preserve normal 404s for missing course records.
            if http.statusCode == 404,
               let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               body["code"] as? String == "NOT_FOUND" {
                throw APIError.serverMessage(503, "COURSES_UNAVAILABLE",
                    "Course details are temporarily unavailable. Your transcript and advisor are still available.")
            }
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

    // MARK: Stage 2

    static func listCourses(termKey: String) async throws -> CourseListResponse {
        struct Payload: Encodable { let termKey: String }
        return try await call("list_courses", Payload(termKey: termKey))
    }

    struct NewCourse: Encodable {
        let termKey: String
        let subject: String
        let number: String
        let title: String
        let sectionCode: String
        let instructorName: String
        let origin: String
    }

    static func addCourse(_ course: NewCourse) async throws -> EnrolledCourse {
        try await call("add_course", course, as: AddCourseResponse.self).course
    }

    static func setSyllabusReminder(courseId: String, remindOn: String?) async throws {
        struct Payload: Encodable {
            let courseId: String
            let remindOn: String?
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(courseId, forKey: .courseId)
                try c.encode(remindOn, forKey: .remindOn) // explicit null clears it
            }
            enum CodingKeys: String, CodingKey { case courseId, remindOn }
        }
        struct Response: Decodable { let courseId: String }
        _ = try await call("set_syllabus_reminder", Payload(courseId: courseId, remindOn: remindOn), as: Response.self)
    }

    static func deleteCourse(courseId: String) async throws -> DeleteResponse {
        struct Payload: Encodable { let courseId: String }
        return try await call("delete_course", Payload(courseId: courseId))
    }

    static func deleteDocument(documentId: String) async throws -> DeleteResponse {
        struct Payload: Encodable { let documentId: String }
        return try await call("delete_document", Payload(documentId: documentId))
    }

    static func documentFile(documentId: String) async throws -> Data {
        struct Payload: Encodable { let documentId: String }
        let response: DocumentFileResponse = try await call("document_file", Payload(documentId: documentId))
        guard let data = Data(base64Encoded: response.dataBase64) else {
            throw APIError.decodingError(URLError(.cannotDecodeContentData))
        }
        return data
    }

    // MARK: Stage 3

    static func document(_ documentId: String) async throws -> DocumentDetail {
        struct Payload: Encodable { let documentId: String }
        return try await call("get_document", Payload(documentId: documentId))
    }

    static func reviewFact(_ factId: String, decision: String) async throws {
        struct Payload: Encodable { let factId: String; let decision: String }
        struct Response: Decodable {}
        _ = try await call("review_fact", Payload(factId: factId, decision: decision), as: Response.self)
    }

    static func confirmUnflagged(documentId: String) async throws -> Int {
        struct Payload: Encodable { let documentId: String }
        struct Response: Decodable { let confirmed: [String] }
        return try await call("confirm_unflagged", Payload(documentId: documentId), as: Response.self).confirmed.count
    }

    struct Correction: Encodable {
        var date: String?
        var startTime: String?
        var endTime: String?
        var location: String?
        var weightPercent: Double?
        var text: String?

        /// Only fields the student set are sent.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(date, forKey: .date)
            try c.encodeIfPresent(startTime, forKey: .startTime)
            try c.encodeIfPresent(endTime, forKey: .endTime)
            try c.encodeIfPresent(location, forKey: .location)
            try c.encodeIfPresent(weightPercent, forKey: .weightPercent)
            try c.encodeIfPresent(text, forKey: .text)
        }
        enum CodingKeys: String, CodingKey { case date, startTime, endTime, location, weightPercent, text }
    }

    static func correctFact(_ factId: String, correction: Correction, note: String?) async throws {
        struct Payload: Encodable { let factId: String; let corrected: Correction; let note: String? }
        struct Response: Decodable {}
        _ = try await call("correct_fact", Payload(factId: factId, corrected: correction, note: note), as: Response.self)
    }

    static func removeCorrection(_ factId: String) async throws {
        struct Payload: Encodable { let factId: String }
        struct Response: Decodable {}
        _ = try await call("remove_correction", Payload(factId: factId), as: Response.self)
    }

    static func completeReview(documentId: String) async throws -> [String] {
        struct Payload: Encodable { let documentId: String }
        struct Response: Decodable { let remindersNeedingReconfirm: [String] }
        return try await call("complete_review", Payload(documentId: documentId), as: Response.self).remindersNeedingReconfirm
    }

    static func dashboard(courseId: String) async throws -> CourseDashboard {
        struct Payload: Encodable { let courseId: String }
        return try await call("course_dashboard", Payload(courseId: courseId))
    }

    static func addReminder(factId: String, lead: String) async throws -> CourseReminder {
        struct Payload: Encodable { let factId: String; let lead: String }
        struct Response: Decodable { let reminder: CourseReminder }
        return try await call("add_reminder", Payload(factId: factId, lead: lead), as: Response.self).reminder
    }

    static func deleteReminder(_ reminderId: String) async throws {
        struct Payload: Encodable { let reminderId: String }
        _ = try await call("delete_reminder", Payload(reminderId: reminderId), as: DeleteResponse.self)
    }

    static func resolveReminder(_ reminderId: String, resolution: String) async throws {
        struct Payload: Encodable { let reminderId: String; let resolution: String }
        _ = try await call("resolve_reminder", Payload(reminderId: reminderId, resolution: resolution), as: DeleteResponse.self)
    }

    static func activeReminders() async throws -> [CourseReminder] {
        try await call("list_reminders", Empty(), as: ReminderListResponse.self).reminders
    }

    /// Uploads the original file with the page text read on this device.
    static func uploadSyllabus(courseId: String, file: Data, mimeType: String, fileName: String,
                               extracted: SyllabusTextExtractor.Result) async throws -> UploadSyllabusResponse {
        guard let url = endpoint else { throw APIError.invalidURL }
        let boundary = "agora-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        for (key, value) in await headers() { request.setValue(value, forHTTPHeaderField: key) }

        let pagesJSON = try JSONEncoder().encode(extracted.pages)
        var body = Data()
        func field(_ name: String, _ value: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(value)
            body.append(Data("\r\n".utf8))
        }
        field("action", Data("upload_syllabus".utf8))
        field("course_id", Data(courseId.utf8))
        field("text_method", Data(extracted.method.rawValue.utf8))
        field("pages", pagesJSON)
        let safeName = fileName.replacingOccurrences(of: "\"", with: "")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try await send(request)
    }
}
