import Foundation
import Observation
import UIKit
import UserNotifications

@Observable
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private(set) var isAuthorized = false
    var errorMessage: String?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var currentRestID: String?
    @ObservationIgnored private var reminderRevision = UUID()

    private override init() {
        super.init()
        center.delegate = self
        currentRestID = UserDefaults.standard.string(forKey: "restNotificationID")
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    // Call only in response to an explicit reminder/timer action.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            isAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            errorMessage = isAuthorized ? nil : "فعّل الإشعارات من إعدادات الجهاز للتنبيه عند انتهاء الراحة."
        } catch {
            errorMessage = "تعذر طلب إذن الإشعارات. حاول مرة أخرى من إعدادات الجهاز."
        }
        return isAuthorized
    }

    func scheduleRest(deadline: Date, requestPermission: Bool = true) async {
        guard !Task.isCancelled else { return }
        cancelRest()
        let identifier = "wateera.rest.\(UUID().uuidString)"
        currentRestID = identifier
        UserDefaults.standard.set(identifier, forKey: "restNotificationID")
        await refreshAuthorization()
        if !isAuthorized && requestPermission { _ = await requestAuthorization() }
        guard !Task.isCancelled, isAuthorized, currentRestID == identifier, deadline > .now else { return }
        errorMessage = nil
        let content = UNMutableNotificationContent()
        content.title = "انتهت الراحة"
        content.body = "أنت جاهز للمجموعة التالية. حافظ على أدائك."
        content.sound = .default
        content.threadIdentifier = "workout-rest"
        content.userInfo = ["route": "activeWorkout"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, deadline.timeIntervalSinceNow), repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            if currentRestID != identifier { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
        } catch {
            if currentRestID == identifier { errorMessage = "تعذر جدولة تنبيه الراحة. سيستمر المؤقت داخل التطبيق." }
        }
    }

    func cancelRest() {
        if let identifier = currentRestID {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
        currentRestID = nil
        UserDefaults.standard.removeObject(forKey: "restNotificationID")
    }

    func reschedule(reminders: [WorkoutReminder], requestPermission: Bool = false) async {
        let revision = UUID()
        reminderRevision = revision
        // Validate before replacing an existing schedule.
        let enabled = reminders.filter(\.enabled)
        guard enabled.reduce(0, { $0 + $1.weekdays.count }) <= 63 else {
            errorMessage = "عدد مواعيد التذكير يتجاوز الحد الذي يدعمه النظام. قلّل الأيام أو التذكيرات النشطة."
            return
        }
        let pending = await center.pendingNotificationRequests()
        guard reminderRevision == revision else { return }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("wateera.reminder.") })
        guard !enabled.isEmpty else { errorMessage = nil; return }
        await refreshAuthorization()
        if !isAuthorized && requestPermission { _ = await requestAuthorization() }
        guard isAuthorized, reminderRevision == revision else { return }
        errorMessage = nil
        // Reserve one of the system's pending notification slots for the rest timer.
        for reminder in enabled {
            let weekdays = Set(reminder.weekdaysRaw.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            for weekday in weekdays.sorted() {
                guard reminderRevision == revision else { return }
                var components = DateComponents()
                components.calendar = Calendar(identifier: .gregorian)
                components.weekday = weekday
                components.hour = min(23, max(0, reminder.hour))
                components.minute = min(59, max(0, reminder.minute))
                let content = UNMutableNotificationContent()
                switch reminder.kindRaw {
                case "rest":
                    content.title = "يوم الراحة"
                    content.body = "امنح جسمك وقتًا للتعافي، واهتم بالنوم والترطيب."
                case "weighIn":
                    content.title = "حان وقت قياس الوزن"
                    content.body = "سجّل وزنك اليوم لمتابعة تقدمك."
                default:
                    content.title = "موعد تمرينك"
                    content.body = "خطوة جديدة نحو هدفك. ابدأ تمرين اليوم."
                }
                content.sound = .default
                content.threadIdentifier = "workout-reminders"
                let identifier = "wateera.reminder.\(revision.uuidString).\(reminder.id.uuidString).\(weekday)"
                do {
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content,
                                                              trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)))
                    if reminderRevision != revision { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
                } catch {
                    errorMessage = "تعذر حفظ أحد التذكيرات. تحقق من إعدادات الإشعارات."
                }
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.content.userInfo["route"] as? String == "activeWorkout" {
            Task { @MainActor in NotificationCenter.default.post(name: .openActiveWorkout, object: nil) }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let openActiveWorkout = Notification.Name("wateera.openActiveWorkout")
}
