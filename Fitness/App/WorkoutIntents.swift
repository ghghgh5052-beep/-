import AppIntents
import Foundation

struct StartTodayWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "ابدأ تمرين اليوم"
    static var description = IntentDescription("افتح وتيرة وابدأ تمرين اليوم من خطتك الحالية.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        SharedWorkoutStorage.requestStartToday()
        NotificationCenter.default.post(name: .startTodayWorkoutRequested, object: nil)
        return .result()
    }
}

extension Notification.Name {
    static let startTodayWorkoutRequested = Notification.Name("wateera.startTodayWorkoutRequested")
    static let workoutShortcutRequested = Notification.Name("wateera.workoutShortcutRequested")
}

struct OpenWeeklyReportIntent: AppIntent {
    static var title: LocalizedStringResource = "اعرض تقرير الأسبوع"
    static var description = IntentDescription("افتح تقرير التدريب الأسبوعي في وتيرة.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("report", forKey: "pendingWorkoutAction")
        NotificationCenter.default.post(name: .workoutShortcutRequested, object: nil)
        return .result()
    }
}

struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "أنه الراحة"
    static var description = IntentDescription("افتح وتيرة وأنهِ مؤقت الراحة الحالي.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("skipRest", forKey: "pendingWorkoutAction")
        NotificationCenter.default.post(name: .workoutShortcutRequested, object: nil)
        return .result()
    }
}

struct PauseWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "أوقف التمرين مؤقتًا"
    static var description = IntentDescription("افتح وتيرة وأوقف جلستك الحالية مؤقتًا دون إنهائها.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set("pause", forKey: "pendingWorkoutAction")
        NotificationCenter.default.post(name: .workoutShortcutRequested, object: nil)
        return .result()
    }
}

struct WorkoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTodayWorkoutIntent(),
                    phrases: ["ابدأ تمرين اليوم في \(.applicationName)", "ابدأ التمرين في \(.applicationName)"],
                    shortTitle: "ابدأ تمرين اليوم", systemImageName: "dumbbell.fill")
        AppShortcut(intent: OpenWeeklyReportIntent(), phrases: ["اعرض تقرير الأسبوع في \(.applicationName)"], shortTitle: "تقرير الأسبوع", systemImageName: "chart.bar.doc.horizontal")
        AppShortcut(intent: SkipRestIntent(), phrases: ["أنه الراحة في \(.applicationName)"], shortTitle: "إنهاء الراحة", systemImageName: "timer")
        AppShortcut(intent: PauseWorkoutIntent(), phrases: ["أوقف التمرين مؤقتًا في \(.applicationName)"], shortTitle: "إيقاف مؤقت", systemImageName: "pause.circle")
    }
}
