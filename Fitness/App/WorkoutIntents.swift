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
}

struct WorkoutShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartTodayWorkoutIntent(),
                    phrases: ["ابدأ تمرين اليوم في \(.applicationName)", "ابدأ التمرين في \(.applicationName)"],
                    shortTitle: "ابدأ تمرين اليوم", systemImageName: "dumbbell.fill")
    }
}
