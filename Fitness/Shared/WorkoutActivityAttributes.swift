import ActivityKit
import Foundation

// Compiled into both targets. The extension reads a small snapshot, never the database.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var workoutTitle: String
        var startedAt: Date
        var timerReferenceDate: Date
        var elapsedSeconds: Int
        var completedSets: Int
        var restDeadline: Date?
        var isPaused: Bool
        var useArabicDigits: Bool
    }

    var sessionID: String
}

struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var todayTitle: String
    var nextTitle: String
    var nextDate: Date?
    var streak: Int
    var completedThisWeek: Int
    var useArabicDigits: Bool
    var activeWorkoutTitle: String?
    var schedule: [WidgetScheduledDay] = []
    var completedWorkoutDates: [Date] = []
    var weekStart: Int = 7

    static var empty: WidgetSnapshot {
        WidgetSnapshot(generatedAt: .now, todayTitle: "لا يوجد تمرين مجدول", nextTitle: "أضف خطة للبدء",
                       nextDate: nil, streak: 0, completedThisWeek: 0, useArabicDigits: true,
                       activeWorkoutTitle: nil)
    }
}

struct WidgetScheduledDay: Codable, Sendable {
    var date: Date
    var title: String
    var isRest: Bool
    var isCompleted: Bool
}

enum SharedWorkoutStorage {
    static var groupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "SharedAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var defaults: UserDefaults? {
        guard let identifier = groupIdentifier else { return nil }
        return UserDefaults(suiteName: identifier)
    }

    static var snapshotURL: URL? {
        guard let identifier = groupIdentifier,
              let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
        else { return nil }
        return directory.appendingPathComponent("workout-widget.json")
    }

    static func readSnapshot() -> WidgetSnapshot {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    static func writeSnapshot(_ snapshot: WidgetSnapshot) throws {
        guard let url = snapshotURL else { throw SharedStorageError.unavailable }
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func requestStartToday() {
        defaults?.set(true, forKey: "pendingStartToday")
        // App Intents execute in the app target. This fallback also supports an unsigned simulator.
        UserDefaults.standard.set(true, forKey: "pendingStartToday")
    }

    static func consumeStartToday() -> Bool {
        let requested = defaults?.bool(forKey: "pendingStartToday") == true ||
            UserDefaults.standard.bool(forKey: "pendingStartToday")
        defaults?.removeObject(forKey: "pendingStartToday")
        UserDefaults.standard.removeObject(forKey: "pendingStartToday")
        return requested
    }
}

enum SharedStorageError: LocalizedError {
    case unavailable

    var errorDescription: String? { "تعذر الوصول إلى مساحة الويدجت. تحقق من توقيع مجموعة التطبيقات." }
}

enum WidgetArabic {
    static func digits(_ value: Int, arabic: Bool) -> String {
        let source = String(value)
        guard arabic else { return source }
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                            "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(source.map { map[$0] ?? $0 })
    }

    static func locale(arabic: Bool) -> Locale {
        Locale(identifier: arabic ? "ar_SA@numbers=arab" : "ar_SA@numbers=latn")
    }
}
