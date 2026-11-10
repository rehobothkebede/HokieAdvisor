import Foundation
import UserNotifications

/// Local notifications for the course companion. Identifiers are derived from
/// server records so they can be reconciled and removed when the underlying
/// course, syllabus, or reminder is deleted.
@MainActor
enum CourseReminderScheduler {
    private static var center: UNUserNotificationCenter { .current() }

    static func syllabusIdentifier(termKey: String, courseId: String) -> String {
        "agora.syllabus.\(termKey).\(courseId)"
    }

    /// A reminder for a confirmed syllabus date, keyed by its server record.
    static func factIdentifier(_ reminderId: String) -> String {
        "agora.fact.\(reminderId)"
    }

    /// Asks once, at the moment the student turns on a reminder.
    static func requestPermission() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// "Syllabus not available yet": a 9:00 a.m. nudge on the chosen day.
    static func scheduleSyllabusReminder(course: EnrolledCourse, on day: String) async {
        guard let date = CalendarDay.date(day) else { return }
        var components = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        components = DateComponents(year: components.year, month: components.month, day: components.day, hour: 9)
        let content = UNMutableNotificationContent()
        content.title = "Syllabus for \(course.code)"
        content.body = "Has your instructor posted the syllabus? Add it to turn on reminders for this course."
        let request = UNNotificationRequest(
            identifier: syllabusIdentifier(termKey: course.termKey, courseId: course.id),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }

    static func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    /// Makes pending syllabus reminders for a term match the server.
    static func reconcileSyllabusReminders(termKey: String, courses: [EnrolledCourse]) async {
        let prefix = "agora.syllabus.\(termKey)."
        let wanted = Dictionary(uniqueKeysWithValues: courses.compactMap { course -> (String, (EnrolledCourse, String))? in
            guard let day = course.syllabusRemindOn, course.status == .needed else { return nil }
            return (syllabusIdentifier(termKey: termKey, courseId: course.id), (course, day))
        })
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        remove(identifiers: pending.filter { wanted[$0] == nil })
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        for (identifier, (course, day)) in wanted where !pending.contains(identifier) {
            await scheduleSyllabusReminder(course: course, on: day)
        }
    }
}
